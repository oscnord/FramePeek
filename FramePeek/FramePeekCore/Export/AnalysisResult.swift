import Foundation

// MARK: - Unified Analysis Result

/// Complete result of all analysis operations on a media file
public struct AnalysisResult: Codable, Sendable {
    /// Schema version for backward compatibility
    public static let schemaVersion = "1.0"
    
    /// Version of the output schema
    public let version: String
    
    /// When the analysis was performed
    public let analyzedAt: Date
    
    /// Information about the analyzed file
    public let file: FileInfo
    
    /// Video/audio metadata (always populated)
    public let metadata: ExtendedVideoInfo?
    
    /// Bitrate analysis results
    public let bitrate: BitrateAnalysisOutput?
    
    /// GOP structure analysis results
    public let gop: GOPAnalysisOutput?
    
    /// Audio waveform data by track index
    public let waveforms: [String: [WaveformSampleOutput]]?
    
    /// A/V sync analysis results
    public let sync: SyncAnalysisOutput?
    
    /// Color analysis results
    public let color: ColorAnalysisSummary?
    
    /// Keyframe timestamps
    public let keyframes: [KeyframeOutput]?
    
    /// Generated thumbnail paths
    public let thumbnails: [ThumbnailOutput]?
    
    public init(
        analyzedAt: Date = Date(),
        file: FileInfo,
        metadata: ExtendedVideoInfo? = nil,
        bitrate: BitrateAnalysisOutput? = nil,
        gop: GOPAnalysisOutput? = nil,
        waveforms: [String: [WaveformSampleOutput]]? = nil,
        sync: SyncAnalysisOutput? = nil,
        color: ColorAnalysisSummary? = nil,
        keyframes: [KeyframeOutput]? = nil,
        thumbnails: [ThumbnailOutput]? = nil
    ) {
        self.version = Self.schemaVersion
        self.analyzedAt = analyzedAt
        self.file = file
        self.metadata = metadata
        self.bitrate = bitrate
        self.gop = gop
        self.waveforms = waveforms
        self.sync = sync
        self.color = color
        self.keyframes = keyframes
        self.thumbnails = thumbnails
    }
}

// MARK: - File Info

/// Basic file information
public struct FileInfo: Codable, Sendable {
    public let path: String
    public let name: String
    public let size: UInt64
    public let sizeFormatted: String
    
    public init(path: String, name: String, size: UInt64, sizeFormatted: String) {
        self.path = path
        self.name = name
        self.size = size
        self.sizeFormatted = sizeFormatted
    }
    
    public init(url: URL) {
        self.path = url.path
        self.name = url.lastPathComponent
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        self.size = fileSize
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        self.sizeFormatted = formatter.string(fromByteCount: Int64(fileSize))
    }
}

// MARK: - Bitrate Analysis Output

/// Bitrate analysis output for JSON export
public struct BitrateAnalysisOutput: Codable, Sendable {
    public let mode: String
    public let stats: BitrateStats
    public let samples: [BitrateSampleOutput]
    
    public init(mode: BitrateVisualizationMode, stats: BitrateStats, samples: [BitrateSampleOutput]) {
        self.mode = mode.rawValue
        self.stats = stats
        self.samples = samples
    }
}

/// Bitrate statistics
public struct BitrateStats: Codable, Sendable {
    public let min: Double
    public let max: Double
    public let average: Double
    public let stdDev: Double?
    
    public init(min: Double, max: Double, average: Double, stdDev: Double? = nil) {
        self.min = min
        self.max = max
        self.average = average
        self.stdDev = stdDev
    }
    
    public init(samples: [BitrateSample]) {
        let bitrates = samples.map { $0.bitrate }
        self.min = bitrates.min() ?? 0
        self.max = bitrates.max() ?? 0
        self.average = bitrates.isEmpty ? 0 : bitrates.reduce(0, +) / Double(bitrates.count)
        
        if bitrates.count > 1 {
            let mean = self.average
            let sumOfSquaredDiffs = bitrates.reduce(0) { $0 + pow($1 - mean, 2) }
            self.stdDev = sqrt(sumOfSquaredDiffs / Double(bitrates.count))
        } else {
            self.stdDev = nil
        }
    }
}

/// Single bitrate sample for JSON export
public struct BitrateSampleOutput: Codable, Sendable {
    public let time: Double
    public let bitrate: Double
    public let duration: Double
    
    public init(time: Double, bitrate: Double, duration: Double) {
        self.time = time
        self.bitrate = bitrate
        self.duration = duration
    }
    
    public init(sample: BitrateSample) {
        self.time = sample.time
        self.bitrate = sample.bitrate
        self.duration = sample.duration
    }
}

// MARK: - GOP Analysis Output

/// GOP analysis output for JSON export
public struct GOPAnalysisOutput: Codable, Sendable {
    public let structureType: String
    public let fixedFrameCount: Int?
    public let stats: GOPStatsOutput
    public let segments: [GOPSegmentOutput]?
    
