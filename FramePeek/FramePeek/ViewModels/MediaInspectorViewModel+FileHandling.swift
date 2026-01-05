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
        
        // Update tab name immediately with filename
        // This will be updated again when extendedInfo loads, but gives immediate feedback
        let fileName = url.lastPathComponent
        
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
                self.handleIncomingFile(url: URL(fileURLWithPath: path))
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

        // cancel in-flight work
        cancelAllTasks()

        // reset state for new asset
        resetStateForNewAsset()

        // Start all tasks in parallel with detached tasks for true background processing
        infoTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let info = await getExtendedInfo(url: url, asset: assetForInfo)
            // Also load duration for timeline view
            let duration = (try? await assetForInfo.load(.duration).seconds) ?? 0
            await MainActor.run {
                self.extendedInfo = info
                self.durationSeconds = duration
            }
        }
        
        // Start thumbnail generation (uses evenly distributed times)
        if autoGenerateThumbnails {
            startThumbnailGeneration(asset: assetForThumbnails)
        }
        
        // Start frame analysis
        startFrameAnalysis(asset: assetForFrames)
    }
    
    private func cancelAllTasks() {
        infoTask?.cancel()
        framesTask?.cancel()
        thumbnailTask?.cancel()
        infoTask = nil
        thumbnailTask = nil
        framesTask = nil
    }
    
    private func resetStateForNewAsset() {
        samples = []
        rawFrames = []
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        extendedInfo = nil
        isAnalyzing = true
        keyframeThumbs = []
        isGeneratingThumbnails = false
    }

    func cancelAnalysis() {
        cancelAllTasks()
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
        durationSeconds = 0
        isGeneratingThumbnails = false
    }
}

