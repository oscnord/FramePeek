import AVFoundation
import CoreMedia

// MARK: - Reader-based extraction (accurate sample sizes)

func extractWithReader(
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
    // Reserve capacity based on estimated frame count for better performance
    let estimatedFrameCount = Int(durationSeconds * estimatedFPS)
    var allSamples: [(pts: Double, size: Int64)] = []
    allSamples.reserveCapacity(min(estimatedFrameCount, 1_000_000)) // Cap at 1M to avoid excessive memory

    var readCount = 0
    var lastReadPTS: Double = 0
    let batchSize = 1000  // Process frames in batches for better performance
    
    while !Task.isCancelled {
        autoreleasepool {
            var batchCount = 0
            
            while batchCount < batchSize && !Task.isCancelled {
                guard let sb = output.copyNextSampleBuffer() else {
                    // Check if reader completed successfully or if there was an error
                    if reader.status == .failed {
                        // Reader failed - error details available in reader.error if needed
                    } else if reader.status != .completed {
                        // Reader didn't complete - may have stopped early
                    }
                    break
                }
                
                let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                let size = CMSampleBufferGetTotalSampleSize(sb)
                guard size > 0, pts.isFinite else { continue }
                allSamples.append((pts: pts, size: Int64(size)))
                readCount += 1
                batchCount += 1
                lastReadPTS = max(lastReadPTS, pts) // Track the latest PTS we've read
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
    
    // Sort by PTS to ensure chronological order
    allSamples.sort { $0.pts < $1.pts }

    guard let firstPTS = allSamples.first?.pts else {
        continuation.yield(makeFinalUpdate(rawFrames: []))
        continuation.finish()
        return
    }

    // Use fixed 1-second buckets aligned with aggregation
    let bucketSize: Double = 1.0
    let startTime = firstPTS
    let endTime = allSamples.last!.pts
    let totalDuration = endTime - startTime + defaultFrameDuration
    let numBuckets = Int(ceil(totalDuration / bucketSize))
    
    var frameIndex = 0
    var bucketIndex = 0
    var previousPTS: Double? = nil
    var lastEmittedBucket = -1

    for (pts, size) in allSamples {
        if Task.isCancelled { break }
        
        // FPS stats
        if let prev = previousPTS, pts > prev {
            let dt = pts - prev
            sumInterval += dt
            intervalCount += 1
            if dt < minInterval { minInterval = dt }
            if dt > maxInterval { maxInterval = dt }
        }
        previousPTS = pts

        // Determine which bucket this frame belongs to
        let currentBucket = Int(floor((pts - startTime) / bucketSize))
        
        // Emit completed buckets we haven't emitted yet
        while bucketIndex <= currentBucket && bucketIndex < numBuckets && bucketIndex > lastEmittedBucket {
            let bucketStart = startTime + Double(bucketIndex) * bucketSize
            let bucketEnd = bucketStart + bucketSize
            
            // Advance to first frame in this bucket
            while frameIndex < allSamples.count && allSamples[frameIndex].pts < bucketStart {
                frameIndex += 1
            }
            
            // Sum frames in bucket [bucketStart, bucketEnd)
            var totalBytes: Int64 = 0
            var tempIndex = frameIndex
            var firstFramePTS: Double? = nil
            var lastFramePTS: Double? = nil
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
    
    // Emit any remaining buckets
    while bucketIndex < numBuckets {
        let bucketStart = startTime + Double(bucketIndex) * bucketSize
        let bucketEnd = bucketStart + bucketSize
        
        while frameIndex < allSamples.count && allSamples[frameIndex].pts < bucketStart {
            frameIndex += 1
        }
        
        var totalBytes: Int64 = 0
        var tempIndex = frameIndex
        var firstFramePTS: Double? = nil
        var lastFramePTS: Double? = nil
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

    // Convert allSamples to RawFrame format and include in final update
    let rawFrames = allSamples.map { (pts: $0.pts, size: $0.size) }
    continuation.yield(makeFinalUpdate(rawFrames: rawFrames))
    continuation.finish()
}
