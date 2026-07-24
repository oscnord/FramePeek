import Foundation
import AVFoundation
import CoreMedia

// MARK: - Constants

private enum SyncThresholds {
    static let durationMismatchMs: Double = 1000  // 1 second difference = duration mismatch
    static let significantOffsetMs: Double = 100  // 100ms = significant offset
    static let minorOffsetMs: Double = 40         // 40ms = minor offset (perceptible)
    static let gapThresholdSeconds: Double = 0.5  // 500ms gap detection
}

// MARK: - Streaming Sync Analysis

/// Progressive update from sync analysis: chart batches while scanning,
/// the aggregate result once at the end
public struct SyncAnalysisUpdate: Sendable {
    public let frameTimingSamples: [FrameTimingSample]?
    public let result: SyncAnalysisResult?
}

/// Analyzes audio/video synchronization with one pass over the video track,
/// producing both the frame-timing chart samples and the aggregate result.
public func analyzeSyncStream(
    asset: AVAsset,
    maxChartSamples: Int = 500
) -> AsyncStream<SyncAnalysisUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let result = await runSyncAnalysis(asset: asset, maxChartSamples: maxChartSamples) { batch in
                continuation.yield(SyncAnalysisUpdate(frameTimingSamples: batch, result: nil))
            }
            continuation.yield(SyncAnalysisUpdate(frameTimingSamples: nil, result: result))
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Single-shot variant used by AnalysisEngine/CLI; runs the same single scan
/// without chart batches
public func analyzeAudioVideoSync(asset: AVAsset) async -> SyncAnalysisResult? {
    await runSyncAnalysis(asset: asset, maxChartSamples: 0) { _ in }
}

private func runSyncAnalysis(
    asset: AVAsset,
    maxChartSamples: Int,
    onChartBatch: ([FrameTimingSample]) -> Void
) async -> SyncAnalysisResult? {
    do {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first else {
            // Audio-only file - return audio track info without video comparison
            if audioTracks.isEmpty {
                return nil
            }

            var audioTrackSyncInfos: [AudioTrackSyncInfo] = []
            for (index, audioTrack) in audioTracks.enumerated() {
                let audioTimeRange = try await audioTrack.load(.timeRange)
                let audioDuration = audioTimeRange.duration.seconds
                guard audioDuration.isFinite else { continue }

                let audioFirstPTS = await getFirstSamplePTS(asset: asset, track: audioTrack) ?? audioTimeRange.start.seconds
                guard audioFirstPTS.isFinite else { continue }

                audioTrackSyncInfos.append(AudioTrackSyncInfo(
                    trackIndex: index,
                    audioFirstPTS: audioFirstPTS,
                    audioDuration: audioDuration,
                    syncOffsetMs: 0,
                    durationDifferenceMs: 0,
                    syncStatus: .inSync  // No video to compare against
                ))
            }

            return SyncAnalysisResult(
                videoFirstPTS: 0,
                videoDuration: 0,
                videoFrameCount: 0,
                averageVideoFrameInterval: nil,
                frameIntervalVariance: nil,
                hasTimestampGaps: false,
                audioTracks: audioTrackSyncInfos
            )
        }

        let videoTimeRange = try await videoTrack.load(.timeRange)
        let videoDuration = videoTimeRange.duration.seconds
        guard videoDuration.isFinite else { return nil }

        let videoFirstPTS = await getFirstSamplePTS(asset: asset, track: videoTrack) ?? videoTimeRange.start.seconds
        guard videoFirstPTS.isFinite else { return nil }

        let frameAnalysis = await scanVideoTiming(
            asset: asset,
            videoTrack: videoTrack,
            maxChartSamples: maxChartSamples,
            onChartBatch: onChartBatch
        )

        var audioTrackSyncInfos: [AudioTrackSyncInfo] = []

        for (index, audioTrack) in audioTracks.enumerated() {
            let audioTimeRange = try await audioTrack.load(.timeRange)
            let audioDuration = audioTimeRange.duration.seconds
            guard audioDuration.isFinite else { continue }

            let audioFirstPTS = await getFirstSamplePTS(asset: asset, track: audioTrack) ?? audioTimeRange.start.seconds
            guard audioFirstPTS.isFinite else { continue }

            let ptsOffsetMs = (audioFirstPTS - videoFirstPTS) * 1000.0
            let durationDiffMs = abs(audioDuration - videoDuration) * 1000.0

            let syncStatus: SyncStatus
            if durationDiffMs > SyncThresholds.durationMismatchMs {
                syncStatus = .durationMismatch
            } else if abs(ptsOffsetMs) > SyncThresholds.significantOffsetMs {
                syncStatus = .significantOffset
            } else if abs(ptsOffsetMs) > SyncThresholds.minorOffsetMs {
                syncStatus = .minorOffset
            } else {
                syncStatus = .inSync
            }

            audioTrackSyncInfos.append(AudioTrackSyncInfo(
                trackIndex: index,
                audioFirstPTS: audioFirstPTS,
                audioDuration: audioDuration,
                syncOffsetMs: ptsOffsetMs,
                durationDifferenceMs: durationDiffMs,
                syncStatus: syncStatus
            ))
        }

        return SyncAnalysisResult(
            videoFirstPTS: videoFirstPTS,
            videoDuration: videoDuration,
            videoFrameCount: frameAnalysis.frameCount,
            averageVideoFrameInterval: frameAnalysis.averageInterval,
            frameIntervalVariance: frameAnalysis.intervalVariance,
            hasTimestampGaps: frameAnalysis.hasGaps,
            audioTracks: audioTrackSyncInfos
        )
    } catch {
        return nil
    }
}

