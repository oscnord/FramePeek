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
    
    // Tab choice dialog
    @Published var showTabChoiceDialog: Bool = false
    @Published var pendingURLForTabChoice: URL?
    
    // Settings loaded from AppStorage (synced on init and when needed)
    @Published var samplingMode: SamplingMode = .auto
    @Published var samplingIntervalSeconds: Double = 0.5   // used if mode == .interval
    @Published var maxPointsTarget: Int = 2000             // used if mode == .auto / caps
    @Published var emitEveryNSamples: Int = 100            // UI update batch size
    @Published var preferAccuracy: Bool = false             // Use reader path for accurate bitrate (slower but matches ffprobe)
    // Always use second-based visualization mode
    var visualizationMode: BitrateVisualizationMode { .second }
    
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
    var rawFrames: [RawFrame] = []  // Store raw frame data for re-aggregation
    var infoTask: Task<Void, Never>?
    var keyframeTask: Task<Void, Never>?
    var thumbnailTask: Task<Void, Never>?
    var framesTask: Task<Void, Never>?

    enum SamplingMode: String, CaseIterable, Identifiable {
        case auto
        case everyFrame
        case interval

        var id: String { rawValue }
    }
}

