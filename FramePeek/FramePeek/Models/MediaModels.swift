import Foundation

// MARK: - Audio Track Info

struct AudioTrackInfo {
    let index: Int
    let codec: String
    let codecDisplayName: String
    let channels: Int
    let channelLayout: String
    let sampleRateHz: Double
    let bitrateKbps: Float?
    let languageCode: String?
}

// MARK: - Extended Video Info

struct ExtendedVideoInfo {
    // File / Container
    let fileName: String
    let fileSize: String
    let fileSizeBytes: UInt64?
    let overallBitrate: String
    let duration: String
    let durationFormatted: String
    let containerFormat: String?
    let containerFormatProfile: String?
    let codecIdRaw: String?

    // Video basic
    let resolution: String
    let displayAspectRatio: String?
    let frameRate: String
    let codec: String
    let codecProfile: String?
    let codecIdInfo: String?

    // Video extra
    let orientationDegrees: Int?
    let trackBitrate: String?
    let maxBitrate: String?
    let minBitrate: String?
    let pixelAspectRatio: String?
    let cleanAperture: String?
    let scanType: String?
    let frameRateMode: String?
    let colorSpace: String?
    let chromaSubsampling: String?
    let bitsPerPixelFrame: String?
    let videoStreamSize: String?

    // Color
    let colorPrimaries: String?
    let transferFunction: String?
    let matrixCoefficients: String?
    let colorRange: String?
    let bitDepth: String?
    let hdrFormat: String?

    // AV1 extras
    let av1CSize: Int?
    let av1Profile: String?
    let av1Level: String?
    let av1ChromaSubsampling: String?
    let av1FullRange: String?

    // Metadata
    let creationDate: String?
    let metadataTitle: String?
    let metadataArtist: String?
    let metadataEncoder: String?
    let metadataDescription: String?

    // Audio
    let audioTracks: [AudioTrackInfo]

    // MARK: - Computed Properties

    /// Parses the numeric frame rate from the frameRate string (e.g., "23.976 fps" -> 23.976)
    var nominalFrameRate: Double? {
        // Try to extract the numeric portion from strings like "23.976 fps", "29.97 fps", "60 fps"
        let trimmed = frameRate.trimmingCharacters(in: .whitespaces)
        let components = trimmed.components(separatedBy: CharacterSet(charactersIn: " f"))
        guard let firstComponent = components.first else { return nil }
        return Double(firstComponent)
    }

    /// Parses the duration in seconds from the duration string
    var durationSeconds: Double? {
        // The duration field stores seconds as a string
        return Double(duration)
    }

    /// Parses width and height from resolution string (e.g., "1920x1080" -> (1920, 1080))
    var resolutionComponents: (width: Int, height: Int)? {
        let parts = resolution.lowercased().components(separatedBy: CharacterSet(charactersIn: "x×"))
        guard parts.count == 2,
              let width = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let height = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (width, height)
    }

    /// Returns true if this is HDR content
    var isHDR: Bool {
        hdrFormat != nil && !hdrFormat!.isEmpty
    }

    /// Returns true if this has wide color gamut (BT.2020)
    var isWideGamut: Bool {
        guard let primaries = colorPrimaries?.lowercased() else { return false }
        return primaries.contains("2020") || primaries.contains("p3")
    }
}

// MARK: - Frame Analysis

struct FrameAnalysisResult {
    let samples: [BitrateSample]
    let averageFPS: Double?
    let minInterval: Double?
    let maxInterval: Double?
}

enum BitrateVisualizationMode: String, CaseIterable, Identifiable {
    case second = "Second"    // 1-second rolling window (default)
    case frame = "Frame"      // Per-frame bitrate
    case gop = "GOP"          // Per-GOP (Group of Pictures) bitrate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .second: return String(localized: "Second")
        case .frame: return String(localized: "Frame")
        case .gop: return String(localized: "GOP")
        }
    }
}

