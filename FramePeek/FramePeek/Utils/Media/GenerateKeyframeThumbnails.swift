import AVFoundation
import AppKit
import CoreImage
import os

/// Converts a CGImage to sRGB color space, handling HDR content properly
private func convertToSRGB(_ cgImage: CGImage) -> CGImage? {
    // Check if already in sRGB or Display P3 (compatible)
    if let colorSpace = cgImage.colorSpace {
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
           let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) {
            if CFEqual(colorSpace, sRGB) || CFEqual(colorSpace, displayP3) {
                return cgImage
            }
        }
    }
    
    // Use CoreImage to convert color space
    // CoreImage automatically applies tone mapping when converting from HDR to sRGB
    let ciImage = CIImage(cgImage: cgImage)
    
    guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return cgImage
    }
    
    // Create a CIContext with sRGB output
    // This will automatically apply tone mapping for HDR content
    let context = CIContext(options: [
        .workingColorSpace: sRGBColorSpace,
        .outputColorSpace: sRGBColorSpace
    ])
    
    guard let outputImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        return cgImage
    }
    
    return outputImage
}

/// Generates thumbnails progressively as they're created
func GenerateKeyframeThumbnailsStream(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150,  // Reasonable limit for smooth scrolling
    thumbHeight: CGFloat = 120,
    batchSize: Int = 10  // Generate thumbnails in batches
) -> AsyncStream<[KeyframeThumbnail]> {
    
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            guard !keyframeTimes.isEmpty else {
                continuation.finish()
                return
            }
            
            // Get video duration
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            guard duration > 0 else {
                continuation.finish()
                return
            }
            
            // Strategy: Generate thumbnails that cover the entire video evenly
            // but snap to actual keyframe times for accurate representation
            let chosen: [Double]
            
            if keyframeTimes.count <= maxThumbnails {
                // Use all keyframes if we have fewer than max
                chosen = keyframeTimes
            } else {
                // Distribute evenly across the video duration, snapping to nearest keyframes
                var selectedTimes: [Double] = []
                selectedTimes.reserveCapacity(maxThumbnails)
                
                let interval = duration / Double(maxThumbnails - 1)
                
                for i in 0..<maxThumbnails {
                    let targetTime = Double(i) * interval
                    
                    // Find nearest keyframe to this target time
                    if let nearest = keyframeTimes.min(by: { abs($0 - targetTime) < abs($1 - targetTime) }) {
                        // Avoid duplicates (if two target times snap to the same keyframe)
                        if selectedTimes.isEmpty || abs(selectedTimes.last! - nearest) > 0.001 {
                            selectedTimes.append(nearest)
                        }
                    }
                }
                
                // Ensure first and last keyframes are included
                if let first = keyframeTimes.first, !selectedTimes.contains(where: { abs($0 - first) < 0.001 }) {
                    selectedTimes.insert(first, at: 0)
                }
                if let last = keyframeTimes.last, !selectedTimes.contains(where: { abs($0 - last) < 0.001 }) {
                    selectedTimes.append(last)
                }
                
                chosen = selectedTimes.sorted()
            }

            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            // Thumbnails are displayed at 96x60, using 192x120 (2x for retina) for higher quality
            gen.maximumSize = CGSize(width: 192, height: 120)

            // Increase tolerance for faster generation (less precise but much faster)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
            
            // Use faster generation mode
            gen.apertureMode = .productionAperture

            let times = chosen.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
            
            guard !times.isEmpty else {
                continuation.finish()
                return
            }

            // Generate thumbnails in batches for progressive updates
            // Use os_unfair_lock for async-safe locking (Swift 6 compatible)
            var cancellationLock = os_unfair_lock_s()
            var cancelled = false
            
            var stateLock = os_unfair_lock_s()
            var pendingThumbnails: [KeyframeThumbnail] = []
            var completed = 0
            let total = times.count
            var finished = false
            
            // Helper function for async-safe locking
            func withLock<T>(_ lock: UnsafeMutablePointer<os_unfair_lock_s>, _ work: () -> T) -> T {
                os_unfair_lock_lock(lock)
                defer { os_unfair_lock_unlock(lock) }
                return work()
            }

            gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
                // Check cancellation flag (callback is not async, so direct access is fine)
                let isCancelled = withLock(&cancellationLock) { cancelled }
                
                if isCancelled {
                    return
                }
                
                // Access shared state with lock and return values
                let stateResult = withLock(&stateLock) { () -> (shouldEmit: Bool, batch: [KeyframeThumbnail]?, shouldFinish: Bool) in
                    // Check if we're already finished
                    if finished {
                        return (false, nil, false)
                    }

                    completed += 1
                    var shouldEmit = false
                    var batch: [KeyframeThumbnail]? = nil
                    var shouldFinish = false

                    if result == .succeeded, let cgImage {
                        // Convert to sRGB to handle HDR content properly
                        // This prevents the green tint issue with HDR/Dolby Vision content
                        let convertedImage = convertToSRGB(cgImage) ?? cgImage
                        let img = NSImage(cgImage: convertedImage, size: .zero)
                        let thumbnail = KeyframeThumbnail(time: requestedTime.seconds, image: img)
                        pendingThumbnails.append(thumbnail)
                        
                        // Emit batch when we have enough or when we're done
                        if pendingThumbnails.count >= batchSize || completed >= total {
                            batch = pendingThumbnails.sorted { $0.time < $1.time }
                            pendingThumbnails.removeAll(keepingCapacity: true)
                            shouldEmit = true
                        }
                    }

                    if completed >= total {
                        finished = true
                        // Emit any remaining thumbnails
                        if !pendingThumbnails.isEmpty {
                            batch = pendingThumbnails.sorted { $0.time < $1.time }
                            pendingThumbnails.removeAll(keepingCapacity: true)
                            shouldEmit = true
                        }
                        shouldFinish = true
                    }
                    
                    return (shouldEmit, batch, shouldFinish)
                }
                
                // Emit outside the lock to avoid blocking
                if stateResult.shouldEmit, let batchToEmit = stateResult.batch {
                    continuation.yield(batchToEmit)
                }
                
                if stateResult.shouldFinish {
                    continuation.finish()
                }
            }
            
            // Monitor for cancellation and cancel generator if needed
            // This runs as part of the main task, so it will be cancelled when the task is cancelled
            while !Task.isCancelled {
                let isDone = withLock(&stateLock) {
                    finished || completed >= total
                }
                
                if isDone {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1 seconds
            }
            
            // If cancelled, stop the generator
            if Task.isCancelled {
                withLock(&cancellationLock) {
                    cancelled = true
                }
                gen.cancelAllCGImageGeneration()
                withLock(&stateLock) {
                    finished = true
                }
                continuation.finish()
            }
        }
        
        continuation.onTermination = { _ in 
            task.cancel()
            // The cancellation monitor task will handle cancelling the generator
        }
    }
}

/// Legacy function that collects all thumbnails before returning
func GenerateKeyframeThumbnails(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150,  // Reasonable limit for smooth scrolling
    thumbHeight: CGFloat = 120
) async -> [KeyframeThumbnail] {
    var allThumbnails: [KeyframeThumbnail] = []
    
    for await batch in GenerateKeyframeThumbnailsStream(
        asset: asset,
        keyframeTimes: keyframeTimes,
        maxThumbnails: maxThumbnails,
        thumbHeight: thumbHeight
    ) {
        allThumbnails.append(contentsOf: batch)
    }
    
    return allThumbnails.sorted { $0.time < $1.time }
}

