import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Audio Track Info

/// Information about a single audio track
public struct AudioTrackInfo: Codable, Sendable {
    public let index: Int
    public let codec: String
    public let codecDisplayName: String
    public let channels: Int
    public let channelLayout: String
    public let sampleRateHz: Double
    public let bitrateKbps: Float?
    public let languageCode: String?
    
    public init(index: Int, codec: String, codecDisplayName: String, channels: Int,
                channelLayout: String, sampleRateHz: Double, bitrateKbps: Float?, languageCode: String?) {
        self.index = index
        self.codec = codec
        self.codecDisplayName = codecDisplayName
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRateHz = sampleRateHz
        self.bitrateKbps = bitrateKbps
        self.languageCode = languageCode
    }
}

// MARK: - Extended Video Info

/// Comprehensive video file information
public struct ExtendedVideoInfo: Codable, Sendable {
    // File / Container
    public let fileName: String
    public let fileSize: String
    public let fileSizeBytes: UInt64?
    public let overallBitrate: String
    public let duration: String
    public let durationFormatted: String
    public let containerFormat: String?
    public let containerFormatProfile: String?
    public let codecIdRaw: String?

    // Video basic
    public let resolution: String
    public let displayAspectRatio: String?
    public let frameRate: String
    public let codec: String
    public let codecProfile: String?
    public let codecIdInfo: String?

    // Video extra
    public let orientationDegrees: Int?
    public let trackBitrate: String?
    public let maxBitrate: String?
    public let minBitrate: String?
    public let pixelAspectRatio: String?
    public let cleanAperture: String?
    public let scanType: String?
    public let frameRateMode: String?
    public let colorSpace: String?
    public let chromaSubsampling: String?
    public let bitsPerPixelFrame: String?
    public let videoStreamSize: String?

    // Color
    public let colorPrimaries: String?
    public let transferFunction: String?
    public let matrixCoefficients: String?
    public let colorRange: String?
    public let bitDepth: String?
    public let hdrFormat: String?

    // AV1 extras
    public let av1CSize: Int?
    public let av1Profile: String?
    public let av1Level: String?
    public let av1ChromaSubsampling: String?
    public let av1FullRange: String?

    // Metadata
    public let creationDate: String?
    public let metadataTitle: String?
    public let metadataArtist: String?
    public let metadataEncoder: String?
    public let metadataDescription: String?

    // Audio
    public let audioTracks: [AudioTrackInfo]
    
    public init(
        fileName: String, fileSize: String, fileSizeBytes: UInt64?, overallBitrate: String,
        duration: String, durationFormatted: String, containerFormat: String?, containerFormatProfile: String?,
        codecIdRaw: String?, resolution: String, displayAspectRatio: String?, frameRate: String,
        codec: String, codecProfile: String?, codecIdInfo: String?, orientationDegrees: Int?,
        trackBitrate: String?, maxBitrate: String?, minBitrate: String?, pixelAspectRatio: String?,
        cleanAperture: String?, scanType: String?, frameRateMode: String?, colorSpace: String?,
        chromaSubsampling: String?, bitsPerPixelFrame: String?, videoStreamSize: String?,
        colorPrimaries: String?, transferFunction: String?, matrixCoefficients: String?, colorRange: String?,
        bitDepth: String?, hdrFormat: String?, av1CSize: Int?, av1Profile: String?, av1Level: String?,
        av1ChromaSubsampling: String?, av1FullRange: String?, creationDate: String?, metadataTitle: String?,
        metadataArtist: String?, metadataEncoder: String?, metadataDescription: String?, audioTracks: [AudioTrackInfo]
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileSizeBytes = fileSizeBytes
        self.overallBitrate = overallBitrate
        self.duration = duration
        self.durationFormatted = durationFormatted
        self.containerFormat = containerFormat
        self.containerFormatProfile = containerFormatProfile
        self.codecIdRaw = codecIdRaw
        self.resolution = resolution
        self.displayAspectRatio = displayAspectRatio
        self.frameRate = frameRate
        self.codec = codec
        self.codecProfile = codecProfile
        self.codecIdInfo = codecIdInfo
        self.orientationDegrees = orientationDegrees
        self.trackBitrate = trackBitrate
        self.maxBitrate = maxBitrate
        self.minBitrate = minBitrate
        self.pixelAspectRatio = pixelAspectRatio
        self.cleanAperture = cleanAperture
        self.scanType = scanType
        self.frameRateMode = frameRateMode
        self.colorSpace = colorSpace
        self.chromaSubsampling = chromaSubsampling
        self.bitsPerPixelFrame = bitsPerPixelFrame
        self.videoStreamSize = videoStreamSize
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.matrixCoefficients = matrixCoefficients
        self.colorRange = colorRange
        self.bitDepth = bitDepth
        self.hdrFormat = hdrFormat
        self.av1CSize = av1CSize
        self.av1Profile = av1Profile
        self.av1Level = av1Level
        self.av1ChromaSubsampling = av1ChromaSubsampling
        self.av1FullRange = av1FullRange
        self.creationDate = creationDate
        self.metadataTitle = metadataTitle
        self.metadataArtist = metadataArtist
        self.metadataEncoder = metadataEncoder
        self.metadataDescription = metadataDescription
        self.audioTracks = audioTracks
    }

