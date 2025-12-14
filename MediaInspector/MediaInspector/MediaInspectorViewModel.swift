//
//  MediaInspectorViewModel.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia

@MainActor
final class MediaInspectorViewModel: ObservableObject {
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

    // Sampling UI
    @Published var showSamplingDialog: Bool = false
    @Published var showAboutView: Bool = false
    @Published var samplingMode: SamplingMode = .auto
    @Published var samplingIntervalSeconds: Double = 0.5   // used if mode == .interval
    @Published var maxPointsTarget: Int = 2000             // used if mode == .auto / caps
    @Published var emitEveryNSamples: Int = 100            // UI update batch size
    @Published var preferAccuracy: Bool = true             // Use reader path for accurate bitrate (slower but matches ffprobe)
    @Published var visualizationMode: BitrateVisualizationMode = .second  // How to visualize bitrate (Second/Frame/GOP)
    
    /// Call this when visualization mode changes to re-aggregate samples
    func handleVisualizationModeChange() {
        guard !rawFrames.isEmpty && !isAnalyzing else { return }
        
        // Defer to next run loop to avoid publishing during view updates
        DispatchQueue.main.async { [weak self] in
            self?.reAggregateSamples()
        }
    }

    private var pendingURL: URL?
    private var currentURL: URL?  // Store current URL for re-analysis
    private var rawFrames: [RawFrame] = []  // Store raw frame data for re-aggregation
    private var infoTask: Task<Void, Never>?
    private var keyframeTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var framesTask: Task<Void, Never>?

    enum SamplingMode: String, CaseIterable, Identifiable {
        case auto
        case everyFrame
        case interval

        var id: String { rawValue }
    }

    func handleIncomingFile(url: URL) {
        pendingURL = url
        showSamplingDialog = true
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
        showSamplingDialog = false
        pendingURL = nil
        loadAsset(url: url)
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

        // Extended info (async)
        infoTask = Task { [weak self] in
            guard let self else { return }
            self.extendedInfo = await getExtendedInfo(url: url, asset: assetForInfo)
        }
        
        // Combined keyframe + thumbnail task (extract keyframes once, then generate thumbnails)
        thumbnailTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let duration = (try? await assetForKeyframes.load(.duration).seconds) ?? 0
            let keyframes = await extractKeyframes(asset: assetForKeyframes, minSpacingSeconds: 0.05)

            if Task.isCancelled { return }
            
            await MainActor.run {
                self.durationSeconds = duration
                self.keyframes = keyframes
            }

            // Generate thumbnails from the keyframes we just extracted
            let times = keyframes.map(\.time)
            let thumbs = await GenerateKeyframeThumbnails(
                asset: assetForKeyframes,
                keyframeTimes: times,
                maxThumbnails: 90
            )
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.keyframeThumbs = thumbs
            }
        }

        // Frames (async + progressive updates) - use fast bitrate extraction
        framesTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Compute options (needs async for duration in auto mode)
            let options = await self.makeSamplingOptions(asset: assetForFrames)

            // Stream frames progressively using fast extraction
            for await update in extractBitratesFast(asset: assetForFrames, options: options) {
                if Task.isCancelled { return }

                await MainActor.run {
                    // Store raw frames from final update
                    if update.isFinished && !update.rawFrames.isEmpty {
                        self.rawFrames = update.rawFrames
                        // Re-aggregate with current visualization mode
                        self.reAggregateSamples()
                    } else if !update.appendedSamples.isEmpty {
                        // During extraction, show intermediate samples (using default second mode)
                        self.samples.append(contentsOf: update.appendedSamples)
                    }
                    self.effectiveFPS = update.averageFPS
                    self.minInterval = update.minInterval
                    self.maxInterval = update.maxInterval

                    if update.isFinished {
                        self.isAnalyzing = false
                    }
                }

                if update.isFinished { break }
            }
        }
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
    }
    
    /// Re-aggregates samples from stored raw frames based on current visualization mode
    private func reAggregateSamples() {
        guard !rawFrames.isEmpty else { return }
        
        let aggregated = aggregateFrames(
            rawFrames: rawFrames,
            mode: visualizationMode,
            averageFPS: effectiveFPS,
            maxSamples: maxPointsTarget
        )
        
        samples = aggregated
    }

    private func makeSamplingOptions(asset: AVAsset) async -> FrameSamplingOptions {
        switch samplingMode {
        case .everyFrame:
            return .everyFrame(
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode
            )

        case .interval:
            return .interval(
                samplingIntervalSeconds,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode
            )

        case .auto:
            // Choose an interval so we end up with ~maxPointsTarget points over duration
            let fallback = FrameSamplingOptions.interval(
                1.0,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode
            )

            guard let dur = try? await asset.load(.duration) else { return fallback }
            let seconds = CMTimeGetSeconds(dur)
            guard seconds.isFinite, seconds > 0 else { return fallback }

            let interval = seconds / Double(max(1, maxPointsTarget))
            let clamped = min(max(interval, 0.05), 10.0)
            return .interval(
                clamped,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode
            )
        }
    }
}
