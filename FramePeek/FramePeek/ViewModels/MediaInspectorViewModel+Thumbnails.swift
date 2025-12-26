//
//  FramePeekViewModel+Thumbnails.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation

extension FramePeekViewModel {
    /// Cancels only thumbnail generation
    func cancelThumbnailGeneration() {
        thumbnailTask?.cancel()
        isGeneratingThumbnails = false
    }
    
    func startThumbnailGeneration(asset: AVAsset) {
        // Start thumbnail generation in parallel - don't wait for keyframes
        // Use evenly distributed times based on duration
        thumbnailTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            
            guard duration > 0 else {
                await MainActor.run {
                    self.isGeneratingThumbnails = false
                }
                return
            }
            
            await MainActor.run {
                self.isGeneratingThumbnails = true
            }
            
            // Start thumbnail generation immediately with evenly distributed times
            // This will snap to nearest frames (not necessarily keyframes)
            await self.startThumbnailGenerationFromDuration(
                asset: asset,
                duration: duration,
                maxThumbnails: 200
            )
        }
    }
    
    /// Starts thumbnail generation from duration - generates evenly distributed times
    /// This runs in parallel with keyframe extraction
    private func startThumbnailGenerationFromDuration(
        asset: AVAsset,
        duration: Double,
        maxThumbnails: Int
    ) async {
        // Generate evenly distributed target times across the video
        var targetTimes: [Double] = []
        targetTimes.reserveCapacity(maxThumbnails)
        let interval = duration / Double(maxThumbnails - 1)
        for i in 0..<maxThumbnails {
            targetTimes.append(Double(i) * interval)
        }
        
        // Guard against empty selection
        guard !targetTimes.isEmpty else {
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
            return
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            for await thumbnailBatch in GenerateKeyframeThumbnailsStream(
                asset: asset,
                keyframeTimes: targetTimes,  // Use target times directly - generator will find nearest frame
                maxThumbnails: targetTimes.count,
                batchSize: 10
            ) {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.keyframeThumbs.append(contentsOf: thumbnailBatch)
                    self.keyframeThumbs.sort { $0.time < $1.time }
                }
            }
            
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
        }
        
        await MainActor.run {
            self.thumbnailTask = task
        }
    }
    
    /// Starts thumbnail generation evenly distributed across video duration
    /// Uses actual keyframe times (for when we have all keyframes)
    private func startThumbnailGenerationEvenly(
        asset: AVAsset,
        duration: Double,
        allKeyframeTimes: [Double],
        maxThumbnails: Int
    ) async {
        // Guard against empty keyframes
        guard !allKeyframeTimes.isEmpty else {
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
            return
        }
        
        // Select keyframe times evenly distributed across the video
        let selectedTimes: [Double]
        
        if allKeyframeTimes.count <= maxThumbnails {
            // Use all keyframes if we have fewer than max
            selectedTimes = allKeyframeTimes.sorted()
        } else {
            // Distribute evenly across the video duration, snapping to nearest keyframes
            var selected: [Double] = []
            selected.reserveCapacity(maxThumbnails)
            
            let sortedKeyframes = allKeyframeTimes.sorted()
            let interval = duration / Double(maxThumbnails - 1)
            
            for i in 0..<maxThumbnails {
                let targetTime = Double(i) * interval
                
                // Find nearest keyframe to this target time using binary search for efficiency
                var bestTime: Double?
                var bestDistance = Double.greatestFiniteMagnitude
                
                for keyframeTime in sortedKeyframes {
                    let distance = abs(keyframeTime - targetTime)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestTime = keyframeTime
                    } else {
                        // Since sorted, we can break early
                        break
                    }
                }
                
                if let nearest = bestTime {
                    // Avoid duplicates
                    if selected.isEmpty || abs(selected.last! - nearest) > 0.001 {
                        selected.append(nearest)
                    }
                }
            }
            
            // Ensure first and last keyframes are included
            if let first = sortedKeyframes.first, !selected.contains(where: { abs($0 - first) < 0.001 }) {
                selected.insert(first, at: 0)
            }
            if let last = sortedKeyframes.last, !selected.contains(where: { abs($0 - last) < 0.001 }) {
                selected.append(last)
            }
            
            selectedTimes = selected.sorted()
        }
        
        // Guard against empty selection
        guard !selectedTimes.isEmpty else {
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
            return
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            for await thumbnailBatch in GenerateKeyframeThumbnailsStream(
                asset: asset,
                keyframeTimes: selectedTimes,
                maxThumbnails: selectedTimes.count,
                batchSize: 10
            ) {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.keyframeThumbs.append(contentsOf: thumbnailBatch)
                    self.keyframeThumbs.sort { $0.time < $1.time }
                }
            }
            
            await MainActor.run {
                self.isGeneratingThumbnails = false
            }
        }
        
        await MainActor.run {
            self.thumbnailTask = task
        }
    }
}

