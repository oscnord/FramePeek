//
//  ExtractFramesStream.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-08.
//

import AVFoundation
import CoreMedia

struct FrameAnalysisUpdate {
    var appendedSamples: [BitrateSample] = []
    var averageFPS: Double? = nil
    var minInterval: Double? = nil
    var maxInterval: Double? = nil
    var isFinished: Bool = false
}

func extractFramesStream(
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

            // Reader + output
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

            var previousTimeForBitrate: Double?
            var previousTimeForStats: Double?
            var lastEmittedTime: Double?

            var sumInterval = 0.0
            var intervalCount = 0
            var minIntervalVal = Double.greatestFiniteMagnitude
            var maxIntervalVal = 0.0

            var totalEmitted = 0

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
                    averageFPS: avgFPS,
                    minInterval: minInt,
                    maxInterval: maxInt,
                    isFinished: isFinished
                )
            }

            while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
                autoreleasepool {
                    let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    let sampleSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)

                    // Stats: every frame (so effectiveFPS/min/max are real)
                    if let prev = previousTimeForStats, currentTime > prev {
                        let interval = currentTime - prev
                        sumInterval += interval
                        intervalCount += 1
                        if interval < minIntervalVal { minIntervalVal = interval }
                        if interval > maxIntervalVal { maxIntervalVal = interval }
                    }
                    previousTimeForStats = currentTime

                    // Bitrate sample between frames
                    if let prev = previousTimeForBitrate, currentTime > prev {
                        let frameDuration = currentTime - prev
                        if frameDuration > 0 {
                            let frameBitrate = (Double(sampleSize) * 8.0) / frameDuration

                            // Sampling gate (interval-based)
                            let shouldEmit: Bool
                            if let minInterval = options.minEmitIntervalSeconds, minInterval > 0 {
                                if let last = lastEmittedTime {
                                    shouldEmit = (currentTime - last) >= minInterval
                                } else {
                                    shouldEmit = true
                                }
                            } else {
                                shouldEmit = true
                            }

                            if shouldEmit, totalEmitted < options.maxSamples {
                                pending.append(BitrateSample(time: currentTime, bitrate: frameBitrate))
                                lastEmittedTime = currentTime
                                totalEmitted += 1
                            }
                        }
                    }
                    previousTimeForBitrate = currentTime

                    if pending.count >= options.emitEveryNSamples {
                        continuation.yield(makeUpdate())
                        pending.removeAll(keepingCapacity: true)
                    }
                }
            }

            if !pending.isEmpty {
                continuation.yield(makeUpdate())
                pending.removeAll()
            }

            if reader.status != .completed && !Task.isCancelled {
                print("Reader ended with status \(reader.status): \(reader.error?.localizedDescription ?? "No error")")
            }

            continuation.yield(makeUpdate(isFinished: true))
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}