/// Gets the PTS of the first sample from a track
private func getFirstSamplePTS(asset: AVAsset, track: AVAssetTrack) async -> Double? {
    guard let reader = try? AVAssetReader(asset: asset) else { return nil }

    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false

    guard reader.canAdd(output) else { return nil }
    reader.add(output)

    guard reader.startReading() else { return nil }

    var firstPTS: Double?

    if let sampleBuffer = output.copyNextSampleBuffer() {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if pts.isFinite {
            firstPTS = pts
        }
    }

    reader.cancelReading()
    return firstPTS
}

// MARK: - Combined Video Timing Scan

private struct FrameTimingAnalysis {
    let frameCount: Int
    let averageInterval: Double?
    let intervalVariance: Double?
    let hasGaps: Bool
}

/// One pass over the video track collects both the interval statistics
/// (previously a private full scan) and the chart samples (previously a
/// second full scan)
private func scanVideoTiming(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    maxChartSamples: Int,
    onChartBatch: ([FrameTimingSample]) -> Void
) async -> FrameTimingAnalysis {
    let empty = FrameTimingAnalysis(frameCount: 0, averageInterval: nil, intervalVariance: nil, hasGaps: false)

    guard let reader = try? AVAssetReader(asset: asset) else { return empty }

    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    output.alwaysCopiesSampleData = false

    guard reader.canAdd(output) else { return empty }
    reader.add(output)

    guard reader.startReading() else { return empty }

    // Estimate frame count for the sampling cadences
    let timeRange = (try? await videoTrack.load(.timeRange)) ?? CMTimeRange.zero
    let duration = timeRange.duration.seconds
    let nominalFrameRate = await AVAssetLoader.nominalFrameRate(of: videoTrack)
    let estimatedFrameCount = Int(duration * Double(nominalFrameRate))

    // Statistics want 1000-5000 intervals; the chart wants ~2x its target
    let statsTarget = min(5000, max(1000, estimatedFrameCount / 10))
    let statsSkipInterval = max(1, estimatedFrameCount / max(statsTarget, 1))
    let chartTarget = maxChartSamples * 2
    let chartSkipInterval = max(1, estimatedFrameCount / max(chartTarget, 1))

    var intervals: [Double] = []
    intervals.reserveCapacity(statsTarget)
    var chartFrames: [(time: Double, interval: Double)] = []
    chartFrames.reserveCapacity(chartTarget)

    var previousPTS: Double?
    var frameCount = 0
    var frameIndex = 0
    var hasGaps = false
    var lastYieldTime = Date.now
    let yieldInterval: TimeInterval = 0.2

    while let sampleBuffer = output.copyNextSampleBuffer() {
        if Task.isCancelled { break }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameCount += 1

        guard pts.isFinite else {
            frameIndex += 1
            continue
        }

        if let prev = previousPTS {
            let interval = pts - prev
            if interval > 0 && interval < 10 {
                if frameIndex % statsSkipInterval == 0 {
                    intervals.append(interval)
                }
                if interval > SyncThresholds.gapThresholdSeconds {
                    hasGaps = true
                }
            }

            if maxChartSamples > 0, interval > 0, interval < 1,
               frameIndex % chartSkipInterval == 0, chartFrames.count < chartTarget {
                chartFrames.append((time: pts, interval: interval * 1000.0))
            }
        }

        previousPTS = pts
        frameIndex += 1

        if maxChartSamples > 0, !chartFrames.isEmpty {
            let now = Date.now
            if now.timeIntervalSince(lastYieldTime) >= yieldInterval {
                onChartBatch(downsampleFrameTiming(chartFrames, targetCount: min(maxChartSamples, chartFrames.count)))
                lastYieldTime = now
            }
        }

        // Keep cancellation responsive on long files while scanning full timeline for late gaps.
        if frameCount % 5000 == 0 {
            await Task.yield()
        }
    }

    if reader.status == .reading {
        reader.cancelReading()
    }

    if maxChartSamples > 0, !chartFrames.isEmpty {
        onChartBatch(downsampleFrameTiming(chartFrames, targetCount: min(maxChartSamples, chartFrames.count)))
    }

    guard !intervals.isEmpty else {
        return FrameTimingAnalysis(frameCount: frameCount, averageInterval: nil, intervalVariance: nil, hasGaps: hasGaps)
    }

    let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
    let variance = intervals.map { pow($0 - avgInterval, 2) }.reduce(0, +) / Double(intervals.count)

    return FrameTimingAnalysis(
        frameCount: frameCount,
        averageInterval: avgInterval,
        intervalVariance: variance,
        hasGaps: hasGaps
    )
}

/// Downsamples frame timing data using uniform sampling
private func downsampleFrameTiming(
    _ frames: [(time: Double, interval: Double)],
    targetCount: Int
) -> [FrameTimingSample] {
    guard frames.count > targetCount, targetCount >= 2 else {
        return frames.map { FrameTimingSample(time: $0.time, intervalMs: $0.interval) }
    }

    var samples: [FrameTimingSample] = []
    samples.reserveCapacity(targetCount)

    let step = Double(frames.count) / Double(targetCount)

    for i in 0..<targetCount {
        let index = Int(Double(i) * step)
        if index < frames.count {
            let frame = frames[index]
            samples.append(FrameTimingSample(time: frame.time, intervalMs: frame.interval))
        }
    }

    return samples
}
