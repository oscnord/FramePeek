import Foundation
import AVFoundation
import CoreMedia

/// Analyzes audio/video synchronization by examining actual sample timestamps
/// - Parameter asset: The AVAsset to analyze
/// - Returns: SyncAnalysisResult with track timing information
func analyzeAudioVideoSync(asset: AVAsset) async -> SyncAnalysisResult? {
    do {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first else {
            if audioTracks.isEmpty {
                return nil
            }
            return SyncAnalysisResult(
                videoFirstPTS: 0,
                videoDuration: 0,
                videoFrameCount: 0,
                averageVideoFrameInterval: nil,
                frameIntervalVariance: nil,
                hasTimestampGaps: false,
                audioTracks: []
            )
        }

        let videoTimeRange = try await videoTrack.load(.timeRange)
        let videoDuration = videoTimeRange.duration.seconds
        let videoFirstPTS = await getFirstSamplePTS(asset: asset, track: videoTrack) ?? videoTimeRange.start.seconds

        let frameAnalysis = await analyzeFrameTiming(asset: asset, videoTrack: videoTrack)

        var audioTrackSyncInfos: [AudioTrackSyncInfo] = []

        for (index, audioTrack) in audioTracks.enumerated() {
            let audioTimeRange = try await audioTrack.load(.timeRange)
            let audioDuration = audioTimeRange.duration.seconds
            let audioFirstPTS = await getFirstAudioPTS(asset: asset, track: audioTrack) ?? audioTimeRange.start.seconds

            let ptsOffsetMs = (audioFirstPTS - videoFirstPTS) * 1000.0
            let durationDiffMs = abs(audioDuration - videoDuration) * 1000.0

            let syncStatus: SyncStatus
            if durationDiffMs > 1000 {
                syncStatus = .durationMismatch
            } else if abs(ptsOffsetMs) > 100 {
                syncStatus = .significantOffset
            } else if abs(ptsOffsetMs) > 40 {
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
        return SyncAnalysisResult(
            videoFirstPTS: 0,
            videoDuration: 0,
            videoFrameCount: 0,
            averageVideoFrameInterval: nil,
            frameIntervalVariance: nil,
            hasTimestampGaps: false,
            audioTracks: []
        )
    }
}

/// Gets the PTS of the first video sample
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

/// Gets the PTS of the first audio sample
private func getFirstAudioPTS(asset: AVAsset, track: AVAssetTrack) async -> Double? {
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

/// Analyzes frame timing to detect VFR and gaps
/// Returns frame timing samples for visualization with progressive updates
func analyzeFrameTimingStream(
    asset: AVAsset,
    maxSamples: Int = 500
) -> AsyncStream<[FrameTimingSample]> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continuation.finish()
                return
            }

            guard let reader = try? AVAssetReader(asset: asset) else {
                continuation.finish()
                return
            }

            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                continuation.finish()
                return
            }
            reader.add(output)

            guard reader.startReading() else {
                continuation.finish()
                return
            }

            // Estimate frame count for sampling strategy
            let timeRange = (try? await videoTrack.load(.timeRange)) ?? CMTimeRange.zero
            let duration = timeRange.duration.seconds
            let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0
            let estimatedFrameCount = Int(duration * Double(nominalFrameRate))

            // Calculate frame skip interval: sample enough to get maxSamples intervals
            // We need roughly 2x maxSamples frames to get maxSamples intervals
            let targetFramesToRead = maxSamples * 2
            let frameSkipInterval = max(1, estimatedFrameCount / max(targetFramesToRead, 1))

            var allFrames: [(time: Double, interval: Double)] = []
            allFrames.reserveCapacity(targetFramesToRead)
            var previousPTS: Double?
            var frameIndex = 0
            var lastYieldTime = Date()
            let yieldInterval: TimeInterval = 0.2 // Yield every 200ms for UI responsiveness

            while let sampleBuffer = output.copyNextSampleBuffer() {
                if Task.isCancelled { break }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                guard pts.isFinite else {
                    frameIndex += 1
                    continue
                }

                // Always track previous PTS to calculate true interval between consecutive frames
                if let prev = previousPTS {
                    let interval = (pts - prev) * 1000.0
                    if interval > 0 && interval < 1000 {
                        // Only store intervals for sampled frames, but use true consecutive frame interval
                        if frameIndex % frameSkipInterval == 0 {
                            allFrames.append((time: pts, interval: interval))
                        }
                    }
                }

                previousPTS = pts
                frameIndex += 1

                // Early termination: if we have enough samples
                if allFrames.count >= maxSamples * 2 {
                    break
                }

                // Yield progressive updates periodically
                let now = Date()
                if now.timeIntervalSince(lastYieldTime) >= yieldInterval && !allFrames.isEmpty {
                    // Downsample current frames for progressive display
                    let currentSamples = downsampleFrameTiming(allFrames, targetCount: min(maxSamples, allFrames.count))
                    continuation.yield(currentSamples)
                    lastYieldTime = now
                }
            }

            reader.cancelReading()

            guard !allFrames.isEmpty else {
                continuation.finish()
                return
            }

            // Final downsampling if needed
            let samples: [FrameTimingSample]
            if allFrames.count <= maxSamples {
                samples = allFrames.map { FrameTimingSample(time: $0.time, intervalMs: $0.interval) }
            } else {
                samples = downsampleFrameTiming(allFrames, targetCount: maxSamples)
            }

            continuation.yield(samples)
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
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

private struct FrameTimingAnalysis {
    let frameCount: Int
    let averageInterval: Double?
    let intervalVariance: Double?
    let hasGaps: Bool
}

private func analyzeFrameTiming(asset: AVAsset, videoTrack: AVAssetTrack) async -> FrameTimingAnalysis {
    guard let reader = try? AVAssetReader(asset: asset) else {
        return FrameTimingAnalysis(frameCount: 0, averageInterval: nil, intervalVariance: nil, hasGaps: false)
    }

    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    output.alwaysCopiesSampleData = false

    guard reader.canAdd(output) else {
        return FrameTimingAnalysis(frameCount: 0, averageInterval: nil, intervalVariance: nil, hasGaps: false)
    }
    reader.add(output)

    guard reader.startReading() else {
        return FrameTimingAnalysis(frameCount: 0, averageInterval: nil, intervalVariance: nil, hasGaps: false)
    }

    // Estimate frame count for sampling strategy
    let timeRange = (try? await videoTrack.load(.timeRange)) ?? CMTimeRange.zero
    let duration = timeRange.duration.seconds
    let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0
    let estimatedFrameCount = Int(duration * Double(nominalFrameRate))

    // Sample frames strategically: for long videos, we don't need every frame
    // Target: collect enough intervals for accurate statistics (1000-5000 samples)
    let targetSamples = min(5000, max(1000, estimatedFrameCount / 10))
    let frameSkipInterval = max(1, estimatedFrameCount / max(targetSamples, 1))

    var intervals: [Double] = []
    intervals.reserveCapacity(targetSamples)
    var previousPTS: Double?
    var frameCount = 0
    var frameIndex = 0
    var hasGaps = false

    // Early termination: if we've collected enough samples and processed significant portion
    let earlyTerminationThreshold = max(1000, estimatedFrameCount / 2)

    while let sampleBuffer = output.copyNextSampleBuffer() {
        if Task.isCancelled { break }

        // Sample frames: skip some to speed up processing
        if frameIndex % frameSkipInterval != 0 {
            frameIndex += 1
            frameCount += 1
            continue
        }
        frameIndex += 1

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard pts.isFinite else { continue }

        if let prev = previousPTS {
            let interval = pts - prev
            if interval > 0 && interval < 10 {
                intervals.append(interval)
                if interval > 0.5 {
                    hasGaps = true
                }
            }
        }

        previousPTS = pts
        frameCount += 1

        // Early termination: if we have enough samples and processed enough frames
        if intervals.count >= targetSamples && frameCount >= earlyTerminationThreshold {
            break
        }
    }

    reader.cancelReading()

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
