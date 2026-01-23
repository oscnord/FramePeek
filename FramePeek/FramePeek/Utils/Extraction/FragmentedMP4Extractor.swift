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

    let estimatedFPS = nominalFrameRate > 0 ? nominalFrameRate : 30.0
    let defaultFrameDuration = 1.0 / estimatedFPS
    let maxPTSGap = defaultFrameDuration * 2.0  // Threshold for detecting discontinuities

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)

    var totalEmitted = 0

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

    let estimatedFrameCount = Int(durationSeconds * estimatedFPS)
    var allSamples: [(pts: Double, size: Int64)] = []
    allSamples.reserveCapacity(min(estimatedFrameCount, 1_000_000))

    var readCount = 0
    var lastReadPTS: Double = 0
    let batchSize = 1000  // Process frames in batches for better performance

    while !Task.isCancelled {
        autoreleasepool {
            var batchCount = 0

            while batchCount < batchSize && !Task.isCancelled {
                guard let sb = output.copyNextSampleBuffer() else {
                    break
                }

                let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                let size = CMSampleBufferGetTotalSampleSize(sb)
                guard size > 0, pts.isFinite else { continue }
                allSamples.append((pts: pts, size: Int64(size)))
                readCount += 1
                batchCount += 1
                lastReadPTS = max(lastReadPTS, pts)
            }
        }

        if readCount % 500 == 0 {
            await Task.yield()
        }

        // Break if no more samples available
        if reader.status != .reading {
            break
        }
    }

    allSamples.sort { $0.pts < $1.pts }

    guard let firstPTS = allSamples.first?.pts else {
        continuation.yield(makeFinalUpdate(rawFrames: []))
        continuation.finish()
        return
    }

    var previousPTS: Double?
    for (pts, _) in allSamples {
        if let prev = previousPTS, pts > prev {
            let dt = pts - prev
            if dt <= maxPTSGap {
                sumInterval += dt
                intervalCount += 1
                if dt < minInterval { minInterval = dt }
                if dt > maxInterval { maxInterval = dt }
            }
        }
        previousPTS = pts
    }

    let bucketSize: Double = 1.0
    let startTime = firstPTS
    let endTime = allSamples.last!.pts
    let totalDuration = endTime - startTime + defaultFrameDuration
    let numBuckets = Int(ceil(totalDuration / bucketSize))

    var frameIndex = 0
    var bucketIndex = 0
    var lastEmittedBucket = -1

    for (pts, _) in allSamples {
        if Task.isCancelled { break }

        let currentBucket = Int(floor((pts - startTime) / bucketSize))

        while bucketIndex <= currentBucket && bucketIndex < numBuckets && bucketIndex > lastEmittedBucket {
            let bucketStart = startTime + Double(bucketIndex) * bucketSize
            let bucketEnd = bucketStart + bucketSize

            while frameIndex < allSamples.count && allSamples[frameIndex].pts < bucketStart {
                frameIndex += 1
            }

            var totalBytes: Int64 = 0
            var tempIndex = frameIndex
            var firstFramePTS: Double?
            var lastFramePTS: Double?
            while tempIndex < allSamples.count && allSamples[tempIndex].pts < bucketEnd {
                if firstFramePTS == nil {
                    firstFramePTS = allSamples[tempIndex].pts
                }
                lastFramePTS = allSamples[tempIndex].pts
                totalBytes += allSamples[tempIndex].size
                tempIndex += 1
            }

            if totalBytes > 0 {
                let actualDuration: Double
                if let first = firstFramePTS, let last = lastFramePTS {
                    let actualSpan = last - first
                    if actualSpan < bucketSize - defaultFrameDuration {
                        actualDuration = actualSpan + defaultFrameDuration
                    } else {
                        actualDuration = bucketSize
                    }
                } else {
                    actualDuration = bucketSize
                }

                let bitrate = (Double(totalBytes) * 8.0) / actualDuration
                let sampleTime = bucketStart + bucketSize / 2.0

                pending.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: actualDuration))
                totalEmitted += 1
                lastEmittedBucket = bucketIndex

                if pending.count >= options.emitEveryNSamples {
                    continuation.yield(makeUpdate())
                    pending.removeAll(keepingCapacity: true)
                }
            }

            bucketIndex += 1
        }
    }

    while bucketIndex < numBuckets {
        let bucketStart = startTime + Double(bucketIndex) * bucketSize
        let bucketEnd = bucketStart + bucketSize

        while frameIndex < allSamples.count && allSamples[frameIndex].pts < bucketStart {
            frameIndex += 1
        }

        var totalBytes: Int64 = 0
        var tempIndex = frameIndex
        var firstFramePTS: Double?
        var lastFramePTS: Double?
        while tempIndex < allSamples.count && allSamples[tempIndex].pts < bucketEnd {
            if firstFramePTS == nil {
                firstFramePTS = allSamples[tempIndex].pts
            }
            lastFramePTS = allSamples[tempIndex].pts
            totalBytes += allSamples[tempIndex].size
            tempIndex += 1
        }

        if totalBytes > 0 {
            let actualDuration: Double
            if let first = firstFramePTS, let last = lastFramePTS {
                let actualSpan = last - first
                if actualSpan < bucketSize - defaultFrameDuration {
                    actualDuration = actualSpan + defaultFrameDuration
                } else {
                    actualDuration = bucketSize
                }
            } else {
                actualDuration = bucketSize
            }

            let bitrate = (Double(totalBytes) * 8.0) / actualDuration
            let sampleTime = bucketStart + bucketSize / 2.0

            pending.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: actualDuration))
            totalEmitted += 1

            if pending.count >= options.emitEveryNSamples {
                continuation.yield(makeUpdate())
                pending.removeAll(keepingCapacity: true)
            }
        }

        bucketIndex += 1
    }

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
    }

    let rawFrames = allSamples.map { (pts: $0.pts, size: $0.size) }
    continuation.yield(makeFinalUpdate(rawFrames: rawFrames))
    continuation.finish()
}
