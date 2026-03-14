import AVFoundation
import AppKit
import CoreImage
import os

/// Binary search for nearest value in a sorted array of Doubles.
/// - Complexity: O(log n)
private func findNearestTime(in sortedTimes: [Double], target: Double) -> Double? {
    guard !sortedTimes.isEmpty else { return nil }

    var low = 0
    var high = sortedTimes.count - 1

    while low < high {
        let mid = low + (high - low) / 2
        if sortedTimes[mid] < target {
            low = mid + 1
        } else {
            high = mid
        }
    }

    // low is the first element >= target. Check if previous is closer.
    if low > 0 {
        let distCurrent = abs(sortedTimes[low] - target)
        let distPrev = abs(sortedTimes[low - 1] - target)
        return distPrev <= distCurrent ? sortedTimes[low - 1] : sortedTimes[low]
    }
    return sortedTimes[low]
}

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
public func GenerateKeyframeThumbnailsStream(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150,  // Reasonable limit for smooth scrolling
    batchSize: Int = 10,  // Generate thumbnails in batches
    thumbnailSize: CGSize = CGSize(width: 192, height: 120)  // Thumbnail size
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
                chosen = keyframeTimes.sorted()
            } else {
                // Sort once for binary search
                let sortedKeyframeTimes = keyframeTimes.sorted()
                var selectedTimes: [Double] = []
                selectedTimes.reserveCapacity(maxThumbnails)

                let interval = duration / Double(maxThumbnails - 1)

                for i in 0..<maxThumbnails {
                    let targetTime = Double(i) * interval
                    // Use binary search to find nearest keyframe — O(log n) instead of O(n)
                    let nearest = findNearestTime(in: sortedKeyframeTimes, target: targetTime)
                    if let nearest {
                        if selectedTimes.isEmpty || abs(selectedTimes.last! - nearest) > 0.001 {
                            selectedTimes.append(nearest)
                        }
                    }
                }

                if let first = sortedKeyframeTimes.first, !selectedTimes.contains(where: { abs($0 - first) < 0.001 }) {
                    selectedTimes.insert(first, at: 0)
                }
                if let last = sortedKeyframeTimes.last, !selectedTimes.contains(where: { abs($0 - last) < 0.001 }) {
                    selectedTimes.append(last)
                }

                chosen = selectedTimes.sorted()
            }

            // Simple AVAssetImageGenerator approach
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = thumbnailSize
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
                    var batch: [KeyframeThumbnail]?
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
                try? await Task.sleep(for: .milliseconds(100))
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
public func GenerateKeyframeThumbnails(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150,  // Reasonable limit for smooth scrolling
    thumbnailSize: CGSize = CGSize(width: 192, height: 120)  // Thumbnail size
) async -> [KeyframeThumbnail] {
    var allThumbnails: [KeyframeThumbnail] = []

    for await batch in GenerateKeyframeThumbnailsStream(
        asset: asset,
        keyframeTimes: keyframeTimes,
        maxThumbnails: maxThumbnails,
        thumbnailSize: thumbnailSize
    ) {
        allThumbnails.append(contentsOf: batch)
    }

    return allThumbnails.sorted { $0.time < $1.time }
}
