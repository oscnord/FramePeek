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
    
    // Pre-sort frames (should already be sorted, but ensure it)
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    
    // First, process ALL buckets to get complete data
    var allBucketSamples: [BitrateSample] = []
    allBucketSamples.reserveCapacity(numBuckets)
    
    var frameIndex = 0
    var bucketIndex = 0
    
    while bucketIndex < numBuckets {
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
            
            allBucketSamples.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: bucketSize))
        }
        
        bucketIndex += 1
    }
    
    // Now downsample to maxSamples if needed, ensuring we always include first and last buckets
    if allBucketSamples.count <= maxSamples {
        return allBucketSamples
    }
    
    // Downsample: always include first and last, then evenly sample the rest
    samples.reserveCapacity(maxSamples)
    
    // Always include first sample
    samples.append(allBucketSamples.first!)
    
    if maxSamples > 2 {
        // Calculate step to evenly distribute remaining samples
        let remainingSlots = maxSamples - 2 // Reserve one for first, one for last
        let step = Double(allBucketSamples.count - 2) / Double(remainingSlots)
        
        for i in 1..<remainingSlots {
            let sourceIndex = Int(round(Double(i) * step)) + 1
            if sourceIndex < allBucketSamples.count - 1 {
                samples.append(allBucketSamples[sourceIndex])
            }
        }
    }
    
    // Always include last sample
    if allBucketSamples.count > 1 {
        samples.append(allBucketSamples.last!)
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
    
    // Use a 1-second rolling window approach, but sample at frame intervals
    // This gives comparable bitrate values to seconds mode, but with frame-level granularity
    let windowSize: Double = 1.0
    
    // If we have too many frames, sample them
    let step = max(1, sortedFrames.count / maxSamples)
    
    // Use sliding window for efficiency
    var windowStartIndex = 0
    var windowEndIndex = 0
    var windowTotalBytes: Int64 = 0
    
    for i in stride(from: 0, to: sortedFrames.count, by: step) {
        let frame = sortedFrames[i]
        let windowStart = frame.pts - windowSize / 2.0
        let windowEnd = frame.pts + windowSize / 2.0
        
        // Advance window start index to remove frames before windowStart
        while windowStartIndex < windowEndIndex && sortedFrames[windowStartIndex].pts < windowStart {
            windowTotalBytes -= sortedFrames[windowStartIndex].size
            windowStartIndex += 1
        }
        
        // Advance window end index to include frames up to windowEnd
        while windowEndIndex < sortedFrames.count && sortedFrames[windowEndIndex].pts < windowEnd {
            windowTotalBytes += sortedFrames[windowEndIndex].size
            windowEndIndex += 1
        }
        
        // Calculate bitrate over the 1-second window (same as seconds mode)
        let bitrate = (Double(windowTotalBytes) * 8.0) / windowSize
        samples.append(BitrateSample(time: frame.pts, bitrate: bitrate, duration: windowSize))
        
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
            // GOP duration is from the start of the first frame to the start of the next GOP
            // The next GOP starts at the current frame's PTS
            let gopDuration = frame.pts - gopStart
            
            // Ensure duration is positive and reasonable
            let validDuration = max(gopDuration, typicalInterval)
            
            let totalBytes = currentGOP.reduce(0) { $0 + $1.size }
            let bitrate = (Double(totalBytes) * 8.0) / validDuration
            
            // Use the end of the GOP (last frame's PTS) as the sample time
            let gopEnd = currentGOP.last!.pts
            samples.append(BitrateSample(time: gopEnd, bitrate: bitrate, duration: validDuration))
            
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
        
        // For the last GOP, estimate duration from start to end plus one frame duration
        // This approximates the duration until the next GOP would start
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
            
            // Calculate proper GOP duration: from start of this GOP to start of next GOP
            let gopDuration: Double
            if endIndex < sortedFrames.count {
                // Next GOP starts at the next frame's PTS
                gopDuration = sortedFrames[endIndex].pts - gopStart
            } else {
                // Last GOP: estimate duration from start to end plus one frame
                gopDuration = (gopEnd - gopStart) + typicalInterval
            }
            
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

