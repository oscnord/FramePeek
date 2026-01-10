import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Extracts waveform data from an audio track
/// - Parameters:
///   - asset: The AVAsset containing the audio track
///   - audioTrack: The audio track to extract waveform from
///   - durationSeconds: Duration of the audio track in seconds
///   - maxSamples: Maximum number of waveform samples to return (for downsampling)
/// - Returns: Array of WaveformSample representing the waveform
func extractWaveform(
    asset: AVAsset,
    audioTrack: AVAssetTrack,
    durationSeconds: Double,
    maxSamples: Int = 2000
) async -> [WaveformSample] {
    guard durationSeconds > 0, maxSamples > 0 else { return [] }
    
    guard let reader = try? AVAssetReader(asset: asset) else {
        return []
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
        return []
    }
    
    reader.add(output)
    
    guard reader.startReading() else {
        return []
    }
    
    // Calculate window size based on target sample count
    let windowSize = durationSeconds / Double(maxSamples)
    let minWindowSize = 0.01 // Minimum 10ms windows
    let actualWindowSize = max(windowSize, minWindowSize)
    
    var allSamples: [WaveformSample] = []
    var currentWindowStart: Double = 0
    var windowSamples: [Int16] = []
    windowSamples.reserveCapacity(Int(actualWindowSize * 48000)) // Pre-allocate for typical sample rates
    
    while let sampleBuffer = output.copyNextSampleBuffer() {
        if Task.isCancelled { break }
        
        autoreleasepool {
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
            
            // Convert to Int16 samples (assuming 16-bit PCM, interleaved)
            let sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { return }
            
            // Work directly with UnsafeBufferPointer to avoid array copy
            let samplesBuffer = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                UnsafeBufferPointer(start: ptr, count: sampleCount)
            }
            
            let bufferDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
            let timeStep = bufferDuration / Double(sampleCount)
            
            // Process samples - accumulate into windows
            for (index, sample) in samplesBuffer.enumerated() {
                let sampleTime = pts + Double(index) * timeStep
                
                // Check if we need to finalize current window
                while sampleTime >= currentWindowStart + actualWindowSize && currentWindowStart < durationSeconds {
                    if !windowSamples.isEmpty {
                        finalizeWindow(
                            samples: windowSamples,
                            windowStart: currentWindowStart,
                            windowSize: actualWindowSize,
                            allSamples: &allSamples
                        )
                    }
                    
                    // Move to next window
                    currentWindowStart += actualWindowSize
                    windowSamples.removeAll(keepingCapacity: true)
                }
                
                // Add sample to current window
                windowSamples.append(sample)
            }
        }
    }
    
    reader.cancelReading()
    
    // Process any remaining samples in final window
    if !windowSamples.isEmpty && currentWindowStart < durationSeconds {
        finalizeWindow(
            samples: windowSamples,
            windowStart: currentWindowStart,
            windowSize: actualWindowSize,
            allSamples: &allSamples
        )
    }
    
    // Downsample if needed
    if allSamples.count > maxSamples {
        return downsampleWaveformLTTB(allSamples, targetCount: maxSamples)
    }
    
    return allSamples
}

/// Finalize a window by calculating RMS, min, and max using Accelerate framework
private func finalizeWindow(
    samples: [Int16],
    windowStart: Double,
    windowSize: Double,
    allSamples: inout [WaveformSample]
) {
    guard !samples.isEmpty else { return }
    
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
    let normalizedMin = abs(Double(minValue) / 32768.0)
    let normalizedMax = abs(Double(maxValue) / 32768.0)
    
    allSamples.append(WaveformSample(
        time: windowStart + windowSize / 2.0,
        amplitude: normalizedAmplitude,
        minAmplitude: normalizedMin,
        maxAmplitude: normalizedMax
    ))
}

/// Downsample waveform samples using LTTB algorithm
private func downsampleWaveformLTTB(_ samples: [WaveformSample], targetCount: Int) -> [WaveformSample] {
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
        
        // Calculate the average point for the next bucket (used as target)
        let nextBucketStart = bucketEnd
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, samples.count - 1)
        
        var avgX: Double = 0
        var avgY: Double = 0
        let nextBucketCount = nextBucketEnd - nextBucketStart + 1
        
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
            // Triangle area using cross product
            let area = abs(
                (pointA.time - avgX) * (pointB.amplitude - pointA.amplitude) -
                (pointA.time - pointB.time) * (avgY - pointA.amplitude)
            ) * 0.5
            
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

