//
//  BitrateChartStatistics.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation

struct BitrateChartStatistics {
    let samples: [BitrateSample]
    
    var maxBitrateKbps: Double {
        let maxBits = samples.map(\.bitrate).max() ?? 1
        return Double(maxBits) / 1000.0
    }
    
    var minBitrateKbps: Double {
        let minBits = samples.map(\.bitrate).min() ?? 0
        return Double(minBits) / 1000.0
    }
    
    var avgBitrateKbps: Double {
        guard !samples.isEmpty else { return 0 }
        
        // Use weighted average if durations are available
        let totalDuration = samples.reduce(0.0) { $0 + $1.duration }
        if totalDuration > 0 {
            // Weighted average: sum(bitrate * duration) / sum(duration)
            let weightedSum = samples.reduce(0.0) { $0 + ($1.bitrate * $1.duration) }
            return (weightedSum / totalDuration) / 1000.0
        } else {
            // Fallback to simple average if no durations
            let sum = samples.reduce(0.0) { $0 + $1.bitrate }
            return (sum / Double(samples.count)) / 1000.0
        }
    }
    
    var stdDevKbps: Double {
        guard samples.count > 1 else { return 0 }
        let avg = avgBitrateKbps * 1000.0
        let variance = samples.reduce(0.0) { sum, sample in
            let diff = sample.bitrate - avg
            return sum + diff * diff
        } / Double(samples.count)
        return sqrt(variance) / 1000.0
    }
    
    var maxTime: Double {
        samples.map(\.time).max() ?? 0
    }
    
    var headerPeakText: String {
        if samples.isEmpty { return "—" }
        return String(format: "%.0f kb/s", maxBitrateKbps)
    }
    
    var headerDurationText: String {
        if samples.isEmpty { return "—" }
        return String(format: "%.0f s", maxTime)
    }
    
    var headerAvgText: String {
        if samples.isEmpty { return "—" }
        return String(format: "%.0f kb/s", avgBitrateKbps)
    }
    
    var headerStdDevText: String {
        if samples.isEmpty { return "—" }
        return String(format: "±%.0f", stdDevKbps)
    }
    
    func niceStep(forMax max: Double, targetTicks: Int) -> Double {
        guard max > 0, targetTicks > 0 else { return 1 }
        let rough = max / Double(targetTicks)
        let magnitude = pow(10.0, floor(log10(rough)))
        let residual = rough / magnitude

        let nice: Double
        if residual < 1.5 { nice = 1 }
        else if residual < 3 { nice = 2 }
        else if residual < 7 { nice = 5 }
        else { nice = 10 }

        return nice * magnitude
    }
}

