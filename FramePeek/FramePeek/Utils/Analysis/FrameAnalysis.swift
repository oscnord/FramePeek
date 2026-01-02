import Foundation
import AVFoundation

// MARK: - Frame Rate Statistics

/// Calculates frame rate statistics from an array of frame timestamps
/// - Parameter times: Array of frame presentation times in seconds
/// - Returns: Tuple containing average FPS, min interval, and max interval, or nil if insufficient data
func frameRateStats(from times: [Double]) -> (averageFPS: Double, minInterval: Double, maxInterval: Double)? {
    guard times.count > 1 else { return nil }
    
    var intervals: [Double] = []
    intervals.reserveCapacity(times.count - 1)
    
    for i in 1..<times.count {
        let interval = times[i] - times[i - 1]
        if interval > 0 {
            intervals.append(interval)
        }
    }
    
    guard !intervals.isEmpty else { return nil }
    
    let totalDuration = intervals.reduce(0, +)
    let averageInterval = totalDuration / Double(intervals.count)
    let averageFPS = averageInterval > 0 ? 1.0 / averageInterval : 0
    let minInterval = intervals.min() ?? 0
    let maxInterval = intervals.max() ?? 0
    
    return (averageFPS, minInterval, maxInterval)
}

// MARK: - Progressive Frame Extraction

/// Starts progressive frame extraction with periodic updates
/// - Parameters:
///   - asset: AVAsset to analyze
///   - maxSamples: Maximum number of samples to collect
///   - emitEveryNSamples: How often to emit updates
///   - onUpdate: Callback for each update batch
/// - Returns: Cancellable Task
func startFrameExtractionProgressive(
    asset: AVAsset,
    maxSamples: Int = 2000,
    emitEveryNSamples: Int = 50,
    onUpdate: @escaping (FrameAnalysisUpdate) -> Void
) -> Task<Void, Never> {
    let options = FrameSamplingOptions(
        minEmitIntervalSeconds: nil,
        maxSamples: maxSamples,
        emitEveryNSamples: emitEveryNSamples,
        preferAccuracy: false,
        visualizationMode: .second
    )

    return Task.detached(priority: .userInitiated) {
        for await update in extractFramesStream(asset: asset, options: options) {
            if Task.isCancelled { return }
            await MainActor.run { onUpdate(update) }
            if update.isFinished { break }
        }
    }
}

// MARK: - Batch Frame Extraction

/// Extracts frames and returns all samples at once via completion handler
/// - Parameters:
///   - asset: AVAsset to analyze
///   - maxSamples: Maximum number of samples to collect
///   - completion: Callback with final analysis result
func extractFrames(
    asset: AVAsset,
    maxSamples: Int = 2000,
    completion: @escaping (FrameAnalysisResult) -> Void
) {
    let options = FrameSamplingOptions(
        minEmitIntervalSeconds: nil,
        maxSamples: maxSamples,
        emitEveryNSamples: 200,
        preferAccuracy: false,
        visualizationMode: .second
    )

    Task.detached(priority: .userInitiated) {
        var all: [BitrateSample] = []
        all.reserveCapacity(maxSamples)

        var avgFPS: Double?
        var minInt: Double?
        var maxInt: Double?

        for await update in extractFramesStream(asset: asset, options: options) {
            if Task.isCancelled { return }
            all.append(contentsOf: update.appendedSamples)
            avgFPS = update.averageFPS
            minInt = update.minInterval
            maxInt = update.maxInterval
            if update.isFinished { break }
        }

        let result = FrameAnalysisResult(
            samples: all,
            averageFPS: avgFPS,
            minInterval: minInt,
            maxInterval: maxInt
        )

        await MainActor.run {
            completion(result)
        }
    }
}
