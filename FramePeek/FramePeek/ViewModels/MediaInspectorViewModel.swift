//
//  FramePeekViewModel.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia
import SwiftUI

@MainActor
final class FramePeekViewModel: ObservableObject {
    @Published var samples: [BitrateSample] = []
    @Published var extendedInfo: ExtendedVideoInfo?
    @Published var effectiveFPS: Double?
    @Published var minInterval: Double?
    @Published var maxInterval: Double?
    @Published var hoveredSample: BitrateSample?
    @Published var isAnalyzing: Bool = false
    // Keyframes
    @Published var keyframes: [KeyframeMarker] = []
    @Published var durationSeconds: Double = 0
    @Published var keyframeThumbs: [KeyframeThumbnail] = []
    @Published var hoveredKeyframeTime: Double? = nil  // Shared hover state for syncing thumbnails, timeline, and chart
    @Published var visibleTimeRange: ClosedRange<Double>? = nil // Zoom state
    @Published var isExtractingKeyframes: Bool = false
    @Published var isGeneratingThumbnails: Bool = false
    @Published var keyframeExtractionProgress: String? = nil  // Optional progress message

    // Sampling UI
    @Published var showSamplingDialog: Bool = false
    @Published var showAboutView: Bool = false
    @Published var showSettingsView: Bool = false
    
    // Settings loaded from AppStorage (synced on init and when needed)
    @Published var samplingMode: SamplingMode = .auto
    @Published var samplingIntervalSeconds: Double = 0.5   // used if mode == .interval
    @Published var maxPointsTarget: Int = 2000             // used if mode == .auto / caps
    @Published var emitEveryNSamples: Int = 100            // UI update batch size
    @Published var preferAccuracy: Bool = false             // Use reader path for accurate bitrate (slower but matches ffprobe)
    @Published var visualizationMode: BitrateVisualizationMode = .second  // How to visualize bitrate (Second/Frame/GOP)
    
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
        if let vizString = defaults.string(forKey: "visualizationMode"),
           let vizMode = BitrateVisualizationMode(rawValue: vizString) {
            visualizationMode = vizMode
        }
    }
    
    /// Saves current settings to UserDefaults (called when settings change)
    func saveSettingsToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(samplingMode.rawValue, forKey: "samplingMode")
        defaults.set(samplingIntervalSeconds, forKey: "samplingIntervalSeconds")
        defaults.set(maxPointsTarget, forKey: "maxPointsTarget")
        defaults.set(preferAccuracy, forKey: "preferAccuracy")
        defaults.set(visualizationMode.rawValue, forKey: "visualizationMode")
    }
    
    private var pendingURL: URL?
    private var currentURL: URL?  // Store current URL for re-analysis
    var rawFrames: [RawFrame] = []  // Store raw frame data for re-aggregation
    private var infoTask: Task<Void, Never>?
    var keyframeTask: Task<Void, Never>?
    var thumbnailTask: Task<Void, Never>?
    var framesTask: Task<Void, Never>?

    enum SamplingMode: String, CaseIterable, Identifiable {
        case auto
        case everyFrame
        case interval

        var id: String { rawValue }
    }

    func handleIncomingFile(url: URL) {
        // Reload settings from UserDefaults in case they changed
        loadSettingsFromUserDefaults()
        pendingURL = url
        
        // Check if user wants to see settings dialog on file load
        let showDialog = UserDefaults.standard.object(forKey: "showSettingsOnFileLoad") == nil ? true : UserDefaults.standard.bool(forKey: "showSettingsOnFileLoad")
        
        if showDialog {
            showSamplingDialog = true
        } else {
            // Skip dialog and use settings directly
            confirmSamplingAndLoad()
        }
    }

    func pickFile() {
        openFileDialog { [weak self] path in
            guard let self, let path else { return }
            self.handleIncomingFile(url: URL(fileURLWithPath: path))
        }
    }

    func confirmSamplingAndLoad() {
        guard let url = pendingURL else {
            showSamplingDialog = false
            return
        }
        // Save current settings to UserDefaults before loading
        saveSettingsToUserDefaults()
        showSamplingDialog = false
        let urlToLoad = url
        pendingURL = nil
        loadAsset(url: urlToLoad)
    }

    func cancelSamplingDialog() {
        showSamplingDialog = false
        pendingURL = nil
    }

    private func loadAsset(url: URL) {
        currentURL = url
        loadAssetInternal(url: url)
    }
    
    private func loadAssetInternal(url: URL) {
        // Create separate asset instances for each reader to avoid blocking
        // AVAsset can only have one active AVAssetReader at a time
        let assetForInfo = AVURLAsset(url: url)
        let assetForKeyframes = AVURLAsset(url: url)
        let assetForFrames = AVURLAsset(url: url)

        // cancel in-flight work
        infoTask?.cancel()
        framesTask?.cancel()
        keyframeTask?.cancel()
        thumbnailTask?.cancel()
        infoTask = nil
        keyframeTask = nil
        thumbnailTask = nil
        framesTask = nil

        // reset state for new asset
        samples = []
        rawFrames = []
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        extendedInfo = nil
        isAnalyzing = true
        keyframes = []
        keyframeThumbs = []
        isExtractingKeyframes = false
        isGeneratingThumbnails = false
        keyframeExtractionProgress = nil

        // Extended info (async)
        infoTask = Task { [weak self] in
            guard let self else { return }
            self.extendedInfo = await getExtendedInfo(url: url, asset: assetForInfo)
        }
        
        // Start keyframe extraction
        startKeyframeExtraction(asset: assetForKeyframes)
        
        // Start thumbnail generation
        startThumbnailGeneration(asset: assetForKeyframes)
        
        // Start frame analysis
        startFrameAnalysis(asset: assetForFrames)
    }

    func cancelAnalysis() {
        infoTask?.cancel()
        keyframeTask?.cancel()
        thumbnailTask?.cancel()
        framesTask?.cancel()
        infoTask = nil
        framesTask = nil
        isAnalyzing = false
    }

    func reset() {
        cancelAnalysis()
        samples = []
        rawFrames = []
        extendedInfo = nil
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        hoveredKeyframeTime = nil
        keyframeThumbs = []
        visibleTimeRange = nil
        isExtractingKeyframes = false
        isGeneratingThumbnails = false
        keyframeExtractionProgress = nil
    }
}

