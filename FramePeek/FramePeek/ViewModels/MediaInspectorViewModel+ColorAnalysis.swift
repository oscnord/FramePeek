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
        
        colorAnalysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            for await batch in analyzeColor(asset: assetForColor, sampleInterval: 1.0, maxSamples: 1000) {
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