    // MARK: - Computed Properties

    /// Parses the numeric frame rate from the frameRate string (e.g., "23.976 fps" -> 23.976)
    public var nominalFrameRate: Double? {
        let trimmed = frameRate.trimmingCharacters(in: .whitespaces)
        let components = trimmed.components(separatedBy: CharacterSet(charactersIn: " f"))
        guard let firstComponent = components.first else { return nil }
        return Double(firstComponent)
    }

    /// Parses the duration in seconds from the duration string
    public var durationSeconds: Double? {
        return Double(duration)
    }

    /// Parses width and height from resolution string (e.g., "1920x1080" -> (1920, 1080))
    public var resolutionComponents: (width: Int, height: Int)? {
        let parts = resolution.lowercased().components(separatedBy: CharacterSet(charactersIn: "x×"))
        guard parts.count == 2,
              let width = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let height = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (width, height)
    }

    /// Returns true if this is HDR content
    public var isHDR: Bool {
        hdrFormat != nil && !hdrFormat!.isEmpty
    }

    /// Returns true if this has wide color gamut (BT.2020)
    public var isWideGamut: Bool {
        guard let primaries = colorPrimaries?.lowercased() else { return false }
        return primaries.contains("2020") || primaries.contains("p3")
    }
}

// Note: FrameAnalysisResult is defined in BitrateSample.swift to avoid circular dependencies

// MARK: - Bitrate Visualization Mode

/// Mode for aggregating bitrate samples
public enum BitrateVisualizationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case second = "Second"    // 1-second rolling window (default)
    case frame = "Frame"      // Per-frame bitrate
    case gop = "GOP"          // Per-GOP (Group of Pictures) bitrate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .second: return "Second"
        case .frame: return "Frame"
        case .gop: return "GOP"
        }
    }
}

// MARK: - Format Accuracy Mode

/// Format-specific accuracy modes for bitrate extraction
public enum FormatAccuracyMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case performance  // Use AVFoundation data as-is (fastest)
    case balanced    // Format-specific optimizations without deep parsing
    case accuracy    // Full format parsing (TS packets, fragment analysis)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .accuracy: return "Accuracy"
        }
    }
}

// MARK: - Frame Sampling Options

/// Configuration for frame sampling during bitrate analysis
public struct FrameSamplingOptions: Sendable {
    public let minEmitIntervalSeconds: Double?
    public let maxSamples: Int
    public let emitEveryNSamples: Int
    public let preferAccuracy: Bool
    public let visualizationMode: BitrateVisualizationMode
    public let accountTSOverhead: Bool
    public let smoothSegmentBoundaries: Bool
    public let formatAccuracyMode: FormatAccuracyMode

