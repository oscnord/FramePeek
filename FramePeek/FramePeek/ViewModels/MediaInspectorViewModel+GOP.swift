import AVFoundation
import SwiftUI

extension FramePeekViewModel {
    func startGOPPreview(asset: AVAsset) {
        startGOPAnalysis(asset: asset, options: .preview(detectFixedStructure: true))
    }
    
    func analyzeGOPFullFile(detectFrameTypes: Bool = true) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .fullFile(detectFrameTypes: detectFrameTypes, detectFixedStructure: false))
    }
    
    func analyzeGOPFullFileOverride(detectFrameTypes: Bool = true) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .fullFile(detectFrameTypes: detectFrameTypes, detectFixedStructure: false))
    }
    
    func analyzeGOPWithFrameTypes() {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .fullFile(detectFrameTypes: true, detectFixedStructure: true))
    }
    
    func analyzeGOPTimeRange(_ range: ClosedRange<Double>, detectFrameTypes: Bool = true) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .timeRange(range, detectFrameTypes: detectFrameTypes))
    }
    
    func cancelGOPAnalysis() {
        gopTask?.cancel()
        gopTask = nil
        isAnalyzingGOP = false
    }
    
    func selectGOP(at index: Int) {
        selectedGOPIndex = index
    }
    
    func deselectGOP() {
        selectedGOPIndex = nil
    }
    
    private func startGOPAnalysis(asset: AVAsset, options: GOPOptions) {
        gopTask?.cancel()
        gopAnalysis = nil
        isAnalyzingGOP = true
        
        gopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            var allSegments: [GOPSegment] = []
            allSegments.reserveCapacity(256)
            
            var latestStructureType: GOPStructureType = .unknown
            var latestRepresentativeGOP: GOPSegment? = nil
            
            for await update in extractGOPSegments(asset: asset, options: options) {
                if Task.isCancelled { return }
                
                if !update.appendedSegments.isEmpty {
                    allSegments.append(contentsOf: update.appendedSegments)
                }
                
                latestStructureType = update.structureType
                if let repGOP = update.representativeGOP {
                    latestRepresentativeGOP = repGOP
                }
                
                let segmentsSnapshot = allSegments
                let isPreview = update.isPreview
                let scannedUntilSeconds = update.scannedUntilSeconds
                let isFinished = update.isFinished
                let structureType = latestStructureType
                let representativeGOP = latestRepresentativeGOP
                
                await MainActor.run {
                    self.gopAnalysis = GOPAnalysisResult(
                        segments: segmentsSnapshot,
                        isPreview: isPreview,
                        scannedUntilSeconds: scannedUntilSeconds,
                        isFinished: isFinished,
                        structureType: structureType,
                        representativeGOP: representativeGOP
                    )
                    
                    if isFinished {
                        self.isAnalyzingGOP = false
                    }
                }
                
                if isFinished { break }
            }
        }
    }
}
