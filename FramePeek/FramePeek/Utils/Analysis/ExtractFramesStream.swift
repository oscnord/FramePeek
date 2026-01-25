import AVFoundation
import CoreMedia

public struct FrameAnalysisUpdate {
    public var appendedSamples: [BitrateSample] = []
    public var rawFrames: [RawFrame] = []  // Raw frame data for re-aggregation
    public var averageFPS: Double?
    public var minInterval: Double?
    public var maxInterval: Double?
    public var isFinished: Bool = false
    
    public init(appendedSamples: [BitrateSample] = [], rawFrames: [RawFrame] = [], averageFPS: Double? = nil, minInterval: Double? = nil, maxInterval: Double? = nil, isFinished: Bool = false) {
        self.appendedSamples = appendedSamples
        self.rawFrames = rawFrames
        self.averageFPS = averageFPS
        self.minInterval = minInterval
        self.maxInterval = maxInterval
        self.isFinished = isFinished
    }
}

public func extractFramesStream(
    asset: AVAsset,
    options: FrameSamplingOptions
) -> AsyncStream<FrameAnalysisUpdate> {

    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

            // Video track
            let videoTrack: AVAssetTrack?
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                videoTrack = tracks.first
            } catch {
                print("Failed to load video tracks: \(error.localizedDescription)")
                continuation.yield(finish)
                continuation.finish()
                return
            }

            guard let videoTrack else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Get duration and nominal frame rate for smart sampling
            let duration = (try? await asset.load(.duration)) ?? .zero
            let durationSeconds = duration.seconds
            let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0

            guard durationSeconds.isFinite, durationSeconds > 0 else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Determine sampling strategy - use seeking only for large intervals on long videos
            // The seeking approach creates multiple readers which has overhead, so only use it
            // when it will actually save significant time
            let estimatedFrameCount = durationSeconds * Double(nominalFrameRate)
            let samplesNeeded = options.maxSamples
            let seekingWorthIt = options.minEmitIntervalSeconds != nil
                && options.minEmitIntervalSeconds! >= 0.5
                && estimatedFrameCount > 10000
                && Double(samplesNeeded) < estimatedFrameCount / 10

            if seekingWorthIt {
                // FAST PATH: Sample at intervals by seeking (skips most frames)
                await extractWithSeeking(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
            } else {
                // NORMAL PATH: Read frames sequentially with interval-based emission
                await extractEveryFrame(
                    asset: asset,
                    videoTrack: videoTrack,
                    options: options,
                    continuation: continuation
                )
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Fast seeking-based sampling (for interval mode)

private func extractWithSeeking(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    durationSeconds: Double,
    nominalFrameRate: Double,
    options: FrameSamplingOptions,
    continuation: AsyncStream<FrameAnalysisUpdate>.Continuation
) async {
    let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)
    let interval = options.minEmitIntervalSeconds ?? 1.0

    // Calculate sample times
    var sampleTimes: [Double] = []
    var t = 0.0
    while t < durationSeconds && sampleTimes.count < options.maxSamples {
        sampleTimes.append(t)
        t += interval
    }

    guard !sampleTimes.isEmpty else {
        continuation.yield(finish)
        continuation.finish()
        return
    }

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)
    var totalEmitted = 0

    // Estimated FPS from nominal rate
    let estimatedFPS = nominalFrameRate > 0 ? nominalFrameRate : 30.0
    let frameDuration = 1.0 / estimatedFPS

    func makeUpdate(isFinished: Bool = false) -> FrameAnalysisUpdate {
        return FrameAnalysisUpdate(
            appendedSamples: pending,
            rawFrames: [],
            averageFPS: estimatedFPS,
            minInterval: frameDuration,
            maxInterval: frameDuration,
            isFinished: isFinished
        )
    }

    for sampleTime in sampleTimes {
        if Task.isCancelled { break }

        // Create a reader for a small time range around our sample point
        // We need to read enough frames to get a meaningful bitrate average
        let windowSize = max(interval, 0.5) // At least 0.5 seconds window
        let startTime = CMTime(seconds: max(0, sampleTime), preferredTimescale: 600)
        let endTime = CMTime(seconds: min(durationSeconds, sampleTime + windowSize), preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        guard let reader = try? AVAssetReader(asset: asset) else { continue }
        reader.timeRange = timeRange

        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else { continue }
        reader.add(output)

        guard reader.startReading() else { continue }

        // Read frames in this window to calculate average bitrate
        var totalSize = 0
        var firstTime: Double?
        var lastTime: Double?
        var frameCount = 0
        let maxFramesToRead = Int(windowSize * estimatedFPS) + 5 // Read frames for the window duration

        while let sampleBuffer = output.copyNextSampleBuffer(), frameCount < maxFramesToRead {
            autoreleasepool {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                let size = CMSampleBufferGetTotalSampleSize(sampleBuffer)

                if firstTime == nil { firstTime = pts }
                lastTime = pts
                totalSize += size
                frameCount += 1
            }
        }

        reader.cancelReading()

        // Calculate bitrate from the frames we read
        if frameCount > 0, let first = firstTime {
            let measuredDuration: Double
            if let last = lastTime, last > first {
                let actualSpan = last - first
                // If we have enough frames for a full window, use the window size
                // Otherwise use actual span + frame duration
                if actualSpan >= windowSize - frameDuration {
                    measuredDuration = windowSize
                } else {
                    measuredDuration = actualSpan + frameDuration
                }
            } else {
                // Single frame - use frame duration
                measuredDuration = frameDuration
            }

            let bitrate = (Double(totalSize) * 8.0) / measuredDuration

            pending.append(BitrateSample(time: sampleTime, bitrate: bitrate, duration: measuredDuration))
            totalEmitted += 1

            if pending.count >= options.emitEveryNSamples {
                continuation.yield(makeUpdate())
                pending.removeAll(keepingCapacity: true)
            }
        }

        // Yield to other tasks periodically
        if totalEmitted % 20 == 0 {
            await Task.yield()
        }
    }

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
    }

    continuation.yield(makeUpdate(isFinished: true))
    continuation.finish()
}

