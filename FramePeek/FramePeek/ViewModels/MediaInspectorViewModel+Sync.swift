import Foundation
import AVFoundation
import FramePeekCore

extension FramePeekViewModel {
    /// Starts audio/video sync analysis when audio tracks are detected
    func startSyncAnalysis(asset: AVAsset, audioTracks: [AudioTrackInfo]) {
        guard !audioTracks.isEmpty, let url = currentVideoURL else { return }

        syncTask?.cancel()

        isAnalyzingSync = true
        syncAnalysisResult = nil
        frameTimingSamples = []

        let assetForSync = AVURLAsset(url: url)

        syncTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            for await update in analyzeSyncStream(asset: assetForSync, maxChartSamples: 500) {
                if Task.isCancelled { break }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if let batch = update.frameTimingSamples {
                        self.frameTimingSamples = batch
                    }
                    if let result = update.result {
                        self.syncAnalysisResult = result
                    }
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isAnalyzingSync = false
                self.syncTask = nil
            }
        }
    }

    /// Cancels sync analysis
    func cancelSyncAnalysis() {
        syncTask?.cancel()
        syncTask = nil
        isAnalyzingSync = false
    }
}
