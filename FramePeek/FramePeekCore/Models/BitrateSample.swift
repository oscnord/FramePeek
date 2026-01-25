import Foundation

/// A single bitrate measurement sample
public struct BitrateSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Double        // seconds (end time of this sample window)
    public let bitrate: Double     // bits per second
    public let duration: Double    // duration of this sample window in seconds (for weighted averaging)

    public init(id: UUID = UUID(), time: Double, bitrate: Double, duration: Double = 0) {
        self.id = id
        self.time = time
        self.bitrate = bitrate
        self.duration = duration
    }
}

/// Result of frame-by-frame analysis
public struct FrameAnalysisResult: Sendable {
    public let samples: [BitrateSample]
    public let averageFPS: Double?
    public let minInterval: Double?
    public let maxInterval: Double?
    
    public init(samples: [BitrateSample], averageFPS: Double?, minInterval: Double?, maxInterval: Double?) {
        self.samples = samples
        self.averageFPS = averageFPS
        self.minInterval = minInterval
        self.maxInterval = maxInterval
    }
}

// Note: FrameAnalysisUpdate and RawFrame are defined in Utils/Analysis/ExtractFramesStream.swift
// and Utils/Analysis/FrameAggregation.swift respectively - do not duplicate here
