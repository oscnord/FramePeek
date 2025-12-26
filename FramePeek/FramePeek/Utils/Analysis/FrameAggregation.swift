//
//  FrameAggregation.swift
//  FramePeek
//
//  Created for smart visualization mode switching
//

import Foundation

/// Raw frame data: presentation timestamp and size in bytes
typealias RawFrame = (pts: Double, size: Int64)

/// Aggregates raw frame data into BitrateSamples based on visualization mode
func aggregateFrames(
    rawFrames: [RawFrame],
    mode: BitrateVisualizationMode,
    averageFPS: Double?,
    maxSamples: Int = 2000
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    let estimatedFPS = averageFPS ?? 30.0
    let defaultFrameDuration = 1.0 / estimatedFPS
    
    switch mode {
    case .second:
        return aggregateBySecond(rawFrames: rawFrames, maxSamples: maxSamples, defaultFrameDuration: defaultFrameDuration)
    case .frame:
        return aggregateByFrame(rawFrames: rawFrames, maxSamples: maxSamples, defaultFrameDuration: defaultFrameDuration)
    case .gop:
        return aggregateByGOP(rawFrames: rawFrames, maxSamples: maxSamples, defaultFrameDuration: defaultFrameDuration)
    }
}

// MARK: - Second-based aggregation (fixed 1-second time buckets)

private func aggregateBySecond(
    rawFrames: [RawFrame],
    maxSamples: Int,
    defaultFrameDuration: Double
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    // Use fixed 1-second time buckets like ffprobe/mediainfo
    // This groups frames into discrete buckets: [0-1), [1-2), [2-3), etc.
    // and divides by exactly 1.0 second for accurate bitrate
    
    let bucketSize: Double = 1.0
    var samples: [BitrateSample] = []
    
    // Find the time range
    let startTime = rawFrames.first!.pts
    let endTime = rawFrames.last!.pts
    let totalDuration = endTime - startTime + defaultFrameDuration
    
    // Calculate number of buckets
    let numBuckets = Int(ceil(totalDuration / bucketSize))
    guard numBuckets > 0 else { return [] }
    
    // Determine step size if we need to skip buckets to stay under maxSamples
    let bucketStep = max(1, numBuckets / maxSamples)
    
    samples.reserveCapacity(min(maxSamples, numBuckets))
    
    // Pre-sort frames (should already be sorted, but ensure it)
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    
    // Group frames into fixed time buckets
    var frameIndex = 0
    var bucketIndex = 0
    
    while bucketIndex < numBuckets && samples.count < maxSamples {
        let bucketStart = startTime + Double(bucketIndex) * bucketSize
        let bucketEnd = bucketStart + bucketSize
        
        // Sum all frame sizes in this bucket
        var totalBytes: Int64 = 0
        var framesInBucket = 0
        
        // Advance to first frame in this bucket
        while frameIndex < sortedFrames.count && sortedFrames[frameIndex].pts < bucketStart {
            frameIndex += 1
        }
        
        // Sum frames in bucket [bucketStart, bucketEnd)
        var tempIndex = frameIndex
        while tempIndex < sortedFrames.count && sortedFrames[tempIndex].pts < bucketEnd {
            totalBytes += sortedFrames[tempIndex].size
            framesInBucket += 1
            tempIndex += 1
        }
        
        // Only emit if bucket has frames
        if framesInBucket > 0 {
            // Bitrate = total bits / bucket duration (exactly 1.0 second)
            let bitrate = (Double(totalBytes) * 8.0) / bucketSize
            let sampleTime = bucketStart + bucketSize / 2.0 // Center of bucket
            
            samples.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: bucketSize))
        }
        
        bucketIndex += bucketStep
    }
    
    return samples
}

// MARK: - Frame-based aggregation (per-frame bitrate)

private func aggregateByFrame(
    rawFrames: [RawFrame],
    maxSamples: Int,
    defaultFrameDuration: Double
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    var samples: [BitrateSample] = []
    samples.reserveCapacity(min(maxSamples, rawFrames.count))
    
    // Pre-sort frames by PTS (should already be sorted, but ensure it)
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    
    // If we have too many frames, sample them
    let step = max(1, sortedFrames.count / maxSamples)
    
    for i in stride(from: 0, to: sortedFrames.count, by: step) {
        let frame = sortedFrames[i]
        
        // Calculate frame duration from actual frame timing
        let frameDuration: Double
        if i + 1 < sortedFrames.count {
            let nextDuration = sortedFrames[i + 1].pts - frame.pts
            // Use actual duration if it's positive and reasonable
            frameDuration = nextDuration > 0 ? nextDuration : defaultFrameDuration
        } else if i > 0 {
            // Last frame: use previous frame's duration
            let prevDuration = frame.pts - sortedFrames[i - 1].pts
            frameDuration = prevDuration > 0 ? prevDuration : defaultFrameDuration
        } else {
            frameDuration = defaultFrameDuration
        }
        
        // Bitrate = frame bits / frame duration
        let bitrate = (Double(frame.size) * 8.0) / frameDuration
        
        samples.append(BitrateSample(time: frame.pts, bitrate: bitrate, duration: frameDuration))
        
        if samples.count >= maxSamples {
            break
        }
    }
    
    return samples
}

// MARK: - GOP-based aggregation (per-GOP bitrate)

