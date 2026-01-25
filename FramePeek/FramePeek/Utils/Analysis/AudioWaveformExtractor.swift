import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Extracts waveform data from an audio track with progressive updates
/// - Parameters:
///   - asset: The AVAsset containing the audio track
///   - audioTrack: The audio track to extract waveform from
///   - durationSeconds: Duration of the audio track in seconds
///   - maxSamples: Maximum number of waveform samples to return (for downsampling)
/// - Returns: AsyncStream of WaveformUpdate with progressive samples
public func extractWaveform(
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

            // Configure output for PCM audio
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
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

            // Calculate sampling strategy: estimate how many buffers we'll encounter
            // Typical audio has ~10-50 buffers per second depending on codec and container
            // For long files, we want to sample strategically to avoid reading everything
            let estimatedBuffersPerSecond = 20.0 // Conservative estimate
            let estimatedTotalBuffers = Int(durationSeconds * estimatedBuffersPerSecond)

            // Target: read enough buffers to get good coverage (2-3x maxSamples)
            // For very long files, sample more aggressively
            let targetBuffersToRead: Int
            if durationSeconds > 3600 { // > 1 hour
                targetBuffersToRead = maxSamples * 3
            } else if durationSeconds > 600 { // > 10 minutes
                targetBuffersToRead = maxSamples * 4
            } else {
                targetBuffersToRead = maxSamples * 5 // Shorter files: read more for accuracy
            }

            let bufferSkipInterval = max(1, estimatedTotalBuffers / max(targetBuffersToRead, 1))

            var allSamples: [WaveformSample] = []
            var currentWindowStart: Double = 0
            var windowSamples: [Int16] = []
            windowSamples.reserveCapacity(Int(actualWindowSize * 48000)) // Pre-allocate for typical sample rates

            var bufferIndex = 0
            var lastYieldTime = Date()
            var lastYieldedCount = 0
            let yieldInterval: TimeInterval = 0.1 // Yield every 100ms for UI responsiveness
            var shouldBreak = false

            while !Task.isCancelled && !shouldBreak {
                autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else {
                        shouldBreak = true
                        return
                    }

                    // Sample buffers strategically - skip some to speed up processing
                    if bufferIndex % bufferSkipInterval != 0 {
                        bufferIndex += 1
                        return
                    }
                    bufferIndex += 1

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

                    // Get the actual number of audio frames (not interleaved samples)
                    // For stereo audio, interleavedSampleCount would be 2x the number of frames
                    let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
                    guard numFrames > 0 else { return }

                    let bufferDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
                    // Use frame count for time step, not interleaved sample count
                    let timeStep = bufferDuration / Double(numFrames)

                    // Calculate interleaved sample count for buffer access
                    let interleavedSampleCount = length / MemoryLayout<Int16>.size
                    guard interleavedSampleCount > 0 else { return }

                    // Determine channel count from interleaved samples vs frames
                    let channelCount = max(1, interleavedSampleCount / numFrames)

                    // Process samples safely inside withMemoryRebound closure
                    // to avoid undefined behavior from escaping pointer
                    data.withMemoryRebound(to: Int16.self, capacity: interleavedSampleCount) { ptr in
                        let samplesBuffer = UnsafeBufferPointer(start: ptr, count: interleavedSampleCount)

                        // Process by frame (mixing channels if stereo)
                        for frameIdx in 0..<numFrames {
                            let sampleTime = pts + Double(frameIdx) * timeStep

                            // Check if we need to finalize current window
                            while sampleTime >= currentWindowStart + actualWindowSize && currentWindowStart < durationSeconds {
                                if !windowSamples.isEmpty {
                                    let newSample = finalizeWindow(
                                        samples: windowSamples,
                                        windowStart: currentWindowStart,
                                        windowSize: actualWindowSize
                                    )
                                    allSamples.append(newSample)
                                }

                                // Move to next window
                                currentWindowStart += actualWindowSize
                                windowSamples.removeAll(keepingCapacity: true)
                            }

                            // Mix channels by averaging for this frame
                            let baseIndex = frameIdx * channelCount
                            if channelCount == 1 {
                                windowSamples.append(samplesBuffer[baseIndex])
                            } else {
                                // Mix stereo/multi-channel to mono by averaging
                                var sum: Int32 = 0
                                for ch in 0..<channelCount {
                                    let idx = baseIndex + ch
                                    if idx < interleavedSampleCount {
                                        sum += Int32(samplesBuffer[idx])
                                    }
                                }
                                let mixed = Int16(clamping: sum / Int32(channelCount))
                                windowSamples.append(mixed)
                            }
                        }
                    }

                    // Early termination: if we have enough samples and we're past the midpoint, we can stop
                    // This speeds up long files significantly
                    if allSamples.count >= maxSamples && currentWindowStart > durationSeconds * 0.5 {
                        // We have enough data, finalize remaining window and break
                        if !windowSamples.isEmpty {
                            let newSample = finalizeWindow(
                                samples: windowSamples,
                                windowStart: currentWindowStart,
                                windowSize: actualWindowSize
                            )
                            allSamples.append(newSample)
                        }
                        shouldBreak = true
                        return
                    }

                    // Yield progressive updates periodically
                    let now = Date()
                    if now.timeIntervalSince(lastYieldTime) >= yieldInterval && allSamples.count > lastYieldedCount {
                        let newSamples = Array(allSamples[lastYieldedCount...])
                        continuation.yield(WaveformUpdate(appendedSamples: newSamples, isFinished: false))
                        lastYieldedCount = allSamples.count
                        lastYieldTime = now
                    }
                }

                // Check if reader is done
                if reader.status != .reading {
                    break
                }
            }

            reader.cancelReading()

            // Process any remaining samples in final window
            if !windowSamples.isEmpty && currentWindowStart < durationSeconds {
                let newSample = finalizeWindow(
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

            // FIX: After downsampling, indices no longer correspond to pre-downsampling array
            // Always yield the complete final result to avoid index mismatches
            continuation.yield(WaveformUpdate(appendedSamples: finalSamples, isFinished: true))
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Finalize a window by calculating RMS, min, and max using Accelerate framework
public func finalizeWindow(
    samples: [Int16],
    windowStart: Double,
    windowSize: Double
) -> WaveformSample {
    guard !samples.isEmpty else {
        return WaveformSample(time: windowStart + windowSize / 2.0, amplitude: 0.0, minAmplitude: 0.0, maxAmplitude: 0.0)
    }

    let count = vDSP_Length(samples.count)

    // Convert Int16 to Float for Accelerate operations
    var floatSamples = [Float](repeating: 0, count: samples.count)
    vDSP_vflt16(samples, 1, &floatSamples, 1, count)

    // Calculate RMS using vDSP (vectorized)
    var rms: Float = 0
    vDSP_rmsqv(floatSamples, 1, &rms, count)

    // Calculate min and max using vDSP (vectorized)
    var minValue: Float = 0
    var maxValue: Float = 0
    vDSP_minv(floatSamples, 1, &minValue, count)
    vDSP_maxv(floatSamples, 1, &maxValue, count)

    // Normalize to 0.0-1.0 range (Int16 range is -32768 to 32767, Float range is -32768.0 to 32767.0)
    let normalizedAmplitude = min(1.0, Double(rms) / 32768.0)
    // For min/max, we want the absolute amplitude envelope
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

/// Downsample waveform samples using LTTB algorithm
public func downsampleWaveformLTTB(_ samples: [WaveformSample], targetCount: Int) -> [WaveformSample] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }

    var result: [WaveformSample] = []
    result.reserveCapacity(targetCount)

    // Always include first point
    result.append(samples[0])

    let bucketSize = Double(samples.count - 2) / Double(targetCount - 2)
    var lastSelectedIndex = 0

    for i in 0..<(targetCount - 2) {
        // Calculate bucket boundaries
        let bucketStart = Int(Double(i) * bucketSize) + 1
        let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, samples.count - 1)

        // Guard against invalid bucket (bucketStart >= bucketEnd)
        guard bucketStart < bucketEnd else {
            // Just use bucketStart if bucket is empty/invalid
            if bucketStart < samples.count {
                result.append(samples[bucketStart])
                lastSelectedIndex = bucketStart
            }
            continue
        }

        // Calculate the average point for the next bucket (used as target)
        let nextBucketStart = bucketEnd
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, samples.count - 1)

        // Guard against invalid next bucket range
        guard nextBucketStart <= nextBucketEnd else {
            result.append(samples[bucketStart])
            lastSelectedIndex = bucketStart
            continue
        }

        var avgX: Double = 0
        var avgY: Double = 0
        let nextBucketCount: Int = nextBucketEnd - nextBucketStart + 1

        // Guard against division by zero
        guard nextBucketCount > 0 else {
            result.append(samples[bucketStart])
            lastSelectedIndex = bucketStart
            continue
        }

        for j in nextBucketStart...nextBucketEnd {
            avgX += samples[j].time
            avgY += samples[j].amplitude
        }
        avgX /= Double(nextBucketCount)
        avgY /= Double(nextBucketCount)

        // Find the point in current bucket that creates largest triangle
        var maxArea: Double = -1
        var maxAreaIndex = bucketStart

        let pointA = samples[lastSelectedIndex]

        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            // Triangle area using cross product - break into sub-expressions for compiler
            let term1 = (pointA.time - avgX) * (pointB.amplitude - pointA.amplitude)
            let term2 = (pointA.time - pointB.time) * (avgY - pointA.amplitude)
            let area = abs(term1 - term2) * 0.5

            if area > maxArea {
                maxArea = area
                maxAreaIndex = j
            }
        }

        result.append(samples[maxAreaIndex])
        lastSelectedIndex = maxAreaIndex
    }

    // Always include last point
    result.append(samples[samples.count - 1])

    return result
}
