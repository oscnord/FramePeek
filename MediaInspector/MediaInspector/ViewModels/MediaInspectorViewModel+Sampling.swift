//
//  MediaInspectorViewModel+Sampling.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia

extension MediaInspectorViewModel {
    /// Call this when visualization mode changes to re-aggregate samples
    func handleVisualizationModeChange() {
        guard !rawFrames.isEmpty && !isAnalyzing else { return }
        
        // Defer to next run loop to avoid publishing during view updates
        DispatchQueue.main.async { [weak self] in
            self?.reAggregateSamples()
        }
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

    func makeSamplingOptions(asset: AVAsset) async -> FrameSamplingOptions {
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
    
    func startFrameAnalysis(asset: AVAsset) {
        // Frames (async + progressive updates) - use fast bitrate extraction
        framesTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Compute options (needs async for duration in auto mode)
            let options = await self.makeSamplingOptions(asset: asset)

            // Stream frames progressively using fast extraction
            for await update in extractBitratesFast(asset: asset, options: options) {
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
}

