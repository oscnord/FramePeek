import AVFoundation
import CoreMedia
import Accelerate

// MARK: - Fast Waveform Extraction

/// Fast waveform extraction using lower sample rate decoding
/// This produces accurate amplitude data (unlike packet-size approximation)
/// while being significantly faster than full-rate decoding.
///
/// Speed optimizations:
/// 1. Requests 8kHz sample rate (6x less data than 48kHz)
/// 2. Uses mono output (half the data for stereo sources)
/// 3. Aggressive buffer skipping for long files
/// 4. Early termination when enough samples collected
func extractWaveformFast(
    asset: AVAsset,
    audioTrack: AVAssetTrack,
    durationSeconds: Double,
    maxSamples: Int = 2000
) -> AsyncStream<WaveformUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = WaveformUpdate(appendedSamples: [], isFinished: true)

            guard durationSeconds > 0, maxSamples > 0 else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            guard let reader = try? AVAssetReader(asset: asset) else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Use low sample rate for speed - 8kHz is enough for waveform visualization
            // This is the key optimization: 6x less data to decode than 48kHz
            let targetSampleRate: Double = 8000

            // Configure output for low-rate mono PCM audio
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: targetSampleRate,
                AVNumberOfChannelsKey: 1, // Mono - halves data for stereo
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]

            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            reader.add(output)

            guard reader.startReading() else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Calculate window size based on target sample count
            let windowSize = durationSeconds / Double(maxSamples)
            let minWindowSize = 0.01 // Minimum 10ms windows
            let actualWindowSize = max(windowSize, minWindowSize)

            // At 8kHz, we get ~8000 samples/second
            // For a 2-hour file (7200s) with 2000 output samples, that's 3.6s windows
            // Each 3.6s window has ~28,800 samples - still a lot, so we skip buffers

            // Calculate buffer skip interval based on duration
            // More aggressive skipping for longer files
            let skipInterval: Int
            if durationSeconds > 7200 { // > 2 hours
                skipInterval = 8
            } else if durationSeconds > 3600 { // > 1 hour
                skipInterval = 6
            } else if durationSeconds > 1800 { // > 30 min
                skipInterval = 4
            } else if durationSeconds > 600 { // > 10 min
                skipInterval = 3
            } else if durationSeconds > 120 { // > 2 min
                skipInterval = 2
            } else {
                skipInterval = 1 // Read all buffers for short files
            }

            var allSamples: [WaveformSample] = []
            allSamples.reserveCapacity(maxSamples + 100)

            var currentWindowStart: Double = 0
            var windowSamples: [Int16] = []
            windowSamples.reserveCapacity(Int(actualWindowSize * targetSampleRate * 1.5))

            var bufferIndex = 0
            var lastYieldTime = Date()
            var lastYieldedCount = 0
            let yieldInterval: TimeInterval = 0.08 // Yield every 80ms for responsive UI
            var shouldBreak = false

            while !Task.isCancelled && !shouldBreak {
                autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else {
                        shouldBreak = true
                        return
                    }

                    // Skip buffers for speed
                    bufferIndex += 1
                    if bufferIndex % skipInterval != 0 {
                        return
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    guard pts.isFinite else { return }

                    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                        return
                    }

                    var length: Int = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    let status = CMBlockBufferGetDataPointer(
                        blockBuffer,
                        atOffset: 0,
                        lengthAtOffsetOut: nil,
                        totalLengthOut: &length,
                        dataPointerOut: &dataPointer
                    )

                    guard status == noErr, let data = dataPointer, length > 0 else {
                        return
                    }

                    let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
                    guard numSamples > 0 else { return }

                    let bufferDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
                    let timeStep = bufferDuration / Double(numSamples)

                    let sampleCount = length / MemoryLayout<Int16>.size
                    guard sampleCount > 0 else { return }

                    // Process samples
                    data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                        let samplesBuffer = UnsafeBufferPointer(start: ptr, count: sampleCount)

                        for i in 0..<sampleCount {
                            let sampleTime = pts + Double(i) * timeStep

                            // Finalize window if needed
                            while sampleTime >= currentWindowStart + actualWindowSize && currentWindowStart < durationSeconds {
                                if !windowSamples.isEmpty {
                                    let newSample = finalizeWindowFast(
                                        samples: windowSamples,
                                        windowStart: currentWindowStart,
                                        windowSize: actualWindowSize
                                    )
                                    allSamples.append(newSample)
                                }
                                currentWindowStart += actualWindowSize
                                windowSamples.removeAll(keepingCapacity: true)
                            }

                            windowSamples.append(samplesBuffer[i])
                        }
                    }

                    // Early termination for very long files
                    // Once we have 1.5x the needed samples and are past 40% of the file, stop
                    if allSamples.count >= Int(Double(maxSamples) * 1.5) && currentWindowStart > durationSeconds * 0.4 {
                        if !windowSamples.isEmpty {
                            let newSample = finalizeWindowFast(
                                samples: windowSamples,
                                windowStart: currentWindowStart,
                                windowSize: actualWindowSize
                            )
                            allSamples.append(newSample)
                        }
                        shouldBreak = true
                        return
                    }

                    // Progressive UI updates
                    let now = Date()
                    if now.timeIntervalSince(lastYieldTime) >= yieldInterval && allSamples.count > lastYieldedCount {
                        let newSamples = Array(allSamples[lastYieldedCount...])
                        continuation.yield(WaveformUpdate(appendedSamples: newSamples, isFinished: false))
                        lastYieldedCount = allSamples.count
                        lastYieldTime = now
                    }
                }

                if reader.status != .reading {
                    break
                }
            }

            reader.cancelReading()

            // Finalize remaining window
            if !windowSamples.isEmpty && currentWindowStart < durationSeconds {
                let newSample = finalizeWindowFast(
                    samples: windowSamples,
                    windowStart: currentWindowStart,
                    windowSize: actualWindowSize
                )
                allSamples.append(newSample)
            }

            // Downsample if needed
            let finalSamples: [WaveformSample]
            if allSamples.count > maxSamples {
                finalSamples = downsampleWaveformLTTB(allSamples, targetCount: maxSamples)
            } else {
                finalSamples = allSamples
            }

            continuation.yield(WaveformUpdate(appendedSamples: finalSamples, isFinished: true))
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Helper Functions