// MARK: - Full frame reading (for everyFrame mode or accurate FPS)

private func extractEveryFrame(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    options: FrameSamplingOptions,
    continuation: AsyncStream<FrameAnalysisUpdate>.Continuation
) async {
    let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

    let reader: AVAssetReader
    do {
        reader = try AVAssetReader(asset: asset)
    } catch {
        print("Failed to create AVAssetReader: \(error.localizedDescription)")
        continuation.yield(finish)
        continuation.finish()
        return
    }

    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    output.alwaysCopiesSampleData = false

    guard reader.canAdd(output) else {
        print("Reader cannot add output")
        continuation.yield(finish)
        continuation.finish()
        return
    }
    reader.add(output)

    guard reader.startReading() else {
        print("Reader failed to start: \(reader.error?.localizedDescription ?? "Unknown error")")
        continuation.yield(finish)
        continuation.finish()
        return
    }

    var pending: [BitrateSample] = []
    pending.reserveCapacity(options.emitEveryNSamples)

    var previousTimeForStats: Double?

    var sumInterval = 0.0
    var intervalCount = 0
    var minIntervalVal = Double.greatestFiniteMagnitude
    var maxIntervalVal = 0.0

    var totalEmitted = 0

    // For windowed bitrate averaging
    var windowStartTime: Double?
    var windowTotalBytes = 0
    var lastEmittedTime: Double?
    let emitInterval = options.minEmitIntervalSeconds ?? 0

    func makeUpdate(isFinished: Bool = false) -> FrameAnalysisUpdate {
        let avgFPS: Double?
        let minInt: Double?
        let maxInt: Double?

        if intervalCount > 0 {
            let avgInterval = sumInterval / Double(intervalCount)
            avgFPS = avgInterval > 0 ? 1.0 / avgInterval : nil
            minInt = minIntervalVal.isFinite ? minIntervalVal : nil
            maxInt = maxIntervalVal > 0 ? maxIntervalVal : nil
        } else {
            avgFPS = nil
            minInt = nil
            maxInt = nil
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

    // Collect raw frames for re-aggregation
    // Reserve capacity based on estimated frame count for better performance
    let duration = (try? await asset.load(.duration)) ?? .zero
    let durationSeconds = duration.seconds
    let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0
    let estimatedFrameCount = Int(durationSeconds * Double(nominalFrameRate))
    var allRawFrames: [RawFrame] = []
    allRawFrames.reserveCapacity(min(estimatedFrameCount, 1_000_000)) // Cap at 1M to avoid excessive memory

    while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
        autoreleasepool {
            let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let sampleSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)

            // Store raw frame data
            if sampleSize > 0 && currentTime.isFinite {
                allRawFrames.append((pts: currentTime, size: Int64(sampleSize)))
            }

            // Stats: every frame (so effectiveFPS/min/max are real)
            if let prev = previousTimeForStats, currentTime > prev {
                let interval = currentTime - prev
                sumInterval += interval
                intervalCount += 1
                if interval < minIntervalVal { minIntervalVal = interval }
                if interval > maxIntervalVal { maxIntervalVal = interval }
            }
            previousTimeForStats = currentTime

            // Initialize window if needed
            if windowStartTime == nil {
                windowStartTime = currentTime
            }

            // Accumulate bytes for this window
            windowTotalBytes += sampleSize

            // Check if we should emit a sample
            let shouldEmit: Bool
            if emitInterval > 0 {
                // Interval mode: emit when we've accumulated enough time
                if let last = lastEmittedTime {
                    shouldEmit = (currentTime - last) >= emitInterval
                } else {
                    // First sample - emit after accumulating at least half the interval
                    shouldEmit = (currentTime - (windowStartTime ?? 0)) >= emitInterval * 0.5
                }
            } else {
                // Every frame mode
                shouldEmit = true
            }

            if shouldEmit, totalEmitted < options.maxSamples, let windowStart = windowStartTime {
                let windowDuration = currentTime - windowStart

                if windowDuration > 0 {
                    // Calculate average bitrate over the window
                    // Add frame duration to account for the last frame extending beyond its PTS
                    let frameDuration = intervalCount > 0 ? sumInterval / Double(intervalCount) : 1.0 / 30.0
                    let effectiveDuration = windowDuration + frameDuration
                    let avgBitrate = (Double(windowTotalBytes) * 8.0) / effectiveDuration
                    pending.append(BitrateSample(time: currentTime, bitrate: avgBitrate, duration: effectiveDuration))
                    totalEmitted += 1
                    lastEmittedTime = currentTime

                    // Reset window for next sample
                    windowStartTime = currentTime
                    windowTotalBytes = 0
                } else if emitInterval == 0 {
                    // Every frame mode with no previous frame - use frame size with estimated duration
                    let estimatedDuration = intervalCount > 0 ? sumInterval / Double(intervalCount) : 1.0 / 30.0
                    let bitrate = (Double(sampleSize) * 8.0) / estimatedDuration
                    pending.append(BitrateSample(time: currentTime, bitrate: bitrate, duration: estimatedDuration))
                    totalEmitted += 1
                    lastEmittedTime = currentTime
                    windowStartTime = currentTime
                    windowTotalBytes = 0
                }
            }

            if pending.count >= options.emitEveryNSamples {
                continuation.yield(makeUpdate())
                pending.removeAll(keepingCapacity: true)
            }
        }

        // Yield periodically to let other tasks run
        if intervalCount % 500 == 0 {
            await Task.yield()
        }
    }

    if !pending.isEmpty {
        continuation.yield(makeUpdate())
        pending.removeAll()
    }

    if reader.status != .completed && !Task.isCancelled {
        print("Reader ended with status \(reader.status): \(reader.error?.localizedDescription ?? "No error")")
    }

    // Include raw frames in final update
    var finalUpdate = makeUpdate(isFinished: true)
    finalUpdate.rawFrames = allRawFrames
    continuation.yield(finalUpdate)
    continuation.finish()
}
