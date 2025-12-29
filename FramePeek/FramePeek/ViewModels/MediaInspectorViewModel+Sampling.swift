//
//  FramePeekViewModel+Sampling.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia

extension FramePeekViewModel {
    /// Re-aggregates samples from stored raw frames (always uses second-based mode)
    private func reAggregateSamples() {
        guard !rawFrames.isEmpty else { return }
        
        let aggregated = aggregateFrames(
            rawFrames: rawFrames,
            mode: visualizationMode,
            averageFPS: effectiveFPS,
            maxSamples: maxPointsTarget
        )
        
        samples = aggregated
        // Update maxBitrate after re-aggregation
        updateMaxBitrateFromSamples()
    }
    
    /// Updates maxBitrate and minBitrate in extendedInfo with peak and minimum bitrate calculated from samples
    private func updateMaxBitrateFromSamples() {
        guard var info = extendedInfo, !samples.isEmpty else { return }
        
        // Calculate peak bitrate from samples (same as BitrateChartStatistics)
        let maxBits = samples.map(\.bitrate).max() ?? 0
        let maxBitrateKbps = Double(maxBits) / 1000.0
        let maxBitrateString = String(format: "%.0f kb/s", maxBitrateKbps)
        
        // Calculate minimum bitrate from samples (same as BitrateChartStatistics)
        let minBits = samples.map(\.bitrate).min() ?? 0
        let minBitrateKbps = Double(minBits) / 1000.0
        let minBitrateString = String(format: "%.0f kb/s", minBitrateKbps)
        
        // Create new ExtendedVideoInfo with updated maxBitrate and minBitrate
        let updatedInfo = ExtendedVideoInfo(
            fileName: info.fileName,
            fileSize: info.fileSize,
            fileSizeBytes: info.fileSizeBytes,
            overallBitrate: info.overallBitrate,
            duration: info.duration,
            durationFormatted: info.durationFormatted,
            containerFormat: info.containerFormat,
            containerFormatProfile: info.containerFormatProfile,
            codecIdRaw: info.codecIdRaw,
            resolution: info.resolution,
            displayAspectRatio: info.displayAspectRatio,
            frameRate: info.frameRate,
            codec: info.codec,
            codecProfile: info.codecProfile,
            codecIdInfo: info.codecIdInfo,
            orientationDegrees: info.orientationDegrees,
            trackBitrate: info.trackBitrate,
            maxBitrate: maxBitrateString, // Use peak from analysis
            minBitrate: minBitrateString, // Use minimum from analysis
            pixelAspectRatio: info.pixelAspectRatio,
            cleanAperture: info.cleanAperture,
            scanType: info.scanType,
            frameRateMode: info.frameRateMode,
            colorSpace: info.colorSpace,
            chromaSubsampling: info.chromaSubsampling,
            bitsPerPixelFrame: info.bitsPerPixelFrame,
            videoStreamSize: info.videoStreamSize,
            colorPrimaries: info.colorPrimaries,
            transferFunction: info.transferFunction,
            matrixCoefficients: info.matrixCoefficients,
            colorRange: info.colorRange,
            bitDepth: info.bitDepth,
            hdrFormat: info.hdrFormat,
            av1CSize: info.av1CSize,
            av1Profile: info.av1Profile,
            av1Level: info.av1Level,
            av1ChromaSubsampling: info.av1ChromaSubsampling,
            av1FullRange: info.av1FullRange,
            creationDate: info.creationDate,
            metadataTitle: info.metadataTitle,
            metadataArtist: info.metadataArtist,
            metadataEncoder: info.metadataEncoder,
            metadataDescription: info.metadataDescription,
            audioTracks: info.audioTracks
        )
        
        extendedInfo = updatedInfo
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
                        // Update maxBitrate in extendedInfo with peak bitrate from analysis
                        self.updateMaxBitrateFromSamples()
                    }
                }

                if update.isFinished { break }
            }
        }
    }
}