/// Finalize a window using Accelerate for fast vectorized operations
private func finalizeWindowFast(
    samples: [Int16],
    windowStart: Double,
    windowSize: Double
) -> WaveformSample {
    guard !samples.isEmpty else {
        return WaveformSample(
            time: windowStart + windowSize / 2.0,
            amplitude: 0.0,
            minAmplitude: 0.0,
            maxAmplitude: 0.0
        )
    }

    let count = vDSP_Length(samples.count)

    // Convert Int16 to Float for Accelerate
    var floatSamples = [Float](repeating: 0, count: samples.count)
    vDSP_vflt16(samples, 1, &floatSamples, 1, count)

    // Calculate RMS (root mean square) for average amplitude
    var rms: Float = 0
    vDSP_rmsqv(floatSamples, 1, &rms, count)

    // Calculate min and max for envelope
    var minValue: Float = 0
    var maxValue: Float = 0
    vDSP_minv(floatSamples, 1, &minValue, count)
    vDSP_maxv(floatSamples, 1, &maxValue, count)

    // Normalize to 0.0-1.0 range
    let normalizedAmplitude = min(1.0, Double(rms) / 32768.0)
    let absMin = abs(Double(minValue))
    let absMax = abs(Double(maxValue))
    let normalizedMin = min(absMin, absMax) / 32768.0
    let normalizedMax = max(absMin, absMax) / 32768.0

    return WaveformSample(
        time: windowStart + windowSize / 2.0,
        amplitude: normalizedAmplitude,
        minAmplitude: normalizedMin,
        maxAmplitude: normalizedMax
    )
}
