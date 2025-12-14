//
//  FastBitrateExtractor.swift
//  MediaInspector
//
//  Efficient bitrate extraction using a rolling time-window over sample sizes.
//  Calculates bitrate using the standard formula: bitrate = (bytes * 8) / duration
//

import AVFoundation
import CoreMedia

/// Extracts bitrate samples efficiently using AVSampleCursor when possible,
/// falling back to AVAssetReader.
func extractBitratesFast(
    asset: AVAsset,
    options: FrameSamplingOptions
) -> AsyncStream<FrameAnalysisUpdate> {

    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

            // Load video track
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Get duration and frame rate
            let duration = (try? await asset.load(.duration)) ?? .zero
            let durationSeconds = duration.seconds
            let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0

            guard durationSeconds.isFinite, durationSeconds > 0 else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Choose extraction method based on preferAccuracy option
            if options.preferAccuracy {
                // Skip cursor path and go directly to reader for accuracy
                await extractWithReader(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
            } else {
                // Try cursor first (fast, metadata-only). Fall back to reader if unavailable.
                if let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
                   !formatDescriptions.isEmpty {

                    let success = await extractWithCursor(
                        track: videoTrack,
                        durationSeconds: durationSeconds,
                        nominalFrameRate: Double(nominalFrameRate),
                        options: options,
                        continuation: continuation
                    )

                    if success { return }
                }

                await extractWithReader(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Cursor-based extraction (fast, metadata-only)

private func extractWithCursor(
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

// MARK: - Reader-based extraction (accurate sample sizes)

private func extractWithReader(
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

    // Collect all samples first (they may be out of order)
    var allSamples: [(pts: Double, size: Int64)] = []
    allSamples.reserveCapacity(8192)

    var readCount = 0
    while !Task.isCancelled, let sb = output.copyNextSampleBuffer() {
        autoreleasepool {
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            let size = CMSampleBufferGetTotalSampleSize(sb)
            guard size > 0, pts.isFinite else { return }
            allSamples.append((pts: pts, size: Int64(size)))
            readCount += 1
        }

        if readCount % 500 == 0 {
            await Task.yield()
        }
    }

    // Sort by PTS to ensure chronological order
    allSamples.sort { $0.pts < $1.pts }

    // Rolling window state
    var window: [(pts: Double, size: Int64)] = []
    window.reserveCapacity(Int(estimatedFPS * windowSize) + 10)

    var previousPTS: Double? = nil
    var nextEmitPTS: Double? = nil
    var firstPTS: Double? = nil

    for (pts, size) in allSamples {
        if Task.isCancelled || totalEmitted >= options.maxSamples { break }

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

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
    }

    // Convert allSamples to RawFrame format and include in final update
    let rawFrames = allSamples.map { (pts: $0.pts, size: $0.size) }
    continuation.yield(makeFinalUpdate(rawFrames: rawFrames))
    continuation.finish()
}
