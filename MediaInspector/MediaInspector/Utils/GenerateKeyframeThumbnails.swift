//
//  GenerateKeyframeThumbnails.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//

import AVFoundation
import AppKit

func GenerateKeyframeThumbnails(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 150,  // Reasonable limit for smooth scrolling
    thumbHeight: CGFloat = 120
) async -> [KeyframeThumbnail] {

    guard !keyframeTimes.isEmpty else { return [] }
    
    // Get video duration
    let duration = (try? await asset.load(.duration).seconds) ?? 0
    guard duration > 0 else { return [] }
    
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
    gen.maximumSize = CGSize(width: thumbHeight * 2.2, height: thumbHeight)

    // Allow some tolerance for faster generation
    gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
    gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

    let times = chosen.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }

    return await withCheckedContinuation { cont in
        let lock = NSLock()
        var out: [KeyframeThumbnail] = []
        out.reserveCapacity(times.count)

        var completed = 0
        let total = times.count
        
        // Handle empty case
        guard total > 0 else {
            cont.resume(returning: [])
            return
        }

        gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
            lock.lock()
            defer { lock.unlock() }

            completed += 1

            if result == .succeeded, let cgImage {
                let img = NSImage(cgImage: cgImage, size: .zero)
                out.append(KeyframeThumbnail(time: requestedTime.seconds, image: img))
            }

            if completed == total {
                cont.resume(returning: out.sorted { $0.time < $1.time })
            }
        }
    }
}
