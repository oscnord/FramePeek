import Foundation
import AVFoundation
import SwiftUI

extension FramePeekViewModel {
    enum TabChoiceAction {
        case currentTab
        case newTab
    }

    func handleIncomingFile(url: URL) {
        // Reload settings from UserDefaults in case they changed
        loadSettingsFromUserDefaults()

        // Check if a file is already loaded in this tab
        if extendedInfo != nil {
            // File is loaded, check user's preference for file opening behavior
            let behaviorString = UserDefaults.standard.string(forKey: "fileOpeningBehavior") ?? "prompt"
            let behavior = FileOpeningBehavior(rawValue: behaviorString) ?? .prompt

            switch behavior {
            case .prompt:
                // Show dialog to let user choose
                pendingURLForTabChoice = url
                showTabChoiceDialog = true

            case .newTab:
                // Signal to open in new tab (FramePeek.swift will handle this)
                // Clear any pending tab choice dialog state
                pendingURLForTabChoice = nil
                showTabChoiceDialog = false
                shouldOpenInNewTab = url

            case .currentTab:
                // Load in current tab (replaces existing file)
                pendingURL = url
                confirmSamplingAndLoad()
            }
        } else {
            // No file loaded, proceed directly
            pendingURL = url
            confirmSamplingAndLoad()
        }
    }

    func handleTabChoice(action: TabChoiceAction) {
        guard let url = pendingURLForTabChoice else {
            showTabChoiceDialog = false
            pendingURLForTabChoice = nil
            return
        }

        showTabChoiceDialog = false
        pendingURLForTabChoice = nil

        switch action {
        case .currentTab:
            // Load in current tab (replaces existing file)
            pendingURL = url
            confirmSamplingAndLoad()

        case .newTab:
            // Signal to open in new tab (FramePeek.swift will handle this via onChange observer)
            shouldOpenInNewTab = url
        }
    }

    func cancelTabChoice() {
        showTabChoiceDialog = false
        pendingURLForTabChoice = nil
    }

    func pickFile() {
        openFileDialog { [weak self] path in
            guard let self, let path else { return }
            // Ensure we're on MainActor for @Published property updates
            Task { @MainActor in
                let url = URL(fileURLWithPath: path)
                FileHistoryManager.shared.addFile(url)
                self.handleIncomingFile(url: url)
            }
        }
    }

    func confirmSamplingAndLoad() {
        guard let url = pendingURL else {
            return
        }
        // Save current settings to UserDefaults before loading
        saveSettingsToUserDefaults()
        let urlToLoad = url
        pendingURL = nil
        loadAsset(url: urlToLoad)
    }

    private func loadAsset(url: URL) {
        loadAssetInternal(url: url)
    }

    private func loadAssetInternal(url: URL) {
        // Create separate asset instances for each reader to avoid blocking
        // AVAsset can only have one active AVAssetReader at a time
        let assetForInfo = AVURLAsset(url: url)
        let assetForThumbnails = AVURLAsset(url: url)
        let assetForFrames = AVURLAsset(url: url)
        let assetForGOP = AVURLAsset(url: url)

        // cancel in-flight work
        cancelAllTasks()

        // reset state for new asset
        resetStateForNewAsset()

        // Store current video URL for player window
        currentVideoURL = url

        // Start all tasks in parallel with detached tasks for true background processing
        infoTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let info = await getExtendedInfo(url: url, asset: assetForInfo)
            // Also load duration for timeline view
            let duration = (try? await assetForInfo.load(.duration).seconds) ?? 0
            await MainActor.run {
                self.extendedInfo = info
                self.durationSeconds = duration

                // Initialize expanded tracks (first 3 tracks or all if <= 3)
                if !info.audioTracks.isEmpty {
                    let trackIndices = Set(info.audioTracks.map { $0.index })
                    if trackIndices.count <= 3 {
                        self.expandedWaveformTracks = trackIndices
                    } else {
                        // Only expand first 3 tracks by default
                        self.expandedWaveformTracks = Set(Array(trackIndices.prefix(3)))
                    }
                    // Start extracting waveforms for expanded tracks
                    self.startWaveformExtraction(asset: assetForInfo, audioTracks: info.audioTracks, duration: duration)
                    // Start sync analysis automatically when audio tracks are detected
                    self.startSyncAnalysis(asset: assetForInfo, audioTracks: info.audioTracks)
                }

                // Update player window if it's open and this is the active ViewModel
                if PlayerViewModelManager.shared.activeViewModel === self {
                    PlayerViewModelManager.shared.setActiveViewModel(self)
                }
            }
        }

        // Start thumbnail generation (uses evenly distributed times)
        if autoGenerateThumbnails {
            startThumbnailGeneration(asset: assetForThumbnails)
        }

        // Start frame analysis
        startFrameAnalysis(asset: assetForFrames)

        // Start fast GOP preview analysis
        startGOPPreview(asset: assetForGOP)
    }

    private func cancelAllTasks() {
        infoTask?.cancel()
        framesTask?.cancel()
        thumbnailTask?.cancel()
        gopTask?.cancel()
        syncTask?.cancel()
        colorAnalysisTask?.cancel()
        // Cancel all waveform extraction tasks
        for task in waveformTasks.values {
            task.cancel()
        }
        waveformTasks.removeAll()
        infoTask = nil
        thumbnailTask = nil
        framesTask = nil
        gopTask = nil
        syncTask = nil
        colorAnalysisTask = nil
    }

    private func resetStateForNewAsset() {
        resetCommonState()
        isAnalyzing = true
    }

    func cancelAnalysis() {
        cancelAllTasks()
        isAnalyzing = false
    }

    func reset() {
        cancelAnalysis()
        resetCommonState()
        // Additional properties only reset on full reset
        hoveredKeyframeTime = nil
        visibleTimeRange = nil
        durationSeconds = 0
    }

    /// Resets all common state properties shared between resetStateForNewAsset and reset
    private func resetCommonState() {
        samples = []
        rawFrames = []
        extendedInfo = nil
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        keyframeThumbs = []
        isGeneratingThumbnails = false
        gopAnalysis = nil
        isAnalyzingGOP = false
        currentVideoURL = nil
        waveformData = [:]
        isExtractingWaveforms = false
        expandedWaveformTracks = []
        syncAnalysisResult = nil
        frameTimingSamples = []
        isAnalyzingSync = false
        colorSamples = []
        isAnalyzingColor = false
        currentPlaybackTime = nil
    }
}
