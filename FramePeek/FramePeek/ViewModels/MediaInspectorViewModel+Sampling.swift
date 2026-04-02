import Foundation
import AVFoundation
import CoreMedia
import FramePeekCore

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

    /// Updates maxBitrate and minBitrate in extendedInfo with peak and minimum bitrate calculated from raw frames
    /// Uses rawFrames instead of aggregated samples to avoid missing peaks due to downsampling
    private func updateMaxBitrateFromSamples() {
        guard let info = extendedInfo else { return }

        // Calculate from rawFrames if available (more accurate, no downsampling)
        // Otherwise fall back to samples
        let maxBitrateKbps: Double
        let minBitrateKbps: Double

        if !rawFrames.isEmpty {
            // Calculate bitrate for all 1-second windows from raw frames
            // rawFrames is pre-sorted by PTS at storage time
            let estimatedFPS = effectiveFPS ?? 30.0
            let defaultFrameDuration = 1.0 / estimatedFPS

            let startTime = rawFrames.first!.pts
            let endTime = rawFrames.last!.pts
            let totalDuration = endTime - startTime + defaultFrameDuration
            let numBuckets = Int(ceil(totalDuration / 1.0))

            guard numBuckets > 0 else { return }

            var bitrates: [Double] = []
            bitrates.reserveCapacity(numBuckets)

            var frameIndex = 0
            for bucketIndex in 0..<numBuckets {
                let bucketStart = startTime + Double(bucketIndex) * 1.0
                let bucketEnd = bucketStart + 1.0

                // Advance to first frame in this bucket
                while frameIndex < rawFrames.count && rawFrames[frameIndex].pts < bucketStart {
                    frameIndex += 1
                }

                // Sum frames in bucket [bucketStart, bucketEnd)
                var totalBytes: Int64 = 0
                var tempIndex = frameIndex
                while tempIndex < rawFrames.count && rawFrames[tempIndex].pts < bucketEnd {
                    totalBytes += rawFrames[tempIndex].size
                    tempIndex += 1
                }

                // Calculate bitrate for this 1-second bucket
                if totalBytes > 0 {
                    let bitrate = (Double(totalBytes) * 8.0) / 1.0
                    bitrates.append(bitrate)
                }
            }

            guard !bitrates.isEmpty else { return }

            let maxBits = bitrates.max() ?? 0
            let minBits = bitrates.min() ?? 0
            maxBitrateKbps = Double(maxBits) / 1000.0
            minBitrateKbps = Double(minBits) / 1000.0
        } else if !samples.isEmpty {
            // Fallback to samples if rawFrames not available
            let maxBits = samples.map(\.bitrate).max() ?? 0
            let minBits = samples.map(\.bitrate).min() ?? 0
            maxBitrateKbps = Double(maxBits) / 1000.0
            minBitrateKbps = Double(minBits) / 1000.0
        } else {
            return
        }

        let maxBitrateString = String(format: "%.0f kb/s", maxBitrateKbps)
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
        // Load format-specific settings from UserDefaults
        let defaults = UserDefaults.standard
        let accountTSOverhead = defaults.object(forKey: "accountTSOverhead") != nil
            ? defaults.bool(forKey: "accountTSOverhead")
            : false
        let smoothSegmentBoundaries = defaults.object(forKey: "smoothSegmentBoundaries") != nil
            ? defaults.bool(forKey: "smoothSegmentBoundaries")
            : true
        let formatAccuracyMode: FormatAccuracyMode = {
            if let modeString = defaults.string(forKey: "formatAccuracyMode"),
               let mode = FormatAccuracyMode(rawValue: modeString) {
                return mode
            }
            return .balanced
        }()

        switch samplingMode {
        case .everyFrame:
            return .everyFrame(
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode,
                accountTSOverhead: accountTSOverhead,
                smoothSegmentBoundaries: smoothSegmentBoundaries,
                formatAccuracyMode: formatAccuracyMode
            )

        case .interval:
            return .interval(
                samplingIntervalSeconds,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode,
                accountTSOverhead: accountTSOverhead,
                smoothSegmentBoundaries: smoothSegmentBoundaries,
                formatAccuracyMode: formatAccuracyMode
            )

        case .auto:
            // Choose an interval so we end up with ~maxPointsTarget points over duration
            let fallback = FrameSamplingOptions.interval(
                1.0,
                maxSamples: maxPointsTarget,
                emitEveryNSamples: emitEveryNSamples,
                preferAccuracy: preferAccuracy,
                visualizationMode: visualizationMode,
                accountTSOverhead: accountTSOverhead,
                smoothSegmentBoundaries: smoothSegmentBoundaries,
                formatAccuracyMode: formatAccuracyMode
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
                visualizationMode: visualizationMode,
                accountTSOverhead: accountTSOverhead,
                smoothSegmentBoundaries: smoothSegmentBoundaries,
                formatAccuracyMode: formatAccuracyMode
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
                    // Store raw frames from final update (pre-sorted by PTS for downstream consumers)
                    if update.isFinished && !update.rawFrames.isEmpty {
                        self.rawFrames = update.rawFrames.sorted { $0.pts < $1.pts }
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
