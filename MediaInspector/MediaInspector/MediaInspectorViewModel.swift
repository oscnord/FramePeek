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

    // Sampling UI
    @Published var showSamplingDialog: Bool = false
    @Published var samplingMode: SamplingMode = .auto
    @Published var samplingIntervalSeconds: Double = 1.0   // used if mode == .interval
    @Published var maxPointsTarget: Int = 2000             // used if mode == .auto / caps
    @Published var emitEveryNSamples: Int = 100            // UI update batch size

    private var pendingURL: URL?
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
        let asset = AVURLAsset(url: url)

        // cancel in-flight work
        infoTask?.cancel()
        framesTask?.cancel()
        infoTask = nil
        keyframeTask = nil
        thumbnailTask = nil
        framesTask = nil

        // reset state for new asset
        samples = []
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        extendedInfo = nil
        isAnalyzing = true

        // Extended info (async)
        infoTask = Task { [weak self] in
            guard let self else { return }
            self.extendedInfo = await getExtendedInfo(url: url, asset: asset)
        }
        
        keyframeTask = Task { [weak self] in
            guard let self else { return }
            self.durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
            self.keyframes = await extractKeyframes(asset: asset, minSpacingSeconds: 0.05)
        }
        
        thumbnailTask = Task { [weak self] in
            guard let self else { return }

            self.durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
            self.keyframes = await extractKeyframes(asset: asset, minSpacingSeconds: 0.05)

            // Generate thumbnails from keyframe times
            let times = self.keyframes.map(\.time)
            self.keyframeThumbs = await GenerateKeyframeThumbnails(
                asset: asset,
                keyframeTimes: times,
                maxThumbnails: 90,
                thumbHeight: 38
            )
        }

        // Frames (async + progressive updates)
        framesTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Compute options (needs async for duration in auto mode)
            let options = await self.makeSamplingOptions(asset: asset)

            // Stream frames progressively
            for await update in extractFramesStream(asset: asset, options: options) {
                if Task.isCancelled { return }

                await MainActor.run {
                    if !update.appendedSamples.isEmpty {
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
        extendedInfo = nil
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        keyframeThumbs = []
    }

    private func makeSamplingOptions(asset: AVAsset) async -> FrameSamplingOptions {
        switch samplingMode {
        case .everyFrame:
            return .everyFrame(
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples
            )

        case .interval:
            return .interval(
                samplingIntervalSeconds,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples
            )

        case .auto:
            // Choose an interval so we end up with ~maxPointsTarget points over duration
            let fallback = FrameSamplingOptions.interval(
                1.0,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples
            )

            guard let dur = try? await asset.load(.duration) else { return fallback }
            let seconds = CMTimeGetSeconds(dur)
            guard seconds.isFinite, seconds > 0 else { return fallback }

            let interval = seconds / Double(max(1, maxPointsTarget))
            let clamped = min(max(interval, 0.05), 10.0)
            return .interval(
                clamped,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples
            )
        }
    }
}