    public init(
        minEmitIntervalSeconds: Double?,
        maxSamples: Int,
        emitEveryNSamples: Int,
        preferAccuracy: Bool = false,
        visualizationMode: BitrateVisualizationMode = .second,
        accountTSOverhead: Bool = false,
        smoothSegmentBoundaries: Bool = true,
        formatAccuracyMode: FormatAccuracyMode = .balanced
    ) {
        self.minEmitIntervalSeconds = minEmitIntervalSeconds
        self.maxSamples = maxSamples
        self.emitEveryNSamples = emitEveryNSamples
        self.preferAccuracy = preferAccuracy
        self.visualizationMode = visualizationMode
        self.accountTSOverhead = accountTSOverhead
        self.smoothSegmentBoundaries = smoothSegmentBoundaries
        self.formatAccuracyMode = formatAccuracyMode
    }

    public static func everyFrame(
        maxSamples: Int = 2000,
        emitEveryNSamples: Int = 100,
        preferAccuracy: Bool = false,
        visualizationMode: BitrateVisualizationMode = .second,
        accountTSOverhead: Bool = false,
        smoothSegmentBoundaries: Bool = true,
        formatAccuracyMode: FormatAccuracyMode = .balanced
    ) -> Self {
        .init(
            minEmitIntervalSeconds: nil,
            maxSamples: maxSamples,
            emitEveryNSamples: emitEveryNSamples,
            preferAccuracy: preferAccuracy,
            visualizationMode: visualizationMode,
            accountTSOverhead: accountTSOverhead,
            smoothSegmentBoundaries: smoothSegmentBoundaries,
            formatAccuracyMode: formatAccuracyMode
        )
    }

    public static func interval(
        _ seconds: Double,
        maxSamples: Int = 2000,
        emitEveryNSamples: Int = 100,
        preferAccuracy: Bool = false,
        visualizationMode: BitrateVisualizationMode = .second,
        accountTSOverhead: Bool = false,
        smoothSegmentBoundaries: Bool = true,
        formatAccuracyMode: FormatAccuracyMode = .balanced
    ) -> Self {
        .init(
            minEmitIntervalSeconds: max(0, seconds),
            maxSamples: maxSamples,
            emitEveryNSamples: emitEveryNSamples,
            preferAccuracy: preferAccuracy,
            visualizationMode: visualizationMode,
            accountTSOverhead: accountTSOverhead,
            smoothSegmentBoundaries: smoothSegmentBoundaries,
            formatAccuracyMode: formatAccuracyMode
        )
    }
}

// MARK: - AV1 Config Summary

/// Summary of AV1 codec configuration
public struct AV1ConfigSummary: Codable, Sendable {
    public let profile: Int
    public let level: Int
    public let bitDepth: Int
    public let chromaSubsampling: String
    public let fullRange: Bool
    
    public init(profile: Int, level: Int, bitDepth: Int, chromaSubsampling: String, fullRange: Bool) {
        self.profile = profile
        self.level = level
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
        self.fullRange = fullRange
    }
}

// MARK: - Waveform Height

/// Display height options for audio waveforms
public enum WaveformHeight: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact
    case normal
    case large

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }

    #if canImport(CoreGraphics)
    public var height: CGFloat {
        switch self {
        case .compact: return 60
        case .normal: return 100
        case .large: return 150
        }
    }
    #endif
}

// MARK: - Audio/Video Sync Analysis

/// Sync information for a single audio track
public struct AudioTrackSyncInfo: Codable, Sendable {
    public let trackIndex: Int
    public let audioFirstPTS: Double
    public let audioDuration: Double
    public let syncOffsetMs: Double
    public let durationDifferenceMs: Double
    public let syncStatus: SyncStatus
    
    public init(trackIndex: Int, audioFirstPTS: Double, audioDuration: Double,
                syncOffsetMs: Double, durationDifferenceMs: Double, syncStatus: SyncStatus) {
        self.trackIndex = trackIndex
        self.audioFirstPTS = audioFirstPTS
        self.audioDuration = audioDuration
        self.syncOffsetMs = syncOffsetMs
        self.durationDifferenceMs = durationDifferenceMs
        self.syncStatus = syncStatus
    }
}

