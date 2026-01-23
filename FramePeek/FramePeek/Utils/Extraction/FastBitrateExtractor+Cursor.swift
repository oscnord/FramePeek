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

    let estimatedFPS = nominalFrameRate > 0 ? nominalFrameRate : 30.0
    let defaultFrameDuration = 1.0 / estimatedFPS

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)

    // FPS stats
    var sumInterval = 0.0
    var intervalCount = 0
    var minInterval = Double.greatestFiniteMagnitude
    var maxInterval = 0.0
    var previousPTS: Double?

    var firstPTS: Double?

    var allRawFrames: [RawFrame] = []
    allRawFrames.reserveCapacity(Int(estimatedFPS * durationSeconds) + 1000)

    let bucketSize: Double = 1.0
    var bucketFrames: [Int: [(pts: Double, size: Int64)]] = [:]
    var lastEmittedBucket = -1

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

            if let prev = previousPTS, pts > prev {
                let dt = pts - prev
                sumInterval += dt
                intervalCount += 1
                if dt < minInterval { minInterval = dt }
                if dt > maxInterval { maxInterval = dt }
            }
            previousPTS = pts

            guard let startPTS = firstPTS else {
                let steps = cursor.stepInPresentationOrder(byCount: 1)
                hasMoreSamples = (steps == 1)
                sampleCount += 1
                if sampleCount % 1000 == 0 {
                    await Task.yield()
                }
                continue
            }

            let bucketIndex = Int(floor((pts - startPTS) / bucketSize))

            if bucketFrames[bucketIndex] == nil {
                bucketFrames[bucketIndex] = []
            }
            bucketFrames[bucketIndex]?.append((pts: pts, size: sampleSize))

            let prevBucketIndex = bucketIndex - 1
            if prevBucketIndex > lastEmittedBucket {
                if let frames = bucketFrames[prevBucketIndex], !frames.isEmpty {
                    let bucketStart = startPTS + Double(prevBucketIndex) * bucketSize
                    let totalBytes = frames.reduce(0) { $0 + $1.size }

                    let firstFramePTS = frames.first!.pts
                    let lastFramePTS = frames.last!.pts
                    let actualSpan = lastFramePTS - firstFramePTS
                    // Add minimum duration guard to prevent inflated bitrate from very small durations
                    let minDuration = bucketSize * 0.1
                    let actualDuration: Double
                    if actualSpan < bucketSize - defaultFrameDuration {
                        actualDuration = max(actualSpan + defaultFrameDuration, minDuration)
                    } else {
                        actualDuration = bucketSize
                    }

                    let bitrate = (Double(totalBytes) * 8.0) / actualDuration
                    let sampleTime = bucketStart + bucketSize / 2.0

                    pending.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: actualDuration))
                    lastEmittedBucket = prevBucketIndex

                    // Remove emitted bucket to prevent unbounded memory growth
                    bucketFrames.removeValue(forKey: prevBucketIndex)

                    if pending.count >= options.emitEveryNSamples {
                        continuation.yield(makeUpdate())
                        pending.removeAll(keepingCapacity: true)
                    }
                }
            }
        }

        let steps = cursor.stepInPresentationOrder(byCount: 1)
        hasMoreSamples = (steps == 1)
        sampleCount += 1

        if sampleCount % 1000 == 0 {
            await Task.yield()
        }

        // Note: We continue reading even after hitting maxSamples to collect all raw frames
        // for re-aggregation. The maxSamples limit only affects emitted samples, not raw frame collection.
    }

    guard let startPTS = firstPTS else {
        continuation.yield(makeFinalUpdate())
        continuation.finish()
        return true
    }

    let endTime = allRawFrames.map(\.pts).max() ?? startPTS
    let totalDuration = endTime - startPTS + defaultFrameDuration
    let numBuckets = Int(ceil(totalDuration / bucketSize))

    for bucketIndex in (lastEmittedBucket + 1)..<numBuckets {
        let bucketStart = startPTS + Double(bucketIndex) * bucketSize

        let frames = bucketFrames[bucketIndex] ?? []
        let totalBytes = frames.reduce(0) { $0 + $1.size }

        if totalBytes > 0 && !frames.isEmpty {
            let firstFramePTS = frames.first!.pts
            let lastFramePTS = frames.last!.pts
            let actualSpan = lastFramePTS - firstFramePTS
            // Add minimum duration guard to prevent inflated bitrate from very small durations
            let minDuration = bucketSize * 0.1
            let actualDuration: Double
            if actualSpan < bucketSize - defaultFrameDuration {
                actualDuration = max(actualSpan + defaultFrameDuration, minDuration)
            } else {
                actualDuration = bucketSize
            }

            let bitrate = (Double(totalBytes) * 8.0) / actualDuration
            let sampleTime = bucketStart + bucketSize / 2.0

            pending.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: actualDuration))

            if pending.count >= options.emitEveryNSamples {
                continuation.yield(makeUpdate())
                pending.removeAll(keepingCapacity: true)
            }
        }
    }

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
    }

    continuation.yield(makeFinalUpdate())
    continuation.finish()
    return true
}
