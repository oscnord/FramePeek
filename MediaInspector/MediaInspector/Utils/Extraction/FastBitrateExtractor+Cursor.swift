//
//  FastBitrateExtractor+Cursor.swift
//  MediaInspector
//
//  Cursor-based extraction (fast, metadata-only)
//

import AVFoundation
import CoreMedia

// MARK: - Cursor-based extraction (fast, metadata-only)

func extractWithCursor(
    track: AVAssetTrack,
    durationSeconds: Double,
    nominalFrameRate: Double,
    options: FrameSamplingOptions,
    continuation: AsyncStream<FrameAnalysisUpdate>.Continuation
) async -> Bool {

    guard let cursor = track.makeSampleCursor(presentationTimeStamp: .zero) else {
        return false
    }

    let emitInterval = options.minEmitIntervalSeconds ?? 0
    let windowSize: Double = 1.0  // 1-second window
    let estimatedFPS = nominalFrameRate > 0 ? nominalFrameRate : 30.0
    let defaultFrameDuration = 1.0 / estimatedFPS

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)

    var totalEmitted = 0

    // FPS stats
    var sumInterval = 0.0
    var intervalCount = 0
    var minInterval = Double.greatestFiniteMagnitude
    var maxInterval = 0.0
    var previousPTS: Double? = nil

    // Rolling window: store (PTS, size) pairs
    var window: [(pts: Double, size: Int64)] = []
    window.reserveCapacity(Int(estimatedFPS * windowSize) + 10)

    var nextEmitPTS: Double? = nil
    var firstPTS: Double? = nil  // Track the first PTS to know when window is full

    // Store all raw frames for re-aggregation
    var allRawFrames: [RawFrame] = []
    allRawFrames.reserveCapacity(Int(estimatedFPS * durationSeconds) + 1000)

    func makeUpdate(isFinished: Bool = false) -> FrameAnalysisUpdate {
        let avgFPS: Double?
        let minInt: Double?
        let maxInt: Double?

        if intervalCount > 0 {
            let avgInterval = sumInterval / Double(intervalCount)
            avgFPS = avgInterval > 0 ? 1.0 / avgInterval : estimatedFPS
            minInt = minInterval.isFinite ? minInterval : nil
            maxInt = maxInterval > 0 ? maxInterval : nil
        } else {
            avgFPS = estimatedFPS
            minInt = defaultFrameDuration
            maxInt = defaultFrameDuration
        }

        return FrameAnalysisUpdate(
            appendedSamples: pending,
            rawFrames: [],
            averageFPS: avgFPS,
            minInterval: minInt,
            maxInterval: maxInt,
            isFinished: isFinished
        )
    }
    
    func makeFinalUpdate() -> FrameAnalysisUpdate {
        var update = makeUpdate(isFinished: true)
        update.rawFrames = allRawFrames
        return update
    }

    var hasMoreSamples = true
    var sampleCount = 0

    while hasMoreSamples && !Task.isCancelled {
        let pts = cursor.presentationTimeStamp.seconds
        if !pts.isFinite {
            let steps = cursor.stepInPresentationOrder(byCount: 1)
            hasMoreSamples = (steps == 1)
            continue
        }

        let sampleSize = Int64(cursor.currentSampleStorageRange.length)
        
        if sampleSize > 0 {
            // Store raw frame data
            allRawFrames.append((pts: pts, size: sampleSize))
            
            // Track first PTS
            if firstPTS == nil {
                firstPTS = pts
            }
            
            // FPS stats
            if let prev = previousPTS, pts > prev {
                let dt = pts - prev
                sumInterval += dt
                intervalCount += 1
                if dt < minInterval { minInterval = dt }
                if dt > maxInterval { maxInterval = dt }
            }
            previousPTS = pts

            // Add current sample to window
            window.append((pts: pts, size: sampleSize))

            // Remove samples outside the 1-second window
            let cutoffTime = pts - windowSize
            window.removeAll { $0.pts < cutoffTime }

            // Initialize emit schedule
            if nextEmitPTS == nil {
                nextEmitPTS = pts
            }

            // Decide whether to emit
            let shouldEmit: Bool
            if emitInterval > 0, let next = nextEmitPTS {
                shouldEmit = pts >= next
            } else {
                shouldEmit = true
            }

            if shouldEmit && totalEmitted < options.maxSamples && !window.isEmpty {
                let totalBytes = window.reduce(0) { $0 + $1.size }
                
                // Calculate proper duration for bitrate
                // Once we have at least 1 second of data, use exactly 1.0 second
                // For partial windows at the start, use actual span + last frame duration
                let oldestPTS = window.first!.pts
                let newestPTS = window.last!.pts
                let actualSpan = newestPTS - oldestPTS
                
                let duration: Double
                if actualSpan >= windowSize - defaultFrameDuration {
                    // Window is essentially full - use the window size for accurate bitrate
                    duration = windowSize
                } else {
                    // Partial window - add frame duration to span for more accurate calculation
                    duration = actualSpan + defaultFrameDuration
                }
                
                guard duration > 0 && duration.isFinite else {
                    let steps = cursor.stepInPresentationOrder(byCount: 1)
                    hasMoreSamples = (steps == 1)
                    sampleCount += 1
                    if sampleCount % 1000 == 0 {
                        await Task.yield()
                    }
                    continue
                }

                // Apply standard bitrate formula: bits = bytes * 8, then divide by duration
                let bitrate = (Double(totalBytes) * 8.0) / duration
                pending.append(BitrateSample(time: pts, bitrate: bitrate, duration: duration))
                totalEmitted += 1

                if emitInterval > 0 {
                    nextEmitPTS = (nextEmitPTS ?? pts) + emitInterval
                }

                if pending.count >= options.emitEveryNSamples {
                    continuation.yield(makeUpdate())
                    pending.removeAll(keepingCapacity: true)
                }
            }
        }

        let steps = cursor.stepInPresentationOrder(byCount: 1)
        hasMoreSamples = (steps == 1)
        sampleCount += 1

        if sampleCount % 1000 == 0 {
            await Task.yield()
        }

        if totalEmitted >= options.maxSamples {
            break
        }
    }

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
    }

    continuation.yield(makeFinalUpdate())
    continuation.finish()
    return true
}
