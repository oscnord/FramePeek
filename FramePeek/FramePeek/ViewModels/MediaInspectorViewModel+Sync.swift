import Foundation
import AVFoundation

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
            
            let result = await analyzeAudioVideoSync(asset: assetForSync)
            
            await MainActor.run {
                if !Task.isCancelled {
                    self.syncAnalysisResult = result
                }
            }
            
            for await batch in analyzeFrameTimingStream(asset: assetForSync, maxSamples: 500) {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    if !Task.isCancelled {
                        self.frameTimingSamples = batch
                    }
                }
            }
            
            await MainActor.run {
                if !Task.isCancelled {
                    self.isAnalyzingSync = false
                }
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
