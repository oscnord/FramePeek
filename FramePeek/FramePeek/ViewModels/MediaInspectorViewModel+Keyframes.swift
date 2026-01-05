import Foundation
import AVFoundation

extension FramePeekViewModel {
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
        // Capture settings values before entering detached task
        let maxKeyframes = self.maxKeyframes
        let minSpacingSeconds = self.keyframeMinSpacingSeconds
        
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
            pendingBatches.reserveCapacity(200) // Balanced batch size for UI updates
            
            for await keyframeBatch in extractKeyframesStream(
                asset: asset,
                maxKeyframes: maxKeyframes,
                minSpacingSeconds: minSpacingSeconds,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.keyframeExtractionProgress = progress
                    }
                }
            ) {
                if Task.isCancelled { break }
                
                pendingBatches.append(contentsOf: keyframeBatch)
                
                // Batch UI updates to reduce MainActor blocking
                // Update every 200 keyframes for good balance between performance and responsiveness
                if pendingBatches.count >= 200 {
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

