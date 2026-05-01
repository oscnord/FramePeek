import AVFoundation
import CoreMedia

private func detectFixedGOPPattern(_ frameCounts: [Int], tolerance: Int) -> Int? {
    guard frameCounts.count >= 3 else { return nil }
    let median = frameCounts.sorted()[frameCounts.count / 2]
    let allWithinTolerance = frameCounts.allSatisfy { abs($0 - median) <= tolerance }
    return allWithinTolerance ? median : nil
}

// MARK: - Fast GOP Extraction (MP4/MOV only)

/// Attempts fast GOP extraction using MP4 atom parsing.
/// Falls back to standard extraction if fast path is unavailable.
public func extractGOPSegmentsFast(
    asset: AVAsset,
    url: URL,
    options: GOPOptions
) -> AsyncStream<GOPUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let isPreview = options.maxScanSeconds != nil || options.maxGOPs != nil
            
            // Try fast path for MP4/MOV files
            if SyncSampleParser.canUseFastParsing(for: url),
               let syncResult = await SyncSampleParser.parseSyncSamples(from: url) {
                
                let keyframes = SyncSampleParser.keyframeTimestamps(from: syncResult)
                
                // Build GOP segments from keyframe timestamps
                var segments: [GOPSegment] = []
                segments.reserveCapacity(keyframes.count)
                
                let totalSamples = Int(syncResult.totalSampleCount)
                let avgFramesPerGOP = keyframes.count > 1 ? totalSamples / keyframes.count : totalSamples
                
                for i in 0..<keyframes.count {
                    let startTime = keyframes[i].timestamp
                    let endTime: Double
                    let frameCount: Int
                    
                    if i + 1 < keyframes.count {
                        endTime = keyframes[i + 1].timestamp
                        // Estimate frame count based on sample indices
                        let startIdx = Int(keyframes[i].sampleIndex)
                        let endIdx = Int(keyframes[i + 1].sampleIndex)
                        frameCount = endIdx - startIdx
                    } else {
                        // Last GOP - estimate from total duration/samples
                        let duration = (try? await asset.load(.duration).seconds) ?? startTime + 1.0
                        endTime = duration
                        frameCount = totalSamples - Int(keyframes[i].sampleIndex) + 1
                    }
                    
                    // Apply time range filter if specified
                    if let range = options.timeRange {
                        if endTime < range.lowerBound { continue }
                        if startTime > range.upperBound { break }
                    }
                    
                    // Apply maxScanSeconds filter
                    if let maxSeconds = options.maxScanSeconds, startTime > maxSeconds {
                        break
                    }
                    
                    segments.append(GOPSegment(
                        startTime: startTime,
                        endTime: endTime,
                        frameCount: frameCount,
                        frames: nil // Fast path doesn't detect frame types
                    ))
                    
                    // Apply maxGOPs filter
                    if let maxGOPs = options.maxGOPs, segments.count >= maxGOPs {
                        break
                    }
                    
                    // Emit batches for progressive updates
                    if segments.count % options.emitEveryNGOPs == 0 {
                        let scannedUntil = segments.last?.endTime ?? 0
                        continuation.yield(GOPUpdate(
                            appendedSegments: Array(segments.suffix(options.emitEveryNGOPs)),
                            scannedUntilSeconds: scannedUntil,
                            isFinished: false,
                            isPreview: isPreview
                        ))
                    }
                }
                
                // Detect pattern
                var structureType: GOPStructureType = .unknown
                let frameCounts = segments.compactMap(\.frameCount)
                if options.detectFixedStructure && frameCounts.count >= options.minGOPsForFixedDetection {
                    if let fixedCount = detectFixedGOPPattern(frameCounts, tolerance: options.fixedFrameTolerance) {
                        structureType = .fixed(frameCount: fixedCount)
                    } else {
                        structureType = .variable
                    }
                }
                
                let remainingSegments = segments.suffix(segments.count % options.emitEveryNGOPs)
                let scannedUntil = segments.last?.endTime ?? 0
                
                if !remainingSegments.isEmpty {
                    continuation.yield(GOPUpdate(
                        appendedSegments: Array(remainingSegments),
                        scannedUntilSeconds: scannedUntil,
                        isFinished: false,
                        isPreview: isPreview,
                        structureType: structureType
                    ))
                }
                
                continuation.yield(GOPUpdate(
                    appendedSegments: [],
                    scannedUntilSeconds: scannedUntil,
                    isFinished: true,
                    isPreview: isPreview,
                    structureType: structureType
                ))
                continuation.finish()
                return
            }
            
            // Fast path not available, fall back to standard extraction
            // (This happens for fMP4, TS, or files where parsing failed)
            for await update in extractGOPSegmentsStandard(asset: asset, options: options) {
                continuation.yield(update)
                if update.isFinished { break }
            }
            continuation.finish()
        }
        
        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Standard GOP Extraction (works with all formats)

public func extractGOPSegments(
    asset: AVAsset,
    options: GOPOptions
) -> AsyncStream<GOPUpdate> {
    // Try to get URL for fast path
    if let urlAsset = asset as? AVURLAsset {
        return extractGOPSegmentsFast(asset: asset, url: urlAsset.url, options: options)
    }
    return extractGOPSegmentsStandard(asset: asset, options: options)
}

private func extractGOPSegmentsStandard(
    asset: AVAsset,
    options: GOPOptions
) -> AsyncStream<GOPUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let isPreview = options.maxScanSeconds != nil || options.maxGOPs != nil

            guard let track = await AVAssetLoader.firstTrack(of: asset, mediaType: .video) else {
                continuation.yield(GOPUpdate(
                    appendedSegments: [],
                    scannedUntilSeconds: 0,
                    isFinished: true,
                    isPreview: isPreview
                ))
                continuation.finish()
                return
            }

            let durationSeconds = await AVAssetLoader.durationSeconds(of: asset)

            var codecType: FourCharCode?
            if options.detectFrameTypes,
               let firstDesc = await AVAssetLoader.firstFormatDescription(of: track) {
                codecType = CMFormatDescriptionGetMediaSubType(firstDesc)
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
                Log.analysis.error("GOPAnalyzer: Failed to analyze GOP structure - \(error.localizedDescription)")
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
