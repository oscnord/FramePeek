import Foundation
import AVFoundation
import CoreMedia
import SwiftUI
import FramePeekCore

@MainActor
@Observable
final class FramePeekViewModel {
    var samples: [BitrateSample] = []
    var extendedInfo: ExtendedVideoInfo?
    var effectiveFPS: Double?
    var minInterval: Double?
    var maxInterval: Double?
    var hoveredSample: BitrateSample?
    var hoveredTimestamp: Double?  // Shared hover state for cross-chart sync
    var isAnalyzing: Bool = false
    var durationSeconds: Double = 0
    var keyframeThumbs: [KeyframeThumbnail] = []
    var hoveredKeyframeTime: Double?  // Shared hover state for syncing thumbnails and chart
    var visibleTimeRange: ClosedRange<Double>? // Zoom state
    var isGeneratingThumbnails: Bool = false

    // GOP analysis
    var gopAnalysis: GOPAnalysisResult?
    var isAnalyzingGOP: Bool = false
    var selectedGOPIndex: Int? // Selected GOP for details view
    var gopLoadedFromCache: Bool = false  // Cache status indicator

    // GOP frame detail extraction (on-demand loading)
    var selectedGOPFrameDetails: [FrameInfo]?
    var isLoadingGOPFrameDetails: Bool = false
    var gopFrameDetailsCache: [UUID: [FrameInfo]] = [:]
    @ObservationIgnored var gopCacheAccessOrder: [UUID] = []
    @ObservationIgnored let gopCacheMaxSize = 50
    var preloadingGOPIndices: Set<Int> = []
    var codecSupportsFrameTypes: Bool = true
    @ObservationIgnored var frameDetailPreloadTask: Task<Void, Never>?

    // UI
    var showAboutView: Bool = false
    var showSettingsView: Bool = false

    // Tab choice dialog
    var showTabChoiceDialog: Bool = false
    var pendingURLForTabChoice: URL?

    // Signal to open file in new tab (set by view model, handled by FramePeek.swift)
    var shouldOpenInNewTab: URL?

    // Settings loaded from AppStorage (synced on init and when needed)
    var samplingMode: SamplingMode = .auto
    var samplingIntervalSeconds: Double = 0.5   // used if mode == .interval
    var maxPointsTarget: Int = 2000             // used if mode == .auto / caps
    var emitEveryNSamples: Int = 100            // UI update batch size
    var preferAccuracy: Bool = false             // Use reader path for accurate bitrate (slower but matches ffprobe)

    // Thumbnails settings
    var autoGenerateThumbnails: Bool = true
    var maxThumbnails: Int = 200
    var thumbnailSize: ThumbnailSize = .medium

    // Chart Display settings
    var chartMaxDisplayPoints: Int = 1_000
    var chartMaxDisplayPointsZoomed: Int = 2_000

    // Waveform settings
    var waveformData: [Int: [WaveformSample]] = [:] // Dictionary keyed by track index
    var isExtractingWaveforms: Bool = false
    var expandedWaveformTracks: Set<Int> = [] // Tracks that are expanded/visible
    var waveformHeight: WaveformHeight = .normal
    var waveformLoadedFromCache: Bool = false  // Cache status indicator

    // Sync analysis
    var syncAnalysisResult: SyncAnalysisResult?
    var frameTimingSamples: [FrameTimingSample] = []
    var isAnalyzingSync: Bool = false

    // Color analysis (legacy) — computed from professionalColorAnalysis with caching
    @ObservationIgnored var legacySamplesCache: [ColorSample]?
    @ObservationIgnored var legacySamplesCacheCount: Int = 0
    var colorSamples: [ColorSample] {
        if legacySamplesCacheCount == professionalColorAnalysis.count,
           let cached = legacySamplesCache {
            return cached
        }
        let converted = convertToLegacyColorSamples(professionalColorAnalysis)
        legacySamplesCache = converted
        legacySamplesCacheCount = professionalColorAnalysis.count
        return converted
    }
    var isAnalyzingColor: Bool = false

    // Professional color analysis
    var professionalColorAnalysis: [FrameColorAnalysis] = []
    var colorAnalysisProgress: Double = 0
    var currentFrameAnalysis: FrameColorAnalysis?  // For real-time overlay
    var hdrContentType: HDRContentType = .sdr
    var dolbyVisionConfig: DolbyVisionConfig?

    // Container analysis
    var containerAnalysis: ContainerAnalysisResult?
    var isAnalyzingContainer: Bool = false

    // Always use second-based visualization mode
    var visualizationMode: BitrateVisualizationMode { .second }

