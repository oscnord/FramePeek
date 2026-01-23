import AVFoundation
import CoreMedia

private func detectFixedGOPPattern(_ frameCounts: [Int], tolerance: Int) -> Int? {
    guard frameCounts.count >= 3 else { return nil }
    let median = frameCounts.sorted()[frameCounts.count / 2]
    let allWithinTolerance = frameCounts.allSatisfy { abs($0 - median) <= tolerance }
    return allWithinTolerance ? median : nil
}

func extractGOPSegments(
    asset: AVAsset,
    options: GOPOptions
) -> AsyncStream<GOPUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let isPreview = options.maxScanSeconds != nil || options.maxGOPs != nil

            guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
                continuation.yield(GOPUpdate(
                    appendedSegments: [],
                    scannedUntilSeconds: 0,
                    isFinished: true,
                    isPreview: isPreview
                ))
                continuation.finish()
                return
            }

            let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0

            var codecType: FourCharCode?
            if options.detectFrameTypes {
                if let formatDescs = try? await track.load(.formatDescriptions),
                   let firstDesc = formatDescs.first {
                    codecType = CMFormatDescriptionGetMediaSubType(firstDesc)
                }
            }

            do {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                output.alwaysCopiesSampleData = false

                guard reader.canAdd(output) else {
                    continuation.yield(GOPUpdate(
                        appendedSegments: [],
                        scannedUntilSeconds: 0,
                        isFinished: true,
                        isPreview: isPreview
                    ))
                    continuation.finish()
                    return
                }

                reader.add(output)

                guard reader.startReading() else {
                    continuation.yield(GOPUpdate(
                        appendedSegments: [],
                        scannedUntilSeconds: 0,
                        isFinished: true,
                        isPreview: isPreview
                    ))
                    continuation.finish()
                    return
                }

                var pending: [GOPSegment] = []
                pending.reserveCapacity(options.emitEveryNGOPs)

                var lastKeyframeTime: Double?
                var framesInCurrentGOP: Int = 0
                var framesInCurrentGOPList: [FrameInfo] = []

                var emittedGOPs = 0
                var sampleCount = 0
                var lastSeenPTS: Double = 0
                var lastScannedPTS: Double = 0

                var completedGOPFrameCounts: [Int] = []
                var allCompletedGOPs: [GOPSegment] = []
                // Limit stored GOPs to prevent unbounded memory growth
                // We only need a few for pattern detection and representative GOP selection
                let maxStoredGOPs = 100
                var detectedStructureType: GOPStructureType = .unknown
                var representativeGOP: GOPSegment?
                var fixedGOPDetected = false

                func yieldPending(isFinished: Bool, structureType: GOPStructureType = .unknown, representativeGOP: GOPSegment? = nil) {
                    let fixedCount = structureType.fixedFrameCount
                    continuation.yield(GOPUpdate(
                        appendedSegments: pending,
                        scannedUntilSeconds: lastScannedPTS,
                        isFinished: isFinished,
                        isPreview: isPreview,
                        structureType: structureType,
                        detectedFixedFrameCount: fixedCount,
                        representativeGOP: representativeGOP
                    ))
                    pending.removeAll(keepingCapacity: true)
                }

                var shouldStopEarly = false
                let timeRange = options.timeRange

                while let sbuf = output.copyNextSampleBuffer() {
                    if Task.isCancelled { break }

                    let t = CMSampleBufferGetPresentationTimeStamp(sbuf).seconds
                    sampleCount += 1

                    guard t.isFinite else {
                        if sampleCount % 2000 == 0 { await Task.yield() }
                        continue
                    }

                    if let range = timeRange, t < range.lowerBound {
                        if sampleCount % 2000 == 0 { await Task.yield() }
                        continue
                    }

                    if let range = timeRange, t > range.upperBound {
                        shouldStopEarly = true
                        break
                    }

                    lastSeenPTS = max(lastSeenPTS, t)
                    lastScannedPTS = t

                    var isKeyframe = false
                    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: false),
                       CFArrayGetCount(attachments) > 0 {
                        if let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self) as? [CFString: Any] {
                            let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
                            isKeyframe = !notSync
                        }
                    }

                    var frameType: FrameType = .unknown
                    var frameSize: Int64?
                    if options.detectFrameTypes {
                        if let codec = codecType {
                            frameType = detectFrameType(sampleBuffer: sbuf, codecType: codec)

                            if isKeyframe {
                                if frameType != .i {
                                    frameType = .i
                                }
                            } else if frameType == .unknown {
                                if let dataBuffer = CMSampleBufferGetDataBuffer(sbuf) {
                                    var totalLength: Int = 0
                                    CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: nil)
                                    frameSize = Int64(totalLength)
                                }
                                frameType = .unknown
                            }
                        } else {
                            frameType = isKeyframe ? .i : .unknown
                        }
                        if frameSize == nil, let dataBuffer = CMSampleBufferGetDataBuffer(sbuf) {
                            var totalLength: Int = 0
                            CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: nil)
                            frameSize = Int64(totalLength)
                        }
                    } else if isKeyframe {
                        frameType = .i
                    }

                    if isKeyframe {
                        if let start = lastKeyframeTime {
                            let gopStart = start
                            let gopEnd = t
                            let shouldIncludeGOP: Bool
                            if let range = timeRange {
                                shouldIncludeGOP = gopEnd >= range.lowerBound && gopStart <= range.upperBound
                            } else {
                                shouldIncludeGOP = true
                            }

                            if shouldIncludeGOP {
                                let sortedFrames = options.detectFrameTypes ? framesInCurrentGOPList.sorted(by: { $0.time < $1.time }) : nil
                                let newSegment = GOPSegment(
                                    startTime: max(gopStart, timeRange?.lowerBound ?? gopStart),
                                    endTime: min(gopEnd, timeRange?.upperBound ?? gopEnd),
                                    frameCount: framesInCurrentGOP,
                                    frames: sortedFrames
                                )
                                pending.append(newSegment)
                                // Limit stored GOPs to prevent memory growth
                                if allCompletedGOPs.count < maxStoredGOPs {
                                    allCompletedGOPs.append(newSegment)
                                }
                                emittedGOPs += 1

                                if let frameCount = newSegment.frameCount {
                                    completedGOPFrameCounts.append(frameCount)
                                }

                                if options.detectFixedStructure && !fixedGOPDetected {
                                    if completedGOPFrameCounts.count >= options.minGOPsForFixedDetection {
                                        if let fixedCount = detectFixedGOPPattern(completedGOPFrameCounts, tolerance: options.fixedFrameTolerance) {
                                            fixedGOPDetected = true
                                            detectedStructureType = .fixed(frameCount: fixedCount)

                                            representativeGOP = allCompletedGOPs.first(where: { $0.frameCount == fixedCount && $0.frames != nil })
                                                ?? allCompletedGOPs.first(where: { $0.frameCount == fixedCount })
                                                ?? newSegment

                                            yieldPending(isFinished: true, structureType: detectedStructureType, representativeGOP: representativeGOP)
                                            continuation.finish()
                                            return
                                        } else {
                                            detectedStructureType = .variable
                                        }
                                    }
                                }

                                if pending.count >= options.emitEveryNGOPs {
                                    yieldPending(isFinished: false, structureType: detectedStructureType)
                                }

                                if let maxGOPs = options.maxGOPs, emittedGOPs >= maxGOPs {
                                    shouldStopEarly = true
                                }
                            }
                        }

                        if timeRange == nil || (t >= timeRange!.lowerBound && t <= timeRange!.upperBound) {
                            lastKeyframeTime = t
                            framesInCurrentGOP = 1
                            let keyframeType = (options.detectFrameTypes && frameType != .unknown) ? frameType : .i
                            framesInCurrentGOPList = [FrameInfo(time: t, type: keyframeType, size: frameSize)]
                        }
                    } else {
                        if lastKeyframeTime != nil {
                            if timeRange == nil || (t >= timeRange!.lowerBound && t <= timeRange!.upperBound) {
                                framesInCurrentGOP += 1
                                if options.detectFrameTypes {
                                    framesInCurrentGOPList.append(FrameInfo(time: t, type: frameType, size: frameSize))
                                }
                            }
                        }
                    }

                    if let maxSeconds = options.maxScanSeconds {
                        if t > maxSeconds {
                            shouldStopEarly = true
                        }
                    }

                    if shouldStopEarly { break }

                    if sampleCount % 2000 == 0 {
                        await Task.yield()
                    }
                }

                if !Task.isCancelled, let start = lastKeyframeTime {
                    let end: Double
                    if let range = timeRange {
                        let rangeEnd = range.upperBound
                        if durationSeconds.isFinite, durationSeconds > 0 {
                            end = min(durationSeconds, rangeEnd)
                        } else {
                            end = rangeEnd
                        }
                    } else if let maxSeconds = options.maxScanSeconds {
                        if durationSeconds.isFinite, durationSeconds > 0 {
                            end = min(durationSeconds, maxSeconds, lastScannedPTS)
                        } else {
                            end = min(maxSeconds, lastScannedPTS)
                        }
                    } else {
                        if durationSeconds.isFinite, durationSeconds > 0 {
                            end = durationSeconds
                        } else {
                            end = max(lastSeenPTS, start)
                        }
                    }

                    let shouldIncludeLastGOP: Bool
                    if let range = timeRange {
                        shouldIncludeLastGOP = end >= range.lowerBound && start <= range.upperBound
                    } else if let maxSeconds = options.maxScanSeconds {
                        shouldIncludeLastGOP = start < maxSeconds
                    } else {
                        shouldIncludeLastGOP = true
                    }

                    if shouldIncludeLastGOP && (end > start || framesInCurrentGOP > 0) {
                        let sortedFrames = options.detectFrameTypes ? framesInCurrentGOPList.sorted(by: { $0.time < $1.time }) : nil
                        let effectiveEnd = end > start ? end : start + 0.001
                        pending.append(GOPSegment(
                            startTime: max(start, timeRange?.lowerBound ?? start),
                            endTime: min(effectiveEnd, timeRange?.upperBound ?? effectiveEnd),
                            frameCount: framesInCurrentGOP,
                            frames: sortedFrames
                        ))
                    }
                }

                if !pending.isEmpty {
                    yieldPending(isFinished: false, structureType: detectedStructureType)
                }

                continuation.yield(GOPUpdate(
                    appendedSegments: [],
                    scannedUntilSeconds: lastScannedPTS,
                    isFinished: true,
                    isPreview: isPreview,
                    structureType: detectedStructureType
                ))
                continuation.finish()
            } catch {
                #if DEBUG
                print("GOPAnalyzer: Failed to analyze GOP structure - \(error.localizedDescription)")
                #endif
                continuation.yield(GOPUpdate(
                    appendedSegments: [],
                    scannedUntilSeconds: 0,
                    isFinished: true,
                    isPreview: isPreview
                ))
                continuation.finish()
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}
