import AVFoundation
import AppKit
import CoreImage
import os

/// Simple, direct sRGB conversion for HDR content
/// This is the simplest possible approach - just convert everything to sRGB using CoreImage
private func convertToSRGBSimple(_ cgImage: CGImage) -> CGImage? {
    guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return cgImage
    }
    
    // Check if already sRGB
    if let colorSpace = cgImage.colorSpace,
       let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
       CFEqual(colorSpace, sRGB) {
        return cgImage
    }
    
    // Simple CoreImage conversion - let it handle everything automatically
    let ciImage = CIImage(cgImage: cgImage)
    let context = CIContext(options: [
        .outputColorSpace: sRGBColorSpace
    ])
    
    // Render directly to sRGB - CoreImage will handle tone mapping automatically
    return context.createCGImage(ciImage, from: ciImage.extent, format: .BGRA8, colorSpace: sRGBColorSpace)
}

/// Generates thumbnails progressively as they're created
/// Simplified approach: Use AVAssetImageGenerator with direct CoreImage sRGB conversion
func GenerateKeyframeThumbnailsStream(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150,  // Reasonable limit for smooth scrolling
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
                chosen = keyframeTimes
            } else {
                var selectedTimes: [Double] = []
                selectedTimes.reserveCapacity(maxThumbnails)
                
                let interval = duration / Double(maxThumbnails - 1)
                
                for i in 0..<maxThumbnails {
                    let targetTime = Double(i) * interval
                    if let nearest = keyframeTimes.min(by: { abs($0 - targetTime) < abs($1 - targetTime) }) {
                        if selectedTimes.isEmpty || abs(selectedTimes.last! - nearest) > 0.001 {
                            selectedTimes.append(nearest)
                        }
                    }
                }
                
                if let first = keyframeTimes.first, !selectedTimes.contains(where: { abs($0 - first) < 0.001 }) {
                    selectedTimes.insert(first, at: 0)
                }
                if let last = keyframeTimes.last, !selectedTimes.contains(where: { abs($0 - last) < 0.001 }) {
                    selectedTimes.append(last)
                }
                
                chosen = selectedTimes.sorted()
            }

            // Simple AVAssetImageGenerator approach
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 192, height: 120)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
            gen.apertureMode = .productionAperture

            let times = chosen.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
            
            guard !times.isEmpty else {
                continuation.finish()
                return
            }

            // Simple state management
            var cancellationLock = os_unfair_lock_s()
            var cancelled = false
            
            var stateLock = os_unfair_lock_s()
            var pendingThumbnails: [KeyframeThumbnail] = []
            var completed = 0
            let total = times.count
            var finished = false
            
            func withLock<T>(_ lock: UnsafeMutablePointer<os_unfair_lock_s>, _ work: () -> T) -> T {
                os_unfair_lock_lock(lock)
                defer { os_unfair_lock_unlock(lock) }
                return work()
            }

            gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
                let isCancelled = withLock(&cancellationLock) { cancelled }
                if isCancelled { return }
                
                let stateResult = withLock(&stateLock) { () -> (shouldEmit: Bool, batch: [KeyframeThumbnail]?, shouldFinish: Bool) in
                    if finished { return (false, nil, false) }

                    completed += 1
                    var shouldEmit = false
                    var batch: [KeyframeThumbnail]? = nil
                    var shouldFinish = false

                    if result == .succeeded, let cgImage {
                        // Simple, direct sRGB conversion
                        let convertedImage = convertToSRGBSimple(cgImage) ?? cgImage
                        let img = NSImage(cgImage: convertedImage, size: .zero)
                        let thumbnail = KeyframeThumbnail(time: requestedTime.seconds, image: img)
                        pendingThumbnails.append(thumbnail)
                        
                        if pendingThumbnails.count >= batchSize || completed >= total {
                            batch = pendingThumbnails.sorted { $0.time < $1.time }
                            pendingThumbnails.removeAll(keepingCapacity: true)
                            shouldEmit = true
                        }
                    }

                    if completed >= total {
                        finished = true
                        if !pendingThumbnails.isEmpty {
                            batch = pendingThumbnails.sorted { $0.time < $1.time }
                            pendingThumbnails.removeAll(keepingCapacity: true)
                            shouldEmit = true
                        }
                        shouldFinish = true
                    }
                    
                    return (shouldEmit, batch, shouldFinish)
                }
                
                if stateResult.shouldEmit, let batchToEmit = stateResult.batch {
                    continuation.yield(batchToEmit)
                }
                
                if stateResult.shouldFinish {
                    continuation.finish()
                }
            }
            
            while !Task.isCancelled {
                let isDone = withLock(&stateLock) {
                    finished || completed >= total
                }
                if isDone { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            if Task.isCancelled {
                withLock(&cancellationLock) { cancelled = true }
                gen.cancelAllCGImageGeneration()
                withLock(&stateLock) { finished = true }
                continuation.finish()
            }
        }
        
        continuation.onTermination = { _ in 
            task.cancel()
        }
    }
}

/// Legacy function that collects all thumbnails before returning
func GenerateKeyframeThumbnails(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150  // Reasonable limit for smooth scrolling
) async -> [KeyframeThumbnail] {
    var allThumbnails: [KeyframeThumbnail] = []
    
    for await batch in GenerateKeyframeThumbnailsStream(
        asset: asset,
        keyframeTimes: keyframeTimes,
        maxThumbnails: maxThumbnails
    ) {
        allThumbnails.append(contentsOf: batch)
    }
    
    return allThumbnails.sorted { $0.time < $1.time }
}

