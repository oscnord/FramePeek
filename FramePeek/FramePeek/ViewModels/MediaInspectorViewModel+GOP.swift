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
        
        // Trigger frame detail loading for the newly selected GOP
        Task {
            await loadFrameDetailsForSelectedGOP()
        }
    }

    func deselectGOP() {
        selectedGOPIndex = nil
        selectedGOPFrameDetails = nil
    }
    
    // MARK: - Frame Detail Loading
    
    /// Loads frame details for the currently selected GOP
    func loadFrameDetailsForSelectedGOP() async {
        guard let index = selectedGOPIndex,
              let analysis = gopAnalysis,
              index < analysis.segments.count else {
            selectedGOPFrameDetails = nil
            return
        }
        
        let segment = analysis.segments[index]
        
        // Check cache first
        if let cached = gopFrameDetailsCache[segment.id] {
            selectedGOPFrameDetails = cached
            return
        }
        
        // If segment already has frames populated, use them
        if let existingFrames = segment.frames, !existingFrames.isEmpty {
            gopFrameDetailsCache[segment.id] = existingFrames
            selectedGOPFrameDetails = existingFrames
            return
        }
        
        // Check codec support
        guard codecSupportsFrameTypes else {
            selectedGOPFrameDetails = nil
            return
        }
        
        // Need to extract frame details on demand
        guard let url = currentVideoURL else {
            selectedGOPFrameDetails = nil
            return
        }
        
        isLoadingGOPFrameDetails = true
        
        let asset = AVURLAsset(url: url)
        let timeRange = segment.startTime...segment.endTime
        
        let result = await Task.detached(priority: .userInitiated) {
            await FrameDetailExtractor.extractFrameDetails(from: asset, timeRange: timeRange)
        }.value
        
        // Update UI on main actor
        isLoadingGOPFrameDetails = false
        
        guard let result else {
            selectedGOPFrameDetails = nil
            return
        }
        
        guard result.codecSupportsFrameTypes else {
            codecSupportsFrameTypes = false
            selectedGOPFrameDetails = nil
            return
        }
        
        // Cache and set result
        gopFrameDetailsCache[segment.id] = result.frames
        
        // Only update if this GOP is still selected
        if selectedGOPIndex == index {
            selectedGOPFrameDetails = result.frames
        }
    }
    
    /// Preloads frame details for visible GOPs in the background
    func preloadFrameDetailsForVisibleGOPs(indices: [Int]) {
        // Cancel any existing preload task
        frameDetailPreloadTask?.cancel()
        
        guard codecSupportsFrameTypes,
              let analysis = gopAnalysis,
              let url = currentVideoURL else {
            return
        }
        
        // Filter to indices that aren't cached yet and aren't already preloading
        let indicesToPreload = indices.filter { index in
            guard index < analysis.segments.count else { return false }
            let segment = analysis.segments[index]
            return gopFrameDetailsCache[segment.id] == nil &&
                   !preloadingGOPIndices.contains(index) &&
                   (segment.frames == nil || segment.frames!.isEmpty)
        }
        
        // Limit batch size
        let batchIndices = Array(indicesToPreload.prefix(5))
        guard !batchIndices.isEmpty else { return }
        
        preloadingGOPIndices.formUnion(batchIndices)
        
        frameDetailPreloadTask = Task.detached(priority: .utility) { [weak self] in
            let asset = AVURLAsset(url: url)
            
            for index in batchIndices {
                if Task.isCancelled { break }
                
                guard let strongSelf = await MainActor.run(body: { self }),
                      let analysis = await strongSelf.gopAnalysis,
                      index < analysis.segments.count else {
                    continue
                }
                
                let segment = analysis.segments[index]
                
                // Skip if already cached
                if await strongSelf.gopFrameDetailsCache[segment.id] != nil {
                    await MainActor.run {
                        _ = strongSelf.preloadingGOPIndices.remove(index)
                    }
                    continue
                }
                
                let timeRange = segment.startTime...segment.endTime
                let result = await FrameDetailExtractor.extractFrameDetails(from: asset, timeRange: timeRange)
                
                if Task.isCancelled { break }
                
                await MainActor.run {
                    strongSelf.preloadingGOPIndices.remove(index)
                    
                    if let result, result.codecSupportsFrameTypes {
                        strongSelf.gopFrameDetailsCache[segment.id] = result.frames
                        
                        // If this is the currently selected GOP, update selectedGOPFrameDetails
                        if strongSelf.selectedGOPIndex == index {
                            strongSelf.selectedGOPFrameDetails = result.frames
                        }
                    } else if result != nil {
                        strongSelf.codecSupportsFrameTypes = false
                    }
                }
            }
        }
    }
    
    /// Clears the frame details cache (called when loading a new file)
    func clearGOPFrameDetailsCache() {
        frameDetailPreloadTask?.cancel()
        frameDetailPreloadTask = nil
        gopFrameDetailsCache.removeAll()
        selectedGOPFrameDetails = nil
        preloadingGOPIndices.removeAll()
        codecSupportsFrameTypes = true
    }

    private func startGOPAnalysis(asset: AVAsset, options: GOPOptions) {
        gopTask?.cancel()
        gopAnalysis = nil
        isAnalyzingGOP = true
        
        // Clear frame details cache when starting new analysis
        clearGOPFrameDetailsCache()
        
        // Check codec support upfront
        Task {
            let codecFourCC = await getVideoCodecFourCC(from: asset)
            codecSupportsFrameTypes = FrameDetailExtractor.codecSupportsFrameTypeDetection(codecFourCC)
        }

        gopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            var allSegments: [GOPSegment] = []
            allSegments.reserveCapacity(256)

            var latestStructureType: GOPStructureType = .unknown
            var latestRepresentativeGOP: GOPSegment?

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
    
    /// Gets the video codec FourCC from an asset
    private func getVideoCodecFourCC(from asset: AVAsset) async -> FourCharCode {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
              let formatDescription = formatDescriptions.first else {
            return 0
        }
        return CMFormatDescriptionGetMediaSubType(formatDescription)
    }
}
