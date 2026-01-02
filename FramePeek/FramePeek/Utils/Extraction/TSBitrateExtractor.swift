import AVFoundation
import CoreMedia

/// Extracts bitrate from MPEG-TS files with optional TS packet overhead accounting
func extractTS(
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

    // Collect all samples
    let estimatedFrameCount = Int(durationSeconds * estimatedFPS)
    var allSamples: [(pts: Double, size: Int64)] = []
    allSamples.reserveCapacity(min(estimatedFrameCount, 1_000_000))

    var readCount = 0
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
        }

        if readCount % 500 == 0 {
            await Task.yield()
        }
    }
    
    // Sort by PTS
    allSamples.sort { $0.pts < $1.pts }

    // Rolling window state
    var window: [(pts: Double, size: Int64)] = []
    window.reserveCapacity(Int(estimatedFPS * windowSize) + 10)

    var previousPTS: Double? = nil
    var nextEmitPTS: Double? = nil

    for (pts, size) in allSamples {
        if Task.isCancelled || totalEmitted >= options.maxSamples { break }
        
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
            var totalBytes = window.reduce(0) { $0 + $1.size }
            
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

            // Calculate raw bitrate
            var bitrate = (Double(totalBytes) * 8.0) / duration
            
            // Account for TS packet overhead if enabled
            if options.accountTSOverhead && options.formatAccuracyMode != .performance {
                // Estimate TS packet count from sample sizes
                // TS packets are 188 bytes, with 4-byte header overhead per packet
                // We estimate: average sample might span multiple TS packets
                // Conservative estimate: assume samples are roughly aligned to packet boundaries
                let estimatedPackets = Double(totalBytes) / 184.0  // 188 - 4 (payload per packet, roughly)
                let overheadBytes = estimatedPackets * 4.0  // 4 bytes header per packet
                let overheadBits = overheadBytes * 8.0
                let overheadBitrate = overheadBits / duration
                
                // Subtract overhead from bitrate to get actual video bitrate
                bitrate = max(0, bitrate - overheadBitrate)
            }
            
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

