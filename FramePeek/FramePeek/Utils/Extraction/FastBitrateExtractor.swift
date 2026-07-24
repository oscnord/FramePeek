import AVFoundation
import CoreMedia

/// Extracts bitrate samples efficiently using AVSampleCursor when possible,
/// falling back to AVAssetReader.
/// Routes to format-specific extractors based on detected container format.
public func extractBitratesFast(
    asset: AVAsset,
    options: FrameSamplingOptions
) -> AsyncStream<FrameAnalysisUpdate> {

    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

            guard let videoTrack = await AVAssetLoader.firstTrack(of: asset, mediaType: .video) else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            let durationSeconds = await AVAssetLoader.durationSeconds(of: asset)
            let nominalFrameRate = await AVAssetLoader.nominalFrameRate(of: videoTrack)

            guard durationSeconds > 0 else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            let url: URL? = (asset as? AVURLAsset)?.url

            let format = await detectContainerFormat(asset: asset, url: url ?? URL(fileURLWithPath: "/"))

            switch format {
            case .fragmentedMP4, .cmaf:
                await extractFragmentedMP4(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
                return

            case .mpegTS:
                await extractTS(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
                return

            default:
                if options.preferAccuracy {
                    await extractWithReader(
                        asset: asset,
                        videoTrack: videoTrack,
                        durationSeconds: durationSeconds,
                        nominalFrameRate: Double(nominalFrameRate),
                        options: options,
                        continuation: continuation
                    )
                } else {
                    let formatDescriptions = await AVAssetLoader.formatDescriptions(of: videoTrack)
                    if !formatDescriptions.isEmpty {

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
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

@inline(__always)
func appendBitrateSampleRespectingLimit(
    _ sample: BitrateSample,
    to pending: inout [BitrateSample],
    totalEmitted: inout Int,
    maxSamples: Int
) -> Bool {
    guard totalEmitted < maxSamples else { return false }
    pending.append(sample)
    totalEmitted += 1
    return true
}

// MARK: - Shared collect/bucket/emit pipeline (reader, TS, and fMP4 extractors)

struct BucketEmissionConfig {
    let estimatedFPS: Double
    let options: FrameSamplingOptions
    /// Excludes segment-boundary PTS gaps from FPS statistics (fragmented MP4)
    var maxFPSStatInterval: Double? = nil
    /// Adjusts a bucket's bitrate, e.g. TS packet overhead subtraction
    var adjustBitrate: ((_ bitrate: Double, _ totalBytes: Int64, _ duration: Double) -> Double)? = nil
}

/// Drains an AVAssetReader video output into (pts, size) tuples, sorted by PTS
func collectVideoSamples(
    reader: AVAssetReader,
    output: AVAssetReaderTrackOutput,
    estimatedCount: Int
) async -> [(pts: Double, size: Int64)] {
    var allSamples: [(pts: Double, size: Int64)] = []
    allSamples.reserveCapacity(min(max(estimatedCount, 0), 1_000_000))

    var readCount = 0
    let batchSize = 1000

    while !Task.isCancelled {
        autoreleasepool {
            var batchCount = 0
            while batchCount < batchSize && !Task.isCancelled {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                let size = CMSampleBufferGetTotalSampleSize(sampleBuffer)
                guard size > 0, pts.isFinite else { continue }
                allSamples.append((pts: pts, size: Int64(size)))
                readCount += 1
                batchCount += 1
            }
        }

        if readCount % 500 == 0 {
            await Task.yield()
        }
        if reader.status != .reading {
            break
        }
    }

    if reader.status == .reading {
        reader.cancelReading()
    }

    allSamples.sort { $0.pts < $1.pts }
    return allSamples
}

/// Aggregates sorted (pts, size) samples into 1-second buckets and emits
/// progressive updates followed by a final update carrying the raw frames.
/// Per-bucket duration uses the actual frame span with a floor of 10% of the
/// bucket to avoid inflated bitrates from sparse buckets.
func emitBucketedBitrates(
    allSamples: [(pts: Double, size: Int64)],
    config: BucketEmissionConfig,
    continuation: AsyncStream<FrameAnalysisUpdate>.Continuation
) {
    let estimatedFPS = config.estimatedFPS
    let defaultFrameDuration = 1.0 / estimatedFPS
    let options = config.options

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)
    var totalEmitted = 0

    var sumInterval = 0.0
    var intervalCount = 0
    var minInterval = Double.greatestFiniteMagnitude
    var maxInterval = 0.0

    func makeUpdate(isFinished: Bool = false, rawFrames: [RawFrame] = []) -> FrameAnalysisUpdate {
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
            rawFrames: rawFrames,
            averageFPS: avgFPS,
            minInterval: minInt,
            maxInterval: maxInt,
            isFinished: isFinished
        )
    }

    guard let firstPTS = allSamples.first?.pts, let lastPTS = allSamples.last?.pts else {
        continuation.yield(makeUpdate(isFinished: true))
        continuation.finish()
        return
    }

    // FPS statistics over consecutive PTS deltas
    let maxStatInterval = config.maxFPSStatInterval ?? .greatestFiniteMagnitude
    var previousPTS: Double?
    for (pts, _) in allSamples {
        if let prev = previousPTS, pts > prev {
            let dt = pts - prev
            if dt <= maxStatInterval {
                sumInterval += dt
                intervalCount += 1
                if dt < minInterval { minInterval = dt }
                if dt > maxInterval { maxInterval = dt }
            }
        }
        previousPTS = pts
    }

    let bucketSize: Double = 1.0
    let totalDuration = lastPTS - firstPTS + defaultFrameDuration
    let numBuckets = Int(ceil(totalDuration / bucketSize))

    var frameIndex = 0
    var bucketIndex = 0

    while bucketIndex < numBuckets {
        if Task.isCancelled { break }

        let bucketStart = firstPTS + Double(bucketIndex) * bucketSize
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
            let minDuration = bucketSize * 0.1
            let actualDuration: Double
            if let first = firstFramePTS, let last = lastFramePTS {
                let actualSpan = last - first
                actualDuration = actualSpan < bucketSize - defaultFrameDuration
                    ? max(actualSpan + defaultFrameDuration, minDuration)
                    : bucketSize
            } else {
                actualDuration = bucketSize
            }

            var bitrate = (Double(totalBytes) * 8.0) / actualDuration
            if let adjust = config.adjustBitrate {
                bitrate = adjust(bitrate, totalBytes, actualDuration)
            }

            let sample = BitrateSample(
                time: bucketStart + bucketSize / 2.0,
                bitrate: bitrate,
                duration: actualDuration
            )
            if !appendBitrateSampleRespectingLimit(
                sample,
                to: &pending,
                totalEmitted: &totalEmitted,
                maxSamples: options.maxSamples
            ) {
                break
            }

            if pending.count >= options.emitEveryNSamples {
                continuation.yield(makeUpdate())
                pending.removeAll(keepingCapacity: true)
            }
        }

        bucketIndex += 1
    }

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
        pending.removeAll(keepingCapacity: true)
    }

    let rawFrames = allSamples.map { (pts: $0.pts, size: $0.size) }
    continuation.yield(makeUpdate(isFinished: true, rawFrames: rawFrames))
    continuation.finish()
}
