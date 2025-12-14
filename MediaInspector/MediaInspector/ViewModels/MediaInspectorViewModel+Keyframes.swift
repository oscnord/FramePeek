//
//  MediaInspectorViewModel+Keyframes.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation

extension MediaInspectorViewModel {
    /// Cancels keyframe extraction but preserves already-loaded keyframes
    /// Thumbnail generation continues for already-loaded keyframes
    func cancelKeyframeExtraction() {
        // Cancel both keyframe extraction and thumbnail generation
        keyframeTask?.cancel()
        thumbnailTask?.cancel()
        isExtractingKeyframes = false
        isGeneratingThumbnails = false
        keyframeExtractionProgress = nil
        
        // Note: keyframes and keyframeThumbs arrays are preserved
    }
    
    func startKeyframeExtraction(asset: AVAsset) {
        // Separate keyframe extraction task - runs in parallel with thumbnail generation
        keyframeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.isExtractingKeyframes = true
                self.keyframeExtractionProgress = "Loading video track..."
            }

            let duration = (try? await asset.load(.duration).seconds) ?? 0
            
            await MainActor.run {
                self.durationSeconds = duration
                self.keyframeExtractionProgress = "Extracting keyframes..."
            }
            
            // Stream keyframes progressively as they're found
            // Extract ALL keyframes for the timeline (no limit)
            // Don't accumulate in memory - just update UI progressively
            var pendingBatches: [KeyframeMarker] = []
            pendingBatches.reserveCapacity(100) // Batch UI updates
            
            for await keyframeBatch in extractKeyframesStream(
                asset: asset,
                maxKeyframes: 50_000,  // High limit, but extract all keyframes
                minSpacingSeconds: 0.0,  // No minimum spacing - get all keyframes
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.keyframeExtractionProgress = progress
                    }
                }
            ) {
                if Task.isCancelled { break }
                
                pendingBatches.append(contentsOf: keyframeBatch)
                
                // Batch UI updates to reduce MainActor blocking
                // Update every 100 keyframes or when we have a large batch
                if pendingBatches.count >= 100 {
                    let toAppend = pendingBatches
                    pendingBatches.removeAll(keepingCapacity: true)
                    await MainActor.run {
                        self.keyframes.append(contentsOf: toAppend)
                    }
                }
            }
            
            // Append any remaining keyframes
            if !pendingBatches.isEmpty {
                await MainActor.run {
                    self.keyframes.append(contentsOf: pendingBatches)
                }
            }
            
            // Finalize keyframe extraction state
            await MainActor.run {
                self.isExtractingKeyframes = false
                self.keyframeExtractionProgress = nil
            }
        }
    }
}

