import AVFoundation
import Accelerate
import FramePeekCore

// MARK: - Waveform Extraction

/// Extracts waveform data from an audio track
/// Processes audio in time-based windows to avoid loading entire file into memory
/// Uses Accelerate for fast peak detection within each window
public func extractWaveformFast(
    asset: AVAsset,
    audioTrack: AVAssetTrack,
    durationSeconds: Double,
    maxSamples: Int = 2000
) -> AsyncStream<WaveformUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let emptyFinish = WaveformUpdate(appendedSamples: [], isFinished: true)
            
            guard durationSeconds > 0, maxSamples > 0 else {
                continuation.yield(emptyFinish)
                continuation.finish()
                return
            }
            
            guard let reader = try? AVAssetReader(asset: asset) else {
                continuation.yield(emptyFinish)
                continuation.finish()
                return
            }
            
            // Request 32-bit float, mono output
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1  // Mix down to mono
            ]
            
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            
            guard reader.canAdd(output) else {
                continuation.yield(emptyFinish)
                continuation.finish()
                return
            }
            
            reader.add(output)
            
            guard reader.startReading() else {
                continuation.yield(emptyFinish)
                continuation.finish()
                return
            }
            
            // Calculate time window for each output sample
            let windowDuration = durationSeconds / Double(maxSamples)
            
            // Results array
            var results = [WaveformSample]()
            results.reserveCapacity(maxSamples)
            
            // Current window tracking
            var currentWindowIndex = 0
            var currentWindowPeak: Float = 0
            var currentWindowSamples = [Float]()
            currentWindowSamples.reserveCapacity(8192) // Buffer for samples in current window
            
            // Progress tracking for UI updates
            var lastYieldTime = Date.now
            var lastYieldedCount = 0
            let yieldInterval: TimeInterval = 0.15
            
            // Process buffers
            while !Task.isCancelled {
                autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else {
                        return
                    }
                    
                    // Get timing info
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    let bufferDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
                    
                    guard pts.isFinite, bufferDuration.isFinite, bufferDuration > 0 else {
                        return
                    }
                    
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
                    
                    let floatCount = length / MemoryLayout<Float>.size
                    guard floatCount > 0 else { return }
                    
                    let timePerSample = bufferDuration / Double(floatCount)
                    
                    data.withMemoryRebound(to: Float.self, capacity: floatCount) { floatPtr in
                        for i in 0..<floatCount {
                            let sampleTime = pts + Double(i) * timePerSample
                            let targetWindowIndex = min(Int(sampleTime / windowDuration), maxSamples - 1)
                            
                            // If we've moved to a new window, finalize the previous one
                            while currentWindowIndex < targetWindowIndex && currentWindowIndex < maxSamples {
                                // Use Accelerate to find max in accumulated samples
                                let peak: Float
                                if currentWindowSamples.isEmpty {
                                    peak = currentWindowPeak
                                } else {
                                    var maxVal: Float = 0
                                    vDSP_maxv(currentWindowSamples, 1, &maxVal, vDSP_Length(currentWindowSamples.count))
                                    peak = max(maxVal, currentWindowPeak)
                                }
                                
                                let time = (Double(currentWindowIndex) + 0.5) * windowDuration
                                let amplitude = Double(min(peak, 1.0))
                                
                                results.append(WaveformSample(
                                    time: time,
                                    amplitude: amplitude,
                                    minAmplitude: amplitude,
                                    maxAmplitude: amplitude
                                ))
                                
                                currentWindowIndex += 1
                                currentWindowPeak = 0
                                currentWindowSamples.removeAll(keepingCapacity: true)
                            }
                            
                            // Add sample to current window (absolute value)
                            let absValue = abs(floatPtr[i])
                            
                            // Keep buffer small - if too many samples, just track peak
                            if currentWindowSamples.count < 50000 {
                                currentWindowSamples.append(absValue)
                            } else if absValue > currentWindowPeak {
                                currentWindowPeak = absValue
                            }
                        }
                    }
                }
                
                if reader.status != .reading {
                    break
                }
                
                // Progressive UI updates
                let now = Date.now
                if now.timeIntervalSince(lastYieldTime) >= yieldInterval && results.count > lastYieldedCount {
                    let newSamples = Array(results[lastYieldedCount...])
                    continuation.yield(WaveformUpdate(appendedSamples: newSamples, isFinished: false))
                    lastYieldedCount = results.count
                    lastYieldTime = now
                }
            }
            
            reader.cancelReading()
            
            // Finalize last window
            if currentWindowIndex < maxSamples {
                let peak: Float
                if currentWindowSamples.isEmpty {
                    peak = currentWindowPeak
                } else {
                    var maxVal: Float = 0
                    vDSP_maxv(currentWindowSamples, 1, &maxVal, vDSP_Length(currentWindowSamples.count))
                    peak = max(maxVal, currentWindowPeak)
                }
                
                let time = (Double(currentWindowIndex) + 0.5) * windowDuration
                let amplitude = Double(min(peak, 1.0))
                
                results.append(WaveformSample(
                    time: time,
                    amplitude: amplitude,
                    minAmplitude: amplitude,
                    maxAmplitude: amplitude
                ))
            }
            
            // Send remaining results
            if results.count > lastYieldedCount {
                let newSamples = Array(results[lastYieldedCount...])
                continuation.yield(WaveformUpdate(appendedSamples: newSamples, isFinished: true))
            } else {
                continuation.yield(WaveformUpdate(appendedSamples: [], isFinished: true))
            }
            continuation.finish()
        }
        
        continuation.onTermination = { _ in task.cancel() }
    }
}
