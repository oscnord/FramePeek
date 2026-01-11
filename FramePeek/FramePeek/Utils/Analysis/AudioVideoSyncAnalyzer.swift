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
                audioFirstPTS: 0,
                videoDuration: 0,
                audioDuration: 0,
                videoFrameCount: 0,
                averageVideoFrameInterval: nil,
                frameIntervalVariance: nil,
                hasTimestampGaps: false,
                syncStatus: .noVideo
            )
        }
        
        guard let audioTrack = audioTracks.first else {
            let videoTimeRange = try await videoTrack.load(.timeRange)
            let videoFirstPTS = await getFirstSamplePTS(asset: asset, track: videoTrack)
            return SyncAnalysisResult(
                videoFirstPTS: videoFirstPTS ?? videoTimeRange.start.seconds,
                audioFirstPTS: 0,
                videoDuration: videoTimeRange.duration.seconds,
                audioDuration: 0,
                videoFrameCount: 0,
                averageVideoFrameInterval: nil,
                frameIntervalVariance: nil,
                hasTimestampGaps: false,
                syncStatus: .noAudio
            )
        }
        
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let audioTimeRange = try await audioTrack.load(.timeRange)
        
        let videoDuration = videoTimeRange.duration.seconds
        let audioDuration = audioTimeRange.duration.seconds
        
        let videoFirstPTS = await getFirstSamplePTS(asset: asset, track: videoTrack) ?? videoTimeRange.start.seconds
        let audioFirstPTS = await getFirstAudioPTS(asset: asset, track: audioTrack) ?? audioTimeRange.start.seconds
        
        let frameAnalysis = await analyzeFrameTiming(asset: asset, videoTrack: videoTrack)
        
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
        
        return SyncAnalysisResult(
            videoFirstPTS: videoFirstPTS,
            audioFirstPTS: audioFirstPTS,
            videoDuration: videoDuration,
            audioDuration: audioDuration,
            videoFrameCount: frameAnalysis.frameCount,
            averageVideoFrameInterval: frameAnalysis.averageInterval,
            frameIntervalVariance: frameAnalysis.intervalVariance,
            hasTimestampGaps: frameAnalysis.hasGaps,
            syncStatus: syncStatus
        )
    } catch {
        return SyncAnalysisResult(
            videoFirstPTS: 0,
            audioFirstPTS: 0,
            videoDuration: 0,
            audioDuration: 0,
            videoFrameCount: 0,
            averageVideoFrameInterval: nil,
            frameIntervalVariance: nil,
            hasTimestampGaps: false,
            syncStatus: .analysisError
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
/// Returns frame timing samples for visualization
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
            
            let timeRange = try? await videoTrack.load(.timeRange)
            let duration = timeRange?.duration.seconds ?? 0
            
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
            
            var allFrames: [(time: Double, interval: Double)] = []
            var previousPTS: Double?
            var frameCount = 0
            
            while let sampleBuffer = output.copyNextSampleBuffer() {
                if Task.isCancelled { break }
                
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                guard pts.isFinite else { continue }
                
                if let prev = previousPTS {
                    let interval = (pts - prev) * 1000.0
                    if interval > 0 && interval < 1000 {
                        allFrames.append((time: pts, interval: interval))
                    }
                }
                
                previousPTS = pts
                frameCount += 1
            }
            
            reader.cancelReading()
            
            guard !allFrames.isEmpty else {
                continuation.finish()
                return
            }
            
            var samples: [FrameTimingSample] = []
            
            if allFrames.count <= maxSamples {
                samples = allFrames.map { FrameTimingSample(time: $0.time, intervalMs: $0.interval) }
            } else {
                let step = Double(allFrames.count) / Double(maxSamples)
                samples.reserveCapacity(maxSamples)
                
                for i in 0..<maxSamples {
                    let index = Int(Double(i) * step)
                    if index < allFrames.count {
                        let frame = allFrames[index]
                        samples.append(FrameTimingSample(time: frame.time, intervalMs: frame.interval))
                    }
                }
            }
            
            continuation.yield(samples)
            continuation.finish()
        }
        
        continuation.onTermination = { _ in task.cancel() }
    }
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
    
    var intervals: [Double] = []
    intervals.reserveCapacity(10000)
    var previousPTS: Double?
    var frameCount = 0
    var hasGaps = false
    
    while let sampleBuffer = output.copyNextSampleBuffer() {
        if Task.isCancelled { break }
        
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
