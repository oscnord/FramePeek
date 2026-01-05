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
        return aggregateBySecond(rawFrames: rawFrames, maxSamples: maxSamples, defaultFrameDuration: defaultFrameDuration, estimatedFPS: estimatedFPS)
    case .frame:
        return aggregateByFrame(rawFrames: rawFrames, maxSamples: maxSamples, defaultFrameDuration: defaultFrameDuration, estimatedFPS: estimatedFPS)
    case .gop:
        return aggregateByGOP(rawFrames: rawFrames, maxSamples: maxSamples, defaultFrameDuration: defaultFrameDuration)
    }
}

// MARK: - Frame-by-Frame Instantaneous Bitrate Calculation

/// Calculates instantaneous bitrate for every frame
/// This gives a true per-frame bitrate value without any windowing or aggregation
func calculateInstantaneousBitrates(
    rawFrames: [RawFrame],
    estimatedFPS: Double
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    var samples: [BitrateSample] = []
    samples.reserveCapacity(sortedFrames.count)
    
    let defaultFrameDuration = 1.0 / estimatedFPS
    
    for i in 0..<sortedFrames.count {
        let frame = sortedFrames[i]
        let frameDuration: Double
        
        if i < sortedFrames.count - 1 {
            // Duration to next frame
            frameDuration = sortedFrames[i + 1].pts - frame.pts
        } else {
            // Last frame: use estimated frame duration
            frameDuration = defaultFrameDuration
        }
        
        // Ensure minimum duration to avoid division by zero or unrealistic values
        let safeDuration = max(frameDuration, defaultFrameDuration / 2.0)
        
        // Instantaneous bitrate for this frame
        let bitrate = (Double(frame.size) * 8.0) / safeDuration
        
        samples.append(BitrateSample(
            time: frame.pts,
            bitrate: bitrate,
            duration: safeDuration
        ))
    }
    
    return samples
}

// MARK: - Peak-Preserving Downsampling

/// Downsamples bitrate samples while preserving all peaks above a threshold
func downsampleWithPeakPreservation(
    samples: [BitrateSample],
    targetCount: Int,
    peakThreshold: Double = 1.2  // Peaks must be 20% above average
) -> [BitrateSample] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }
    
    // Calculate average bitrate
    let avgBitrate = samples.map(\.bitrate).reduce(0, +) / Double(samples.count)
    let threshold = avgBitrate * peakThreshold
    
    // Detect all peaks (local maxima above threshold)
    var peakIndices = Set<Int>()
    for i in 1..<(samples.count - 1) {
        if samples[i].bitrate > samples[i-1].bitrate &&
           samples[i].bitrate > samples[i+1].bitrate &&
           samples[i].bitrate > threshold {
            peakIndices.insert(i)
        }
    }
    
    // Always include first and last
    var includedIndices = Set<Int>([0, samples.count - 1])
    includedIndices.formUnion(peakIndices)
    
    // Fill remaining slots uniformly
    if includedIndices.count < targetCount {
        let remaining = targetCount - includedIndices.count
        let available = (0..<samples.count).filter { !includedIndices.contains($0) }
        
        if !available.isEmpty && remaining > 0 {
            let step = Double(available.count) / Double(remaining + 1)
            
            for i in 1...remaining {
                let idx = min(Int(round(Double(i) * step)), available.count - 1)
                includedIndices.insert(available[idx])
            }
        }
    }
    
    return includedIndices.sorted().map { samples[$0] }
}

// MARK: - Unified sliding window aggregation

/// Calculates bitrate using a 1-second sliding window
/// This is the core algorithm used by both second-based and frame-based modes
private func calculateSlidingWindowBitrates(
    rawFrames: [RawFrame],
    windowSize: Double = 1.0
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    var allSamples: [BitrateSample] = []
    allSamples.reserveCapacity(sortedFrames.count)
    
    // Use sliding window for efficiency
    var windowStartIndex = 0
    var windowEndIndex = 0
    var windowTotalBytes: Int64 = 0
    
    for i in 0..<sortedFrames.count {
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
        
        // Calculate bitrate over the 1-second window
        let bitrate = (Double(windowTotalBytes) * 8.0) / windowSize
        allSamples.append(BitrateSample(time: frame.pts, bitrate: bitrate, duration: windowSize))
    }
    
    return allSamples
}

