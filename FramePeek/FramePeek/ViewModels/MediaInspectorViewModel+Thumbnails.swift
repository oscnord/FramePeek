import Foundation
import AVFoundation
import FramePeekCore

extension FramePeekViewModel {
    /// Cancels only thumbnail generation
    func cancelThumbnailGeneration() {
        thumbnailTask?.cancel()
        isGeneratingThumbnails = false
    }

    func startThumbnailGeneration(asset: AVAsset) {
        // Start thumbnail generation in parallel - don't wait for keyframes
        // Use evenly distributed times based on duration
        let maxThumbnails = max(2, self.maxThumbnails)
        let thumbnailSize = self.thumbnailSize.cgSize

        // One task end to end: a nested task would detach from cancellation
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
                guard !Task.isCancelled else { return }
                self.isGeneratingThumbnails = true
            }

            // Evenly distributed target times; the generator snaps to nearest frames
            let interval = duration / Double(maxThumbnails - 1)
            var targetTimes: [Double] = []
            targetTimes.reserveCapacity(maxThumbnails)
            for i in 0..<maxThumbnails {
                targetTimes.append(Double(i) * interval)
            }

            var seenTimes = Set<Double>()
            for await thumbnailBatch in GenerateKeyframeThumbnailsStream(
                asset: asset,
                keyframeTimes: targetTimes,
                maxThumbnails: targetTimes.count,
                batchSize: 10,
                thumbnailSize: thumbnailSize
            ) {
                if Task.isCancelled { break }

                // Filter duplicates using O(1) Set lookup instead of contains(where:)
                let uniqueBatch = thumbnailBatch.filter { seenTimes.insert($0.time).inserted }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.keyframeThumbs.append(contentsOf: uniqueBatch)
                }
            }

            // Single sort after all batches complete
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.keyframeThumbs.sort { $0.time < $1.time }
                self.isGeneratingThumbnails = false
            }
        }
    }
}
