//
//  BitrateChartDownsampling.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation

/// Largest-Triangle-Three-Buckets (LTTB) downsampling algorithm
/// Preserves visual shape of the data while reducing point count for performance
func downsampleLTTB(_ samples: [BitrateSample], targetCount: Int) -> [BitrateSample] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }
    
    var result: [BitrateSample] = []
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
            avgY += samples[j].bitrate
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
                (pointA.time - avgX) * (pointB.bitrate - pointA.bitrate) -
                (pointA.time - pointB.time) * (avgY - pointA.bitrate)
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

/// Downsample keyframes evenly across the video duration for chart display
func downsampleKeyframes(_ keyframes: [KeyframeMarker], maxCount: Int, visibleRange: ClosedRange<Double>?) -> [KeyframeMarker] {
    let filteredKeyframes: [KeyframeMarker]
    if let range = visibleRange {
        filteredKeyframes = keyframes.filter { range.contains($0.time) }
    } else {
        filteredKeyframes = keyframes
    }
    
    guard filteredKeyframes.count > maxCount else { return filteredKeyframes }
    
    let step = Double(filteredKeyframes.count) / Double(maxCount)
    var result: [KeyframeMarker] = []
    result.reserveCapacity(maxCount)
    
    for i in 0..<maxCount {
        let index = min(Int(Double(i) * step), filteredKeyframes.count - 1)
        result.append(filteredKeyframes[index])
    }
    
    return result
}

