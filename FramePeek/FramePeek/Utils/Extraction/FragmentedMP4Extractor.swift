//
//  FragmentedMP4Extractor.swift
//  FramePeek
//
//  Fragment-aware bitrate extraction for fragmented MP4 and CMAF files
//

import AVFoundation
import CoreMedia

/// Extracts bitrate from fragmented MP4/CMAF files with fragment-aware handling
func extractFragmentedMP4(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    durationSeconds: Double,
    nominalFrameRate: Double,
    options: FrameSamplingOptions,
    continuation: AsyncStream<FrameAnalysisUpdate>.Continuation
) async {
    let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

    guard let reader = try? AVAssetReader(asset: asset) else {
        continuation.yield(finish)
        continuation.finish()
        return
    }

    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    output.alwaysCopiesSampleData = false

    guard reader.canAdd(output) else {
        continuation.yield(finish)
        continuation.finish()
        return
    }
    reader.add(output)

    guard reader.startReading() else {
        continuation.yield(finish)
        continuation.finish()
        return
    }

    let emitInterval = options.minEmitIntervalSeconds ?? 0
    let windowSize: Double = 1.0  // 1-second window
    let estimatedFPS = nominalFrameRate > 0 ? nominalFrameRate : 30.0
    let defaultFrameDuration = 1.0 / estimatedFPS
    let maxPTSGap = defaultFrameDuration * 2.0  // Threshold for detecting discontinuities

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)

    var totalEmitted = 0

    // FPS stats
    var sumInterval = 0.0
    var intervalCount = 0
    var minInterval = Double.greatestFiniteMagnitude
    var maxInterval = 0.0

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
    
    func makeFinalUpdate(rawFrames: [RawFrame]) -> FrameAnalysisUpdate {
        var update = makeUpdate(isFinished: true)
        update.rawFrames = rawFrames
        return update
    }

    // Collect all samples first (fragmented files may have out-of-order samples)
    let estimatedFrameCount = Int(durationSeconds * estimatedFPS)
    var allSamples: [(pts: Double, size: Int64)] = []
    allSamples.reserveCapacity(min(estimatedFrameCount, 1_000_000))

    var readCount = 0
    var lastReadPTS: Double = 0
    while !Task.isCancelled {
        guard let sb = output.copyNextSampleBuffer() else {
            break
        }
        
        autoreleasepool {
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            let size = CMSampleBufferGetTotalSampleSize(sb)
            guard size > 0, pts.isFinite else { return }
            allSamples.append((pts: pts, size: Int64(size)))
            readCount += 1
            lastReadPTS = max(lastReadPTS, pts)
        }

        if readCount % 500 == 0 {
            await Task.yield()
        }
    }
    
    // Sort by PTS to ensure chronological order (critical for fragmented files)
    allSamples.sort { $0.pts < $1.pts }

    // Detect PTS discontinuities (fragment boundaries)
    var discontinuities: [Double] = []
    var previousPTS: Double? = nil
    for (pts, _) in allSamples {
        if let prev = previousPTS {
            let gap = pts - prev
            if gap > maxPTSGap {
                // Potential fragment boundary
                discontinuities.append(prev)
            }
        }
        previousPTS = pts
    }

    // Rolling window state
    var window: [(pts: Double, size: Int64)] = []
    window.reserveCapacity(Int(estimatedFPS * windowSize) + 10)

    previousPTS = nil
    var nextEmitPTS: Double? = nil

    for (pts, size) in allSamples {
        if Task.isCancelled || totalEmitted >= options.maxSamples { break }
        
        // FPS stats (skip gaps at boundaries)
        if let prev = previousPTS, pts > prev {
            let dt = pts - prev
            if dt <= maxPTSGap {  // Only count normal intervals
                sumInterval += dt
                intervalCount += 1
                if dt < minInterval { minInterval = dt }
                if dt > maxInterval { maxInterval = dt }
            }
        }
        previousPTS = pts

        // Add current sample to window
        window.append((pts: pts, size: size))

        // Remove samples outside the 1-second window
        let cutoffTime = pts - windowSize
        window.removeAll { $0.pts < cutoffTime }

        // Initialize emit schedule
        if nextEmitPTS == nil {
            nextEmitPTS = pts
        }

        let shouldEmit: Bool
        if emitInterval > 0, let next = nextEmitPTS {
            shouldEmit = pts >= next
        } else {
            shouldEmit = true
        }

        if shouldEmit && totalEmitted < options.maxSamples && !window.isEmpty {
            let totalBytes = window.reduce(0) { $0 + $1.size }
            
            // Calculate proper duration for bitrate
            let oldestPTS = window.first!.pts
            let newestPTS = window.last!.pts
            let actualSpan = newestPTS - oldestPTS
            
            let duration: Double
            if actualSpan >= windowSize - defaultFrameDuration {
                duration = windowSize
            } else {
                duration = actualSpan + defaultFrameDuration
            }
            
            guard duration > 0 && duration.isFinite else {
                continue
            }

            // Calculate bitrate (always use accurate, unsmoothed values)
            // Smoothing should be applied during visualization/aggregation, not during extraction
            // This preserves accurate peak bitrate measurements
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

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
    }

    // Convert allSamples to RawFrame format and include in final update
    let rawFrames = allSamples.map { (pts: $0.pts, size: $0.size) }
    continuation.yield(makeFinalUpdate(rawFrames: rawFrames))
    continuation.finish()
}