// MARK: - Second-based aggregation (fixed 1-second time buckets)

private func aggregateBySecond(
    rawFrames: [RawFrame],
    maxSamples: Int,
    defaultFrameDuration: Double,
    estimatedFPS: Double
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    // Use fixed 1-second time buckets like ffprobe/mediainfo
    // This groups frames into discrete buckets: [0-1), [1-2), [2-3), etc.
    // and divides by exactly 1.0 second for accurate bitrate
    let bucketSize: Double = 1.0
    let sortedFrames = rawFrames.sorted { $0.pts < $1.pts }
    
    guard let startTime = sortedFrames.first?.pts,
          let endTime = sortedFrames.last?.pts else { return [] }
    
    let totalDuration = endTime - startTime + defaultFrameDuration
    let numBuckets = Int(ceil(totalDuration / bucketSize))
    guard numBuckets > 0 else { return [] }
    
    var bucketSamples: [BitrateSample] = []
    bucketSamples.reserveCapacity(numBuckets)
    
    var frameIndex = 0
    
    for bucketIndex in 0..<numBuckets {
        let bucketStart = startTime + Double(bucketIndex) * bucketSize
        let bucketEnd = bucketStart + bucketSize
        
        // Advance to first frame in this bucket
        while frameIndex < sortedFrames.count && sortedFrames[frameIndex].pts < bucketStart {
            frameIndex += 1
        }
        
        // Sum frames in bucket [bucketStart, bucketEnd)
        var totalBytes: Int64 = 0
        var tempIndex = frameIndex
        var firstFramePTS: Double? = nil
        var lastFramePTS: Double? = nil
        
        while tempIndex < sortedFrames.count && sortedFrames[tempIndex].pts < bucketEnd {
            if firstFramePTS == nil {
                firstFramePTS = sortedFrames[tempIndex].pts
            }
            lastFramePTS = sortedFrames[tempIndex].pts
            totalBytes += sortedFrames[tempIndex].size
            tempIndex += 1
        }
        
        if totalBytes > 0 {
            // Calculate average bitrate over the 1-second bucket
            let actualDuration: Double
            if let first = firstFramePTS, let last = lastFramePTS {
                let actualSpan = last - first
                if actualSpan < bucketSize - defaultFrameDuration {
                    actualDuration = actualSpan + defaultFrameDuration
                } else {
                    actualDuration = bucketSize
                }
            } else {
                actualDuration = bucketSize
            }
            
            let bitrate = (Double(totalBytes) * 8.0) / actualDuration
            let sampleTime = bucketStart + bucketSize / 2.0
            
            bucketSamples.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: actualDuration))
        }
    }
    
    // Use peak-preserving downsampling if needed
    if bucketSamples.count <= maxSamples {
        return bucketSamples
    }
    
    return downsampleWithPeakPreservation(samples: bucketSamples, targetCount: maxSamples)
}

// MARK: - Frame-based aggregation (per-frame bitrate)

private func aggregateByFrame(
    rawFrames: [RawFrame],
    maxSamples: Int,
    defaultFrameDuration: Double,
    estimatedFPS: Double
) -> [BitrateSample] {
    guard !rawFrames.isEmpty else { return [] }
    
    // Calculate bitrate for every frame using sliding window
    let allSamples = calculateSlidingWindowBitrates(rawFrames: rawFrames, windowSize: 1.0)
    
    // Use peak-preserving downsampling to reduce to maxSamples
    if allSamples.count <= maxSamples {
        return allSamples
    }
    
    return downsampleWithPeakPreservation(samples: allSamples, targetCount: maxSamples)
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



