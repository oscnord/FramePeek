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
    @Published var isExtractingKeyframes: Bool = false
    @Published var isGeneratingThumbnails: Bool = false
    @Published var keyframeExtractionProgress: String? = nil  // Optional progress message

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
        isExtractingKeyframes = false
        isGeneratingThumbnails = false
        keyframeExtractionProgress = nil

        // Extended info (async)
        infoTask = Task { [weak self] in
            guard let self else { return }
            self.extendedInfo = await getExtendedInfo(url: url, asset: assetForInfo)
        }
        
        // Separate keyframe extraction task - runs in parallel with thumbnail generation
        keyframeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.isExtractingKeyframes = true
                self.keyframeExtractionProgress = "Loading video track..."
            }

            let duration = (try? await assetForKeyframes.load(.duration).seconds) ?? 0
            
            await MainActor.run {
                self.durationSeconds = duration
                self.keyframeExtractionProgress = "Extracting keyframes..."
            }
            
            // Stream keyframes progressively as they're found
            // Extract ALL keyframes for the timeline (no limit)
            // Don't accumulate in memory - just update UI progressively
            var pendingBatches: [KeyframeMarker] = []
            pendingBatches.reserveCapacity(100) // Batch UI updates
            
            for await keyframeBatch in extractKeyframesStream(
                asset: assetForKeyframes,
                maxKeyframes: 50_000,  // High limit, but extract all keyframes
                minSpacingSeconds: 0.0,  // No minimum spacing - get all keyframes
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.keyframeExtractionProgress = progress
                    }
                }
            ) {
                if Task.isCancelled { break }
                
                pendingBatches.append(contentsOf: keyframeBatch)
                
                // Batch UI updates to reduce MainActor blocking
                // Update every 100 keyframes or when we have a large batch
                if pendingBatches.count >= 100 {
                    let toAppend = pendingBatches
                    pendingBatches.removeAll(keepingCapacity: true)
                    await MainActor.run {
                        self.keyframes.append(contentsOf: toAppend)
                    }
                }
            }
            
            // Append any remaining keyframes
            if !pendingBatches.isEmpty {
                await MainActor.run {
                    self.keyframes.append(contentsOf: pendingBatches)
                }
            }
            
            // Finalize keyframe extraction state
            await MainActor.run {
                self.isExtractingKeyframes = false
                self.keyframeExtractionProgress = nil
            }
        }
        
        // Start thumbnail generation in parallel - don't wait for keyframes
        // Use evenly distributed times based on duration
        thumbnailTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let duration = (try? await assetForKeyframes.load(.duration).seconds) ?? 0
            
            guard duration > 0 else {
                await MainActor.run {
                    self.isGeneratingThumbnails = false
                }
                return
            }
            
            await MainActor.run {
                self.isGeneratingThumbnails = true
            }
            
            // Start thumbnail generation immediately with evenly distributed times
            // This will snap to nearest frames (not necessarily keyframes)
            await self.startThumbnailGenerationFromDuration(
                asset: assetForKeyframes,
                duration: duration,
                maxThumbnails: 200
            )
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
    
    /// Cancels keyframe extraction but preserves already-loaded keyframes
    /// Thumbnail generation continues for already-loaded keyframes
    func cancelKeyframeExtraction() {
        // Cancel both keyframe extraction and thumbnail generation
        keyframeTask?.cancel()
        thumbnailTask?.cancel()
        isExtractingKeyframes = false
        isGeneratingThumbnails = false
        keyframeExtractionProgress = nil
        
        // Note: keyframes and keyframeThumbs arrays are preserved
    }
    
    /// Cancels only thumbnail generation
    func cancelThumbnailGeneration() {
        thumbnailTask?.cancel()
        isGeneratingThumbnails = false
    }
    
    /// Starts thumbnail generation from duration - generates evenly distributed times
    /// This runs in parallel with keyframe extraction
    private func startThumbnailGenerationFromDuration(
        asset: AVAsset,
        duration: Double,
        maxThumbnails: Int
    ) async {
        // Generate evenly distributed target times across the video
        var targetTimes: [Double] = []
        targetTimes.reserveCapacity(maxThumbnails)
        let interval = duration / Double(maxThumbnails - 1)
        for i in 0..<maxThumbnails {
            targetTimes.append(Double(i) * interval)
        }
        
        // Guard against empty selection
        guard !targetTimes.isEmpty else {
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
            return
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            for await thumbnailBatch in GenerateKeyframeThumbnailsStream(
                asset: asset,
                keyframeTimes: targetTimes,  // Use target times directly - generator will find nearest frame
                maxThumbnails: targetTimes.count,
                batchSize: 10
            ) {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.keyframeThumbs.append(contentsOf: thumbnailBatch)
                    self.keyframeThumbs.sort { $0.time < $1.time }
                }
            }
            
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
        }
        
        await MainActor.run {
            self.thumbnailTask = task
        }
    }
    
    /// Starts thumbnail generation evenly distributed across video duration
    /// Uses actual keyframe times (for when we have all keyframes)
    private func startThumbnailGenerationEvenly(
        asset: AVAsset,
        duration: Double,
        allKeyframeTimes: [Double],
        maxThumbnails: Int
    ) async {
        // Guard against empty keyframes
        guard !allKeyframeTimes.isEmpty else {
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
            return
        }
        
        // Select keyframe times evenly distributed across the video
        let selectedTimes: [Double]
        
        if allKeyframeTimes.count <= maxThumbnails {
            // Use all keyframes if we have fewer than max
            selectedTimes = allKeyframeTimes.sorted()
        } else {
            // Distribute evenly across the video duration, snapping to nearest keyframes
            var selected: [Double] = []
            selected.reserveCapacity(maxThumbnails)
            
            let sortedKeyframes = allKeyframeTimes.sorted()
            let interval = duration / Double(maxThumbnails - 1)
            
            for i in 0..<maxThumbnails {
                let targetTime = Double(i) * interval
                
                // Find nearest keyframe to this target time using binary search for efficiency
                var bestTime: Double?
                var bestDistance = Double.greatestFiniteMagnitude
                
                for keyframeTime in sortedKeyframes {
                    let distance = abs(keyframeTime - targetTime)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestTime = keyframeTime
                    } else {
                        // Since sorted, we can break early
                        break
                    }
                }
                
                if let nearest = bestTime {
                    // Avoid duplicates
                    if selected.isEmpty || abs(selected.last! - nearest) > 0.001 {
                        selected.append(nearest)
                    }
                }
            }
            
            // Ensure first and last keyframes are included
            if let first = sortedKeyframes.first, !selected.contains(where: { abs($0 - first) < 0.001 }) {
                selected.insert(first, at: 0)
            }
            if let last = sortedKeyframes.last, !selected.contains(where: { abs($0 - last) < 0.001 }) {
                selected.append(last)
            }
            
            selectedTimes = selected.sorted()
        }
        
        // Guard against empty selection
        guard !selectedTimes.isEmpty else {
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
            return
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            for await thumbnailBatch in GenerateKeyframeThumbnailsStream(
                asset: asset,
                keyframeTimes: selectedTimes,
                maxThumbnails: selectedTimes.count,
                batchSize: 10
            ) {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.keyframeThumbs.append(contentsOf: thumbnailBatch)
                    self.keyframeThumbs.sort { $0.time < $1.time }
                }
            }
            
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
        }
        
        await MainActor.run {
            self.thumbnailTask = task
        }
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
