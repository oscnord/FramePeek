import Foundation
import AVFoundation

extension FramePeekViewModel {
    /// Starts color analysis (manual trigger, not automatic)
    func startColorAnalysis(asset: AVAsset) {
        guard let url = currentVideoURL else { return }

        colorAnalysisTask?.cancel()

        isAnalyzingColor = true
        colorSamples = []

        let assetForColor = AVURLAsset(url: url)

        // Load settings from UserDefaults
        let sampleInterval = UserDefaults.standard.double(forKey: "colorAnalysisSampleInterval")
        let maxSamples = UserDefaults.standard.integer(forKey: "colorAnalysisMaxSamples")
        let smoothingFactor = UserDefaults.standard.double(forKey: "colorAnalysisSmoothingFactor")

        // Use defaults if not set
        let effectiveInterval = sampleInterval > 0 ? sampleInterval : 1.0
        let effectiveMaxSamples = maxSamples > 0 ? maxSamples : 1000
        let effectiveSmoothing = smoothingFactor > 0 ? smoothingFactor : 0.3

        colorAnalysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            for await batch in analyzeColor(asset: assetForColor, sampleInterval: effectiveInterval, maxSamples: effectiveMaxSamples, smoothingFactor: effectiveSmoothing) {
                if Task.isCancelled { break }

                await MainActor.run {
                    if !Task.isCancelled {
                        self.colorSamples = batch
                    }
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.isAnalyzingColor = false
                }
                self.colorAnalysisTask = nil
            }
        }
    }

    /// Cancels color analysis
    func cancelColorAnalysis() {
        colorAnalysisTask?.cancel()
        colorAnalysisTask = nil
        isAnalyzingColor = false
    }
}