/// Format-specific accuracy modes for bitrate extraction
enum FormatAccuracyMode: String, CaseIterable, Identifiable, Codable {
    case performance  // Use AVFoundation data as-is (fastest)
    case balanced    // Format-specific optimizations without deep parsing
    case accuracy    // Full format parsing (TS packets, fragment analysis)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .performance: return String(localized: "Performance")
        case .balanced: return String(localized: "Balanced")
        case .accuracy: return String(localized: "Accuracy")
        }
    }
}

struct FrameSamplingOptions {
    let minEmitIntervalSeconds: Double?
    let maxSamples: Int
    let emitEveryNSamples: Int
    let preferAccuracy: Bool  // If true, uses reader path (accurate) instead of cursor path (fast)
    let visualizationMode: BitrateVisualizationMode  // How to aggregate bitrate samples

    // Format-specific options
    /// For TS files: account for packet overhead in bitrate calculations
    let accountTSOverhead: Bool

    /// For fragmented formats: smooth bitrate at segment boundaries
    let smoothSegmentBoundaries: Bool

    /// Format-specific accuracy mode
    let formatAccuracyMode: FormatAccuracyMode

    init(
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

    static func everyFrame(
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

    static func interval(
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

// MARK: - AV1 Config

struct AV1ConfigSummary {
    let profile: Int
    let level: Int
    let bitDepth: Int
    let chromaSubsampling: String
    let fullRange: Bool
}

// MARK: - Waveform Height

enum WaveformHeight: String, CaseIterable, Identifiable {
    case compact
    case normal
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .normal: return String(localized: "Normal")
        case .large: return String(localized: "Large")
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: return 60
        case .normal: return 100
        case .large: return 150
        }
    }
}

// MARK: - Audio/Video Sync Analysis

struct AudioTrackSyncInfo {
    let trackIndex: Int
    let audioFirstPTS: Double
    let audioDuration: Double
    let syncOffsetMs: Double
    let durationDifferenceMs: Double
    let syncStatus: SyncStatus
}

struct SyncAnalysisResult {
    let videoFirstPTS: Double
    let videoDuration: Double
    let videoFrameCount: Int
    let averageVideoFrameInterval: Double?
    let frameIntervalVariance: Double?
    let hasTimestampGaps: Bool
    let audioTracks: [AudioTrackSyncInfo]

    var overallSyncStatus: SyncStatus {
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

    var isVariableFrameRate: Bool {
        guard let variance = frameIntervalVariance, let avg = averageVideoFrameInterval else { return false }
        return variance > avg * 0.1
    }

    var primaryTrackSyncOffsetMs: Double {
        audioTracks.first?.syncOffsetMs ?? 0
    }

    var primaryTrackDurationDifferenceMs: Double {
        audioTracks.first?.durationDifferenceMs ?? 0
    }
}

enum SyncStatus {
    case inSync
    case minorOffset
    case significantOffset
    case durationMismatch
    case noAudio
    case noVideo
    case analysisError

    var displayName: String {
        switch self {
        case .inSync: return String(localized: "In Sync")
        case .minorOffset: return String(localized: "Minor Offset")
        case .significantOffset: return String(localized: "Significant Offset")
        case .durationMismatch: return String(localized: "Duration Mismatch")
        case .noAudio: return String(localized: "No Audio")
        case .noVideo: return String(localized: "No Video")
        case .analysisError: return String(localized: "Analysis Error")
        }
    }
}

struct FrameTimingSample: Identifiable {
    let id = UUID()
    let time: Double
    let intervalMs: Double
}

// MARK: - Waveform Extraction

struct WaveformUpdate {
    let appendedSamples: [WaveformSample]
    let isFinished: Bool
}

// MARK: - Color Analysis

struct ColorSample: Identifiable {
    let id = UUID()
    let time: Double
    let brightness: Double  // 0.0 to 1.0
    let colorTemperature: Double?  // Kelvin (optional)
    let histogram: ColorHistogram?  // RGB distribution
}

struct ColorHistogram {
    let red: [Double]    // 256 bins
    let green: [Double]
    let blue: [Double]
}
