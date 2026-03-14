import AVFoundation
import SwiftUI
import FramePeekCore

extension FramePeekViewModel {
    func startGOPPreview(asset: AVAsset, forceRefresh: Bool = false) {
        startGOPAnalysis(asset: asset, options: .preview(detectFixedStructure: true), forceRefresh: forceRefresh)
    }

    func analyzeGOPFullFile(detectFrameTypes: Bool = true, forceRefresh: Bool = false) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .fullFile(detectFrameTypes: detectFrameTypes, detectFixedStructure: false), forceRefresh: forceRefresh)
    }

    func analyzeGOPFullFileOverride(detectFrameTypes: Bool = true, forceRefresh: Bool = false) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .fullFile(detectFrameTypes: detectFrameTypes, detectFixedStructure: false), forceRefresh: forceRefresh)
    }

    func analyzeGOPWithFrameTypes(forceRefresh: Bool = false) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .fullFile(detectFrameTypes: true, detectFixedStructure: true), forceRefresh: forceRefresh)
    }

    func analyzeGOPTimeRange(_ range: ClosedRange<Double>, detectFrameTypes: Bool = true, forceRefresh: Bool = false) {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .timeRange(range, detectFrameTypes: detectFrameTypes), forceRefresh: forceRefresh)
    }

    func cancelGOPAnalysis() {
        gopTask?.cancel()
        gopTask = nil
        isAnalyzingGOP = false
    }
    
    /// Force refresh GOP analysis, bypassing cache
    func refreshGOPAnalysis() {
        guard let url = currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        startGOPAnalysis(asset: asset, options: .preview(detectFixedStructure: true), forceRefresh: true)
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
        if let cached = getCachedGOPFrameDetails(for: segment.id) {
            selectedGOPFrameDetails = cached
            return
        }

        // If segment already has frames populated, use them
        if let existingFrames = segment.frames, !existingFrames.isEmpty {
            cacheGOPFrameDetails(existingFrames, for: segment.id)
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
        cacheGOPFrameDetails(result.frames, for: segment.id)

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

        // Capture all needed MainActor state ONCE to avoid bouncing
        let cachedIds = Set(gopFrameDetailsCache.keys)
        let currentPreloading = preloadingGOPIndices

        // Filter to indices that aren't cached yet and aren't already preloading
        let indicesToPreload = indices.filter { index in
            guard index < analysis.segments.count else { return false }
            let segment = analysis.segments[index]
            return !cachedIds.contains(segment.id) &&
                   !currentPreloading.contains(index) &&
                   (segment.frames == nil || segment.frames!.isEmpty)
        }

        // Limit batch size
        let batchIndices = Array(indicesToPreload.prefix(5))
        guard !batchIndices.isEmpty else { return }

        preloadingGOPIndices.formUnion(batchIndices)

        // Capture segments info needed for background work
        let segmentInfos: [(index: Int, id: UUID, timeRange: ClosedRange<Double>)] = batchIndices.compactMap { index in
            guard index < analysis.segments.count else { return nil }
            let segment = analysis.segments[index]
            return (index, segment.id, segment.startTime...segment.endTime)
        }

        frameDetailPreloadTask = Task.detached(priority: .utility) { [weak self] in
            let asset = AVURLAsset(url: url)

            for info in segmentInfos {
                if Task.isCancelled { break }

                let result = await FrameDetailExtractor.extractFrameDetails(from: asset, timeRange: info.timeRange)

                if Task.isCancelled { break }

                // Single MainActor bounce per segment for the final UI update
                await MainActor.run {
                    guard let self else { return }
                    self.preloadingGOPIndices.remove(info.index)

                    if let result, result.codecSupportsFrameTypes {
                        self.cacheGOPFrameDetails(result.frames, for: info.id)

                        // If this is the currently selected GOP, update selectedGOPFrameDetails
                        if self.selectedGOPIndex == info.index {
                            self.selectedGOPFrameDetails = result.frames
                        }
                    } else if result != nil {
                        self.codecSupportsFrameTypes = false
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
        gopCacheAccessOrder.removeAll()
        selectedGOPFrameDetails = nil
        preloadingGOPIndices.removeAll()
        codecSupportsFrameTypes = true
    }

    private func startGOPAnalysis(asset: AVAsset, options: GOPOptions, forceRefresh: Bool = false) {
        gopTask?.cancel()
        // Don't clear gopAnalysis immediately - keep showing previous results until new data arrives
        // This prevents UI jumping when transitioning from preview to full analysis
        isAnalyzingGOP = true
        gopLoadedFromCache = false
        
        // Clear frame details cache when starting new analysis
        clearGOPFrameDetailsCache()
        
        // Check codec support upfront
        Task {
            let codecFourCC = await getVideoCodecFourCC(from: asset)
            codecSupportsFrameTypes = FrameDetailExtractor.codecSupportsFrameTypeDetection(codecFourCC)
        }
        
        guard let url = currentVideoURL else {
            isAnalyzingGOP = false
            return
        }

        gopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            // Determine if this is a full file request (no maxScanSeconds limit means full file)
            let isFullFileRequest = options.maxScanSeconds == nil
            
            // Check cache first (unless force refresh)
            if !forceRefresh {
                if let cached = await CacheManager.shared.loadGOPCache(for: url) {
                    // Skip cache if requesting full file but cache only has preview
                    let shouldSkipCache = isFullFileRequest && cached.isPreview
                    
                    if !shouldSkipCache {
                        let segments = await CacheManager.shared.convertCachedGOPSegments(cached.segments)
                        
                        // Get representative GOP from index
                        let representativeGOP: GOPSegment? = cached.representativeGOPIndex.flatMap { index in
                            index < segments.count ? segments[index] : nil
                        }
                        
                        await MainActor.run {
                            self.gopAnalysis = GOPAnalysisResult(
                                segments: segments,
                                isPreview: cached.isPreview,
                                scannedUntilSeconds: cached.scannedUntilSeconds,
                                isFinished: !cached.isPartial,
                                structureType: cached.structureType,
                                representativeGOP: representativeGOP
                            )
                            self.gopLoadedFromCache = true
                            
                            if !cached.isPartial {
                                self.isAnalyzingGOP = false
                            }
                        }
                        
                        // If not partial, we're done
                        if !cached.isPartial {
                            return
                        }
                        // If partial, continue with fresh analysis below
                    }
                }
            }

            var allSegments: [GOPSegment] = []
            allSegments.reserveCapacity(256)

            var latestStructureType: GOPStructureType = .unknown
            var latestRepresentativeGOP: GOPSegment?
            var latestRepresentativeGOPIndex: Int?
            var lastUIUpdate = ContinuousClock.now
            var pendingUIUpdate = false

            for await update in extractGOPSegments(asset: asset, options: options) {
                if Task.isCancelled { return }

                if !update.appendedSegments.isEmpty {
                    allSegments.append(contentsOf: update.appendedSegments)
                    pendingUIUpdate = true
                }

                latestStructureType = update.structureType
                if let repGOP = update.representativeGOP {
                    latestRepresentativeGOP = repGOP
                    // Find index of representative GOP
                    latestRepresentativeGOPIndex = allSegments.firstIndex(where: {
                        $0.startTime == repGOP.startTime && $0.endTime == repGOP.endTime
                    })
                }

                let isPreview = update.isPreview
                let scannedUntilSeconds = update.scannedUntilSeconds
                let isFinished = update.isFinished

                // Batch UI updates: push every 200ms or on finish
                let now = ContinuousClock.now
                let shouldUpdate = isFinished ||
                                   (pendingUIUpdate && now - lastUIUpdate >= .milliseconds(200))

                if shouldUpdate {
                    lastUIUpdate = now
                    pendingUIUpdate = false

                    let segmentsSnapshot = allSegments
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
                        self.gopLoadedFromCache = false  // No longer from cache

                        if isFinished {
                            self.isAnalyzingGOP = false
                        }
                    }
                }

                if isFinished {
                    // Save to cache when analysis completes
                    await CacheManager.shared.saveGOPCache(
                        for: url,
                        segments: allSegments,
                        isPartial: false,
                        partialDurationSeconds: nil,
                        isPreview: isPreview,
                        scannedUntilSeconds: scannedUntilSeconds,
                        structureType: latestStructureType,
                        representativeGOPIndex: latestRepresentativeGOPIndex
                    )
                    break
                }
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
