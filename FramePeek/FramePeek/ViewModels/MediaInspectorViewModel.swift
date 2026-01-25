import Foundation
import AVFoundation
import CoreMedia
import SwiftUI
import FramePeekCore

@MainActor
final class FramePeekViewModel: ObservableObject {
    @Published var samples: [BitrateSample] = []
    @Published var extendedInfo: ExtendedVideoInfo?
    @Published var effectiveFPS: Double?
    @Published var minInterval: Double?
    @Published var maxInterval: Double?
    @Published var hoveredSample: BitrateSample?
    @Published var hoveredTimestamp: Double?  // Shared hover state for cross-chart sync
    @Published var isAnalyzing: Bool = false
    @Published var durationSeconds: Double = 0
    @Published var keyframeThumbs: [KeyframeThumbnail] = []
    @Published var hoveredKeyframeTime: Double?  // Shared hover state for syncing thumbnails and chart
    @Published var visibleTimeRange: ClosedRange<Double>? // Zoom state
    @Published var isGeneratingThumbnails: Bool = false

    // GOP analysis
    @Published var gopAnalysis: GOPAnalysisResult?
    @Published var isAnalyzingGOP: Bool = false
    @Published var selectedGOPIndex: Int? // Selected GOP for details view
    @Published var gopLoadedFromCache: Bool = false  // Cache status indicator
    
    // GOP frame detail extraction (on-demand loading)
    @Published var selectedGOPFrameDetails: [FrameInfo]?
    @Published var isLoadingGOPFrameDetails: Bool = false
    @Published var gopFrameDetailsCache: [UUID: [FrameInfo]] = [:]
    @Published var preloadingGOPIndices: Set<Int> = []
    @Published var codecSupportsFrameTypes: Bool = true
    var frameDetailPreloadTask: Task<Void, Never>?

    // UI
    @Published var showAboutView: Bool = false
    @Published var showSettingsView: Bool = false

    // Tab choice dialog
    @Published var showTabChoiceDialog: Bool = false
    @Published var pendingURLForTabChoice: URL?

    // Signal to open file in new tab (set by view model, handled by FramePeek.swift)
    @Published var shouldOpenInNewTab: URL?

    // Settings loaded from AppStorage (synced on init and when needed)
    @Published var samplingMode: SamplingMode = .auto
    @Published var samplingIntervalSeconds: Double = 0.5   // used if mode == .interval
    @Published var maxPointsTarget: Int = 2000             // used if mode == .auto / caps
    @Published var emitEveryNSamples: Int = 100            // UI update batch size
    @Published var preferAccuracy: Bool = false             // Use reader path for accurate bitrate (slower but matches ffprobe)

    // Thumbnails settings
    @Published var autoGenerateThumbnails: Bool = true
    @Published var maxThumbnails: Int = 200
    @Published var thumbnailSize: ThumbnailSize = .medium

    // Chart Display settings
    @Published var chartMaxDisplayPoints: Int = 1_000
    @Published var chartMaxDisplayPointsZoomed: Int = 2_000

    // Waveform settings
    @Published var waveformData: [Int: [WaveformSample]] = [:] // Dictionary keyed by track index
    @Published var isExtractingWaveforms: Bool = false
    @Published var expandedWaveformTracks: Set<Int> = [] // Tracks that are expanded/visible
    @Published var waveformHeight: WaveformHeight = .normal
    @Published var waveformLoadedFromCache: Bool = false  // Cache status indicator

    // Sync analysis
    @Published var syncAnalysisResult: SyncAnalysisResult?
    @Published var frameTimingSamples: [FrameTimingSample] = []
    @Published var isAnalyzingSync: Bool = false

    // Color analysis (legacy)
    @Published var colorSamples: [ColorSample] = []
    @Published var isAnalyzingColor: Bool = false
    
    // Professional color analysis
    @Published var professionalColorAnalysis: [FrameColorAnalysis] = []
    @Published var colorAnalysisProgress: Double = 0
    @Published var currentFrameAnalysis: FrameColorAnalysis?  // For real-time overlay
    @Published var hdrContentType: HDRContentType = .sdr
    @Published var dolbyVisionConfig: DolbyVisionConfig?

    // Container analysis
    @Published var containerAnalysis: ContainerAnalysisResult?
    @Published var isAnalyzingContainer: Bool = false

    // Playback position
    @Published var currentPlaybackTime: Double?

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
    private var currentURL: URL?  // Store current URL for re-analysis
    @Published var currentVideoURL: URL?  // Current video URL for player window
    var rawFrames: [RawFrame] = []  // Store raw frame data for re-aggregation
    var infoTask: Task<Void, Never>?
    var thumbnailTask: Task<Void, Never>?
    var framesTask: Task<Void, Never>?
    var gopTask: Task<Void, Never>?
    var waveformTasks: [Int: Task<Void, Never>] = [:] // Dictionary of extraction tasks per track
    var syncTask: Task<Void, Never>?
    var colorAnalysisTask: Task<Void, Never>?
    var containerTask: Task<Void, Never>?

    enum SamplingMode: String, CaseIterable, Identifiable {
        case auto
        case everyFrame
        case interval

        var id: String { rawValue }
    }
}