private func aggregateByGOP(
    rawFrames: [RawFrame],
    maxSamples: Int,
    defaultFrameDuration: Double
) -> [BitrateSample] {
    guard rawFrames.count > 1 else {
        // Single frame or empty - treat as one GOP
        if let frame = rawFrames.first {
            let bitrate = (Double(frame.size) * 8.0) / defaultFrameDuration
            return [BitrateSample(time: frame.pts, bitrate: bitrate, duration: defaultFrameDuration)]
        }
        return []
    }
    
    // Pre-sort frames by PTS
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    
    var samples: [BitrateSample] = []
    samples.reserveCapacity(min(maxSamples, sortedFrames.count / 10)) // GOPs are typically 10-30 frames
    
    // Estimate typical frame interval from first 100 frames
    var intervals: [Double] = []
    for i in 1..<min(sortedFrames.count, 100) {
        let interval = sortedFrames[i].pts - sortedFrames[i-1].pts
        if interval > 0 {
            intervals.append(interval)
        }
    }
    let typicalInterval = intervals.isEmpty ? defaultFrameDuration : intervals.sorted()[intervals.count / 2]
    
    // Detect GOP boundaries by looking for:
    // 1. Large time gaps (keyframes often have slightly larger gaps)
    // 2. Frame size spikes (I-frames are typically larger)
    // 3. Fallback to fixed-size groups if no clear boundaries detected
    
    let gopBoundaryThreshold = typicalInterval * 1.8
    var currentGOP: [RawFrame] = []
    var previousPTS: Double?
    var previousSize: Int64?
    
    // Calculate average frame size for size-based detection
    let avgFrameSize = sortedFrames.reduce(0) { $0 + $1.size } / Int64(sortedFrames.count)
    let sizeSpikeThreshold = Double(avgFrameSize) * 1.5
    
    for (index, frame) in sortedFrames.enumerated() {
        var isGOPBoundary = false
        
        if let prev = previousPTS {
            let gap = frame.pts - prev
            
            // Check for time gap
            if gap > gopBoundaryThreshold {
                isGOPBoundary = true
            }
            
            // Check for size spike (I-frames are typically much larger)
            if let prevSize = previousSize, Double(frame.size) > sizeSpikeThreshold && Double(frame.size) > Double(prevSize) * 1.3 {
                isGOPBoundary = true
            }
        }
        
        if isGOPBoundary && !currentGOP.isEmpty {
            // Emit the previous GOP with correct duration calculation
            let gopStart = currentGOP.first!.pts
            let gopEnd = currentGOP.last!.pts
            
            // GOP duration should include the last frame's duration
            // Use the gap to the next frame (current frame) as the last frame's duration
            let lastFrameDuration = frame.pts - gopEnd
            let gopDuration = (gopEnd - gopStart) + (lastFrameDuration > 0 ? lastFrameDuration : typicalInterval)
            
            let totalBytes = currentGOP.reduce(0) { $0 + $1.size }
            let bitrate = (Double(totalBytes) * 8.0) / gopDuration
            
            samples.append(BitrateSample(time: gopEnd, bitrate: bitrate, duration: gopDuration))
            
            currentGOP.removeAll()
            
            if samples.count >= maxSamples {
                break
            }
        }
        
        currentGOP.append(frame)
        previousPTS = frame.pts
        previousSize = frame.size
    }
    
    // Emit the last GOP if any
    if !currentGOP.isEmpty && samples.count < maxSamples {
        let gopStart = currentGOP.first!.pts
        let gopEnd = currentGOP.last!.pts
        
        // For the last GOP, add typical frame duration for the last frame
        let gopDuration = (gopEnd - gopStart) + typicalInterval
        
        let totalBytes = currentGOP.reduce(0) { $0 + $1.size }
        let bitrate = (Double(totalBytes) * 8.0) / max(gopDuration, typicalInterval)
        
        samples.append(BitrateSample(time: gopEnd, bitrate: bitrate, duration: gopDuration))
    }
    
    // Fallback: if we didn't detect any boundaries, create fixed-size GOPs
    if samples.isEmpty && sortedFrames.count > 0 {
        let framesPerGOP = max(1, sortedFrames.count / max(1, maxSamples))
        
        for i in stride(from: 0, to: sortedFrames.count, by: framesPerGOP) {
            let endIndex = min(i + framesPerGOP, sortedFrames.count)
            let gopFrames = Array(sortedFrames[i..<endIndex])
            
            guard let gopStart = gopFrames.first?.pts,
                  let gopEnd = gopFrames.last?.pts else { continue }
            
            // Calculate proper GOP duration
            let lastFrameDuration: Double
            if endIndex < sortedFrames.count {
                lastFrameDuration = sortedFrames[endIndex].pts - gopEnd
            } else {
                lastFrameDuration = typicalInterval
            }
            let gopDuration = (gopEnd - gopStart) + lastFrameDuration
            
            let totalBytes = gopFrames.reduce(0) { $0 + $1.size }
            let bitrate = (Double(totalBytes) * 8.0) / max(gopDuration, typicalInterval)
            
            samples.append(BitrateSample(time: gopEnd, bitrate: bitrate, duration: gopDuration))
            
            if samples.count >= maxSamples {
                break
            }
        }
    }
    
    return samples
}

