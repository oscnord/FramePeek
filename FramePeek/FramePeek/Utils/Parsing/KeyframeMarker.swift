
import AVFoundation
import CoreMedia
import AppKit

struct KeyframeMarker: Identifiable {
    let id = UUID()
    let time: Double
}

struct KeyframeThumbnail: Identifiable {
    let id = UUID()
    let time: Double
    let image: NSImage
}

/// Extracts keyframes and returns them progressively via AsyncStream
func extractKeyframesStream(
    asset: AVAsset,
    maxKeyframes: Int = 20_000,           // safety cap
    minSpacingSeconds: Double = 0.0,      // optional downsample to avoid "solid line"
    onProgress: ((String) -> Void)? = nil // Optional progress callback
) -> AsyncStream<[KeyframeMarker]> {
    
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            // Load the video track
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            guard let track = tracks?.first else {
                continuation.finish()
                return
            }
            
            // Get duration for fallback synthetic keyframes
            let duration = (try? await asset.load(.duration).seconds) ?? 0

            // Use optimized AVAssetReader - we need sample buffers to check keyframe status
            await extractKeyframesWithReaderStream(
                asset: asset,
                track: track,
                duration: duration,
                maxKeyframes: maxKeyframes,
                minSpacingSeconds: minSpacingSeconds,
                onProgress: onProgress,
                continuation: continuation
            )
        }
        
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Legacy function that collects all keyframes before returning
func extractKeyframes(
    asset: AVAsset,
    maxKeyframes: Int = 20_000,           // safety cap
    minSpacingSeconds: Double = 0.0,      // optional downsample to avoid "solid line"
    onProgress: ((String) -> Void)? = nil // Optional progress callback
) async -> [KeyframeMarker] {
    var allKeyframes: [KeyframeMarker] = []
    
    for await batch in extractKeyframesStream(
        asset: asset,
        maxKeyframes: maxKeyframes,
        minSpacingSeconds: minSpacingSeconds,
        onProgress: onProgress
    ) {
        allKeyframes.append(contentsOf: batch)
    }
    
    return allKeyframes
}

// MARK: - Optimized reader-based extraction (streaming)

private func extractKeyframesWithReaderStream(
    asset: AVAsset,
    track: AVAssetTrack,
    duration: Double,
    maxKeyframes: Int,
    minSpacingSeconds: Double,
    onProgress: ((String) -> Void)?,
    continuation: AsyncStream<[KeyframeMarker]>.Continuation
) async {
    
    do {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            continuation.finish()
            return
        }
        reader.add(output)

        guard reader.startReading() else {
            continuation.finish()
            return
        }

        var pendingMarkers: [KeyframeMarker] = []
        pendingMarkers.reserveCapacity(50) // Batch size for updates
        
        // Don't accumulate all markers - just track count to avoid memory growth
        var totalKeyframeCount = 0
        var lastAccepted: Double? = nil
        var sampleCount = 0
        var lastProgressUpdate = 0
        var lastEmitCount = 0

        while let sbuf = output.copyNextSampleBuffer() {
            // Check for cancellation periodically
            if Task.isCancelled {
                break
            }
            
            let t = CMSampleBufferGetPresentationTimeStamp(sbuf).seconds
            guard t.isFinite else {
                sampleCount += 1
                if sampleCount % 2000 == 0 {
                    await Task.yield()
                }
                continue
            }

            // Optimized keyframe check - inline the attachment lookup
            var isKeyframe = false
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: false),
               CFArrayGetCount(attachments) > 0 {
                // Fast path: check if NotSync key exists and is false
                if let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self) as? [CFString: Any] {
                    // If NotSync is missing or false -> sync sample (keyframe)
                    let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
                    isKeyframe = !notSync
                }
            }

            if isKeyframe {
                if let last = lastAccepted, minSpacingSeconds > 0, (t - last) < minSpacingSeconds {
                    sampleCount += 1
                    // Yield every 2000 samples
                    if sampleCount % 2000 == 0 {
                        await Task.yield()
                    }
                    continue
                }
                
                let marker = KeyframeMarker(time: t)
                pendingMarkers.append(marker)
                totalKeyframeCount += 1
                lastAccepted = t
                
                // Emit batch every 20 keyframes or every 100 keyframes processed (optimized balance)
                if pendingMarkers.count >= 20 || (totalKeyframeCount - lastEmitCount) >= 100 {
                    continuation.yield(pendingMarkers)
                    pendingMarkers.removeAll(keepingCapacity: true)
                    lastEmitCount = totalKeyframeCount
                }
                
                if totalKeyframeCount >= maxKeyframes { break }
            }
            
            sampleCount += 1
            
            // Update progress every 5000 samples or every 100 keyframes
            if let progressCallback = onProgress, duration > 0 {
                let progressInterval = 5000
                if sampleCount - lastProgressUpdate >= progressInterval || (totalKeyframeCount > 0 && totalKeyframeCount % 100 == 0 && totalKeyframeCount != lastEmitCount) {
                    let timeProgress = duration > 0 ? min(100, Int((t / duration) * 100)) : 0
                    progressCallback("Extracting keyframes... \(totalKeyframeCount) found, \(timeProgress)%")
                    lastProgressUpdate = sampleCount
                }
            }
            
            // Yield every 2000 samples (balanced for performance and responsiveness)
            if sampleCount % 2000 == 0 {
                await Task.yield()
            }
        }
        
        // Emit any remaining pending markers (even if cancelled)
        if !pendingMarkers.isEmpty {
            continuation.yield(pendingMarkers)
        }
        
        // If we didn't get any keyframes but have duration, the file might use a format
        // where all frames are sync samples - create synthetic markers
        // Only create synthetic markers if we weren't cancelled
        if !Task.isCancelled && totalKeyframeCount == 0 && duration > 0 {
            let syntheticCount = min(100, max(10, Int(duration / 2))) // One every 2 seconds, min 10, max 100
            let interval = duration / Double(syntheticCount)
            var syntheticMarkers: [KeyframeMarker] = []
            for i in 0..<syntheticCount {
                syntheticMarkers.append(KeyframeMarker(time: Double(i) * interval))
            }
            continuation.yield(syntheticMarkers)
        }

        continuation.finish()
    } catch {
        continuation.finish()
    }
}