    /// Returns true if a file is loaded but cannot be analyzed for bitrate/frame data
    var isFileUnanalyzable: Bool {
        guard let info = extendedInfo else { return false }
        // File is loaded, analysis is complete, but no samples were extracted
        let hasNoSamples = samples.isEmpty && !isAnalyzing
        // Check if there's no video track (resolution is N/A or codec is Unknown)
        let hasNoVideoTrack = info.resolution == "N/A" || info.codec == "Unknown"
        // Check if duration is invalid
        let hasInvalidDuration = durationSeconds <= 0 || !durationSeconds.isFinite

        return hasNoSamples && (hasNoVideoTrack || hasInvalidDuration)
    }

    // MARK: - GOP Frame Details LRU Cache

    func cacheGOPFrameDetails(_ details: [FrameInfo], for id: UUID) {
        gopFrameDetailsCache[id] = details
        gopCacheAccessOrder.removeAll { $0 == id }
        gopCacheAccessOrder.append(id)
        while gopCacheAccessOrder.count > gopCacheMaxSize {
            let evictedID = gopCacheAccessOrder.removeFirst()
            gopFrameDetailsCache.removeValue(forKey: evictedID)
        }
    }

    func getCachedGOPFrameDetails(for id: UUID) -> [FrameInfo]? {
        guard let details = gopFrameDetailsCache[id] else { return nil }
        gopCacheAccessOrder.removeAll { $0 == id }
        gopCacheAccessOrder.append(id)
        return details
    }

    init() {
        loadSettingsFromUserDefaults()
    }

    /// Loads settings from UserDefaults (AppStorage)
    func loadSettingsFromUserDefaults() {
        let defaults = UserDefaults.standard

        // Load sampling mode (convert from SamplingModeSetting string to SamplingMode)
        if let modeString = defaults.string(forKey: "samplingMode") {
            // SamplingModeSetting and SamplingMode use the same raw values
            if let mode = SamplingMode(rawValue: modeString) {
                samplingMode = mode
            }
        }

        // Load other settings
        if defaults.object(forKey: "samplingIntervalSeconds") != nil {
            samplingIntervalSeconds = defaults.double(forKey: "samplingIntervalSeconds")
        }
        if defaults.object(forKey: "maxPointsTarget") != nil {
            maxPointsTarget = defaults.integer(forKey: "maxPointsTarget")
        }
        if defaults.object(forKey: "preferAccuracy") != nil {
            preferAccuracy = defaults.bool(forKey: "preferAccuracy")
        }
        if defaults.object(forKey: "emitEveryNSamples") != nil {
            emitEveryNSamples = defaults.integer(forKey: "emitEveryNSamples")
        }

        // Load Thumbnails settings
        if defaults.object(forKey: "autoGenerateThumbnails") != nil {
            autoGenerateThumbnails = defaults.bool(forKey: "autoGenerateThumbnails")
        }
        if defaults.object(forKey: "maxThumbnails") != nil {
            maxThumbnails = defaults.integer(forKey: "maxThumbnails")
        }
        if let sizeString = defaults.string(forKey: "thumbnailSize"),
           let size = ThumbnailSize(rawValue: sizeString) {
            thumbnailSize = size
        }

        // Load Chart Display settings
        if defaults.object(forKey: "chartMaxDisplayPoints") != nil {
            chartMaxDisplayPoints = defaults.integer(forKey: "chartMaxDisplayPoints")
        }
        if defaults.object(forKey: "chartMaxDisplayPointsZoomed") != nil {
            chartMaxDisplayPointsZoomed = defaults.integer(forKey: "chartMaxDisplayPointsZoomed")
        }
    }

    /// Saves current settings to UserDefaults (called when settings change)
    func saveSettingsToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(samplingMode.rawValue, forKey: "samplingMode")
        defaults.set(samplingIntervalSeconds, forKey: "samplingIntervalSeconds")
        defaults.set(maxPointsTarget, forKey: "maxPointsTarget")
        defaults.set(preferAccuracy, forKey: "preferAccuracy")
    }

    var pendingURL: URL?
    @ObservationIgnored private var currentURL: URL?  // Store current URL for re-analysis
    var currentVideoURL: URL?  // Current video URL for player window
    @ObservationIgnored var rawFrames: [RawFrame] = []  // Store raw frame data for re-aggregation
    @ObservationIgnored var infoTask: Task<Void, Never>?
    @ObservationIgnored var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored var framesTask: Task<Void, Never>?
    @ObservationIgnored var gopTask: Task<Void, Never>?
    @ObservationIgnored var waveformTasks: [Int: Task<Void, Never>] = [:] // Dictionary of extraction tasks per track
    @ObservationIgnored var syncTask: Task<Void, Never>?
    @ObservationIgnored var colorAnalysisTask: Task<Void, Never>?
    @ObservationIgnored var containerTask: Task<Void, Never>?

    enum SamplingMode: String, CaseIterable, Identifiable {
        case auto
        case everyFrame
        case interval

        var id: String { rawValue }
    }
}
