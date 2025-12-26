//
//  GenerateKeyframeThumbnails.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-09.
//

import AVFoundation
import AppKit

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
            // Optimize size: thumbnails are displayed at 56x36, so we don't need huge images
            // Using 112x72 (2x for retina) is sufficient and much faster
            gen.maximumSize = CGSize(width: 112, height: 72)

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
            // Use atomic cancellation flag that can be checked in callback
            let cancellationLock = NSLock()
            var cancelled = false
            
            let lock = NSLock()
            var pendingThumbnails: [KeyframeThumbnail] = []
            var completed = 0
            let total = times.count
            var finished = false

            gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
                // Check cancellation flag
                cancellationLock.lock()
                let isCancelled = cancelled
                cancellationLock.unlock()
                
                if isCancelled {
                    return
                }
                
                lock.lock()
                defer { lock.unlock() }
                
                // Check if we're already finished
                if finished {
                    return
                }

                completed += 1

                if result == .succeeded, let cgImage {
                    let img = NSImage(cgImage: cgImage, size: .zero)
                    let thumbnail = KeyframeThumbnail(time: requestedTime.seconds, image: img)
                    pendingThumbnails.append(thumbnail)
                    
                    // Emit batch when we have enough or when we're done
                    if pendingThumbnails.count >= batchSize || completed == total {
                        let batch = pendingThumbnails.sorted { $0.time < $1.time }
                        pendingThumbnails.removeAll(keepingCapacity: true)
                        continuation.yield(batch)
                    }
                }

                if completed == total {
                    finished = true
                    // Emit any remaining thumbnails
                    if !pendingThumbnails.isEmpty {
                        let batch = pendingThumbnails.sorted { $0.time < $1.time }
                        continuation.yield(batch)
                    }
                    continuation.finish()
                }
            }
            
            // Monitor for cancellation and cancel generator if needed
            // This runs as part of the main task, so it will be cancelled when the task is cancelled
            while !Task.isCancelled {
                lock.lock()
                let isDone = finished || completed >= total
                lock.unlock()
                
                if isDone {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1 seconds
            }
            
            // If cancelled, stop the generator
            if Task.isCancelled {
                cancellationLock.lock()
                cancelled = true
                cancellationLock.unlock()
                gen.cancelAllCGImageGeneration()
                lock.lock()
                finished = true
                lock.unlock()
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