    public init(result: GOPAnalysisResult, includeSegments: Bool = true) {
        switch result.structureType {
        case .unknown:
            self.structureType = "unknown"
            self.fixedFrameCount = nil
        case .fixed(let count):
            self.structureType = "fixed"
            self.fixedFrameCount = count
        case .variable:
            self.structureType = "variable"
            self.fixedFrameCount = nil
        }
        
        self.stats = GOPStatsOutput(stats: result.stats)
        self.segments = includeSegments ? result.segments.map { GOPSegmentOutput(segment: $0) } : nil
    }
}

/// GOP statistics for JSON export
public struct GOPStatsOutput: Codable, Sendable {
    public let count: Int
    public let minDuration: Double?
    public let avgDuration: Double?
    public let maxDuration: Double?
    public let minFrameCount: Int?
    public let avgFrameCount: Double?
    public let maxFrameCount: Int?
    
    public init(stats: GOPAnalysisStats) {
        self.count = stats.gopCount
        self.minDuration = stats.minDuration
        self.avgDuration = stats.avgDuration
        self.maxDuration = stats.maxDuration
        self.minFrameCount = stats.minFrameCount
        self.avgFrameCount = stats.avgFrameCount
        self.maxFrameCount = stats.maxFrameCount
    }
}

/// Single GOP segment for JSON export
public struct GOPSegmentOutput: Codable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let duration: Double
    public let frameCount: Int?
    public let frames: [FrameInfoOutput]?
    
    public init(segment: GOPSegment) {
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.duration = segment.duration
        self.frameCount = segment.frameCount
        self.frames = segment.frames?.map { FrameInfoOutput(frame: $0) }
    }
}

/// Single frame info for JSON export
public struct FrameInfoOutput: Codable, Sendable {
    public let time: Double
    public let type: String
    public let size: Int64?
    
    public init(frame: FrameInfo) {
        self.time = frame.time
        self.type = frame.type.rawValue
        self.size = frame.size
    }
}

// MARK: - Waveform Output

/// Single waveform sample for JSON export
public struct WaveformSampleOutput: Codable, Sendable {
    public let time: Double
    public let amplitude: Double
    public let min: Double
    public let max: Double
    
    public init(sample: WaveformSample) {
        self.time = sample.time
        self.amplitude = sample.amplitude
        self.min = sample.minAmplitude
        self.max = sample.maxAmplitude
    }
}

// MARK: - Sync Analysis Output

/// A/V sync analysis output for JSON export
public struct SyncAnalysisOutput: Codable, Sendable {
    public let overallStatus: String
    public let video: VideoSyncOutput
    public let audio: [AudioSyncOutput]
    
    public init(result: SyncAnalysisResult) {
        self.overallStatus = result.overallSyncStatus.rawValue
        self.video = VideoSyncOutput(result: result)
        self.audio = result.audioTracks.map { AudioSyncOutput(info: $0) }
    }
}

/// Video sync details for JSON export
public struct VideoSyncOutput: Codable, Sendable {
    public let firstPTS: Double
    public let duration: Double
    public let frameCount: Int
    public let averageFrameInterval: Double?
    public let isVariableFrameRate: Bool
    
    public init(result: SyncAnalysisResult) {
        self.firstPTS = result.videoFirstPTS
        self.duration = result.videoDuration
        self.frameCount = result.videoFrameCount
        self.averageFrameInterval = result.averageVideoFrameInterval
        self.isVariableFrameRate = result.isVariableFrameRate
    }
}

/// Audio track sync details for JSON export
public struct AudioSyncOutput: Codable, Sendable {
    public let trackIndex: Int
    public let firstPTS: Double
    public let duration: Double
    public let syncOffsetMs: Double
    public let durationDifferenceMs: Double
    public let status: String
    
    public init(info: AudioTrackSyncInfo) {
        self.trackIndex = info.trackIndex
        self.firstPTS = info.audioFirstPTS
        self.duration = info.audioDuration
        self.syncOffsetMs = info.syncOffsetMs
        self.durationDifferenceMs = info.durationDifferenceMs
        self.status = info.syncStatus.rawValue
    }
}

// MARK: - Color Analysis Summary

/// Color analysis summary for JSON export
public struct ColorAnalysisSummary: Codable, Sendable {
    public let hdrContentType: String?
    public let stats: AggregatedColorStats?
    public let sampleCount: Int
    
    public init(hdrType: HDRContentType?, stats: AggregatedColorStats?, sampleCount: Int) {
        self.hdrContentType = hdrType?.rawValue
        self.stats = stats
        self.sampleCount = sampleCount
    }
}

// MARK: - Keyframe Output

/// Keyframe info for JSON export
public struct KeyframeOutput: Codable, Sendable {
    public let time: Double
    public let index: Int
    
    public init(time: Double, index: Int) {
        self.time = time
        self.index = index
    }
}

// MARK: - Thumbnail Output

/// Thumbnail info for JSON export
public struct ThumbnailOutput: Codable, Sendable {
    public let time: Double
    public let index: Int
    public let path: String
    
    public init(time: Double, index: Int, path: String) {
        self.time = time
        self.index = index
        self.path = path
    }
}