/// Complete A/V sync analysis result
public struct SyncAnalysisResult: Codable, Sendable {
    public let videoFirstPTS: Double
    public let videoDuration: Double
    public let videoFrameCount: Int
    public let averageVideoFrameInterval: Double?
    public let frameIntervalVariance: Double?
    public let hasTimestampGaps: Bool
    public let audioTracks: [AudioTrackSyncInfo]
    
    public init(videoFirstPTS: Double, videoDuration: Double, videoFrameCount: Int,
                averageVideoFrameInterval: Double?, frameIntervalVariance: Double?,
                hasTimestampGaps: Bool, audioTracks: [AudioTrackSyncInfo]) {
        self.videoFirstPTS = videoFirstPTS
        self.videoDuration = videoDuration
        self.videoFrameCount = videoFrameCount
        self.averageVideoFrameInterval = averageVideoFrameInterval
        self.frameIntervalVariance = frameIntervalVariance
        self.hasTimestampGaps = hasTimestampGaps
        self.audioTracks = audioTracks
    }

    public var overallSyncStatus: SyncStatus {
        if audioTracks.isEmpty {
            return .noAudio
        }

        let statuses = audioTracks.map { $0.syncStatus }

        if statuses.contains(.durationMismatch) {
            return .durationMismatch
        }
        if statuses.contains(.significantOffset) {
            return .significantOffset
        }
        if statuses.contains(.minorOffset) {
            return .minorOffset
        }
        if statuses.allSatisfy({ $0 == .inSync }) {
            return .inSync
        }

        return .inSync
    }

    public var isVariableFrameRate: Bool {
        guard let variance = frameIntervalVariance, let avg = averageVideoFrameInterval else { return false }
        return variance > avg * 0.1
    }

    public var primaryTrackSyncOffsetMs: Double {
        audioTracks.first?.syncOffsetMs ?? 0
    }

    public var primaryTrackDurationDifferenceMs: Double {
        audioTracks.first?.durationDifferenceMs ?? 0
    }
}

/// Sync status classification
public enum SyncStatus: String, Codable, Sendable, CaseIterable {
    case inSync
    case minorOffset
    case significantOffset
    case durationMismatch
    case noAudio
    case noVideo
    case analysisError

    public var displayName: String {
        switch self {
        case .inSync: return "In Sync"
        case .minorOffset: return "Minor Offset"
        case .significantOffset: return "Significant Offset"
        case .durationMismatch: return "Duration Mismatch"
        case .noAudio: return "No Audio"
        case .noVideo: return "No Video"
        case .analysisError: return "Analysis Error"
        }
    }
}

/// Frame timing sample for VFR detection
public struct FrameTimingSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Double
    public let intervalMs: Double
    
    public init(id: UUID = UUID(), time: Double, intervalMs: Double) {
        self.id = id
        self.time = time
        self.intervalMs = intervalMs
    }
}

// MARK: - Color Sample (Simple)

/// Simple color sample for basic color analysis
public struct ColorSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Double
    public let brightness: Double  // 0.0 to 1.0
    public let colorTemperature: Double?  // Kelvin (optional)
    public let histogram: ColorHistogram?  // RGB distribution
    
    public init(id: UUID = UUID(), time: Double, brightness: Double,
                colorTemperature: Double?, histogram: ColorHistogram?) {
        self.id = id
        self.time = time
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.histogram = histogram
    }
}

/// RGB color histogram
public struct ColorHistogram: Codable, Sendable {
    public let red: [Double]    // 256 bins
    public let green: [Double]
    public let blue: [Double]
    
    public init(red: [Double], green: [Double], blue: [Double]) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

// MARK: - Thumbnail Size

/// Thumbnail size options
public enum ThumbnailSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    
    #if canImport(CoreGraphics)
    public var dimension: CGFloat {
        switch self {
        case .small: return 120
        case .medium: return 200
        case .large: return 320
        }
    }
    #endif
}

// Note: KeyframeThumbnail is defined in Utils/Parsing/KeyframeMarker.swift
