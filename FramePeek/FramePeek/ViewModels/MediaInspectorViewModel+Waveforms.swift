import Foundation
import AVFoundation
import FramePeekCore

extension FramePeekViewModel {
    /// Starts waveform extraction for expanded audio tracks
    /// - Parameter forceRefresh: If true, bypasses cache and extracts fresh data
    func startWaveformExtraction(asset: AVAsset, audioTracks: [AudioTrackInfo], duration: Double, forceRefresh: Bool = false) {
        guard !audioTracks.isEmpty, let url = currentVideoURL else { return }

        let expandedTracks = audioTracks.filter { expandedWaveformTracks.contains($0.index) }
        guard !expandedTracks.isEmpty else { return }

        // Reset cache indicator
        waveformLoadedFromCache = false
        isExtractingWaveforms = true

        // Extract waveforms for all expanded tracks in parallel
        for trackInfo in expandedTracks {
            // Skip if already extracted or already extracting
            if waveformData[trackInfo.index] != nil || waveformTasks[trackInfo.index] != nil {
                continue
            }

            let trackIndex = trackInfo.index
            let assetForWaveform = AVURLAsset(url: url)

            // Create extraction task
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }

                if Task.isCancelled { return }
                
                // Check cache first (unless force refresh) - only for first track
                if !forceRefresh && trackIndex == 1 {
                    if let cached = await CacheManager.shared.loadWaveformCache(for: url) {
                        await MainActor.run {
                            self.waveformData[trackIndex] = cached.samples
                            self.waveformLoadedFromCache = true
                            self.waveformTasks.removeValue(forKey: trackIndex)
                            
                            // If partial cache, we could continue extraction, but for simplicity
                            // we'll just use the cached data as-is
                            if self.waveformTasks.isEmpty {
                                self.isExtractingWaveforms = false
                            }
                        }
                        
                        // If not partial, we're done
                        if !cached.isPartial {
                            return
                        }
                        // If partial, continue with extraction below
                    }
                }

                do {
                    let tracks = try await assetForWaveform.loadTracks(withMediaType: .audio)
                    guard let audioTrack = tracks.first(where: { track in
                        // Match track by index (tracks are 0-indexed, AudioTrackInfo.index is 1-indexed)
                        let trackIndexInArray = tracks.firstIndex(of: track) ?? -1
                        return trackIndexInArray + 1 == trackIndex
                    }) else {
                        await MainActor.run {
                            self.waveformTasks.removeValue(forKey: trackIndex)
                            if self.waveformTasks.isEmpty {
                                self.isExtractingWaveforms = false
                            }
                        }
                        return
                    }

                    var accumulatedSamples: [WaveformSample] = []

                    // Use fast waveform extraction (8kHz sample rate with skipping)
                    for await update in extractWaveformFast(
                        asset: assetForWaveform,
                        audioTrack: audioTrack,
                        durationSeconds: duration,
                        maxSamples: 2000
                    ) {
                        if Task.isCancelled { break }

                        // Accumulate samples progressively
                        accumulatedSamples.append(contentsOf: update.appendedSamples)

                        // Update UI progressively - create a copy to avoid concurrency issues
                        let samplesCopy = accumulatedSamples
                        await MainActor.run {
                            if !Task.isCancelled {
                                self.waveformData[trackIndex] = samplesCopy
                                self.waveformLoadedFromCache = false  // No longer from cache
                            }
                        }

                        if update.isFinished {
                            break
                        }
                    }

                    // Final update - create a copy to avoid concurrency issues
                    let finalSamples = accumulatedSamples
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.waveformData[trackIndex] = finalSamples
                        }
                        self.waveformTasks.removeValue(forKey: trackIndex)

                        // Check if all extractions are complete
                        if self.waveformTasks.isEmpty {
                            self.isExtractingWaveforms = false
                        }
                    }
                    
                    // Save to cache (only for first track)
                    if trackIndex == 1 && !finalSamples.isEmpty {
                        await CacheManager.shared.saveWaveformCache(
                            for: url,
                            samples: finalSamples,
                            isPartial: false,
                            partialDurationSeconds: nil
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.waveformTasks.removeValue(forKey: trackIndex)
                        if self.waveformTasks.isEmpty {
                            self.isExtractingWaveforms = false
                        }
                    }
                }
            }

            // Store task reference
            waveformTasks[trackIndex] = task
        }

        // If no tracks to extract, mark as complete
        if expandedTracks.allSatisfy({ waveformData[$0.index] != nil || waveformTasks[$0.index] != nil }) {
            // All tracks are either extracted or extracting
        } else if waveformTasks.isEmpty {
            isExtractingWaveforms = false
        }
    }

    /// Extracts waveform for a specific track on-demand (when track is expanded)
    /// - Parameter forceRefresh: If true, bypasses cache and extracts fresh data
    func extractWaveformForTrack(trackIndex: Int, asset: AVAsset, audioTrack: AVAssetTrack, duration: Double, forceRefresh: Bool = false) {
        // Skip if already extracted or already extracting (unless force refresh)
        if !forceRefresh && (waveformData[trackIndex] != nil || waveformTasks[trackIndex] != nil) {
            return
        }
        
        // If force refresh, clear existing data
        if forceRefresh {
            waveformData[trackIndex] = nil
            waveformTasks[trackIndex]?.cancel()
            waveformTasks[trackIndex] = nil
        }

        // Reset cache indicator
        waveformLoadedFromCache = false
        isExtractingWaveforms = true
        
        guard let url = currentVideoURL else {
            isExtractingWaveforms = false
            return
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            // Check cache first (unless force refresh) - only for first track
            if !forceRefresh && trackIndex == 1 {
                if let cached = await CacheManager.shared.loadWaveformCache(for: url) {
                    await MainActor.run {
                        self.waveformData[trackIndex] = cached.samples
                        self.waveformLoadedFromCache = true
                        self.waveformTasks.removeValue(forKey: trackIndex)
                        
                        if self.waveformTasks.isEmpty {
                            self.isExtractingWaveforms = false
                        }
                    }
                    
                    // If not partial, we're done
                    if !cached.isPartial {
                        return
                    }
                }
            }

            var accumulatedSamples: [WaveformSample] = []

            // Use fast waveform extraction (8kHz sample rate with skipping)
            for await update in extractWaveformFast(
                asset: asset,
                audioTrack: audioTrack,
                durationSeconds: duration,
                maxSamples: 2000
            ) {
                if Task.isCancelled { break }

                // Accumulate samples progressively
                accumulatedSamples.append(contentsOf: update.appendedSamples)

                // Update UI progressively - create a copy to avoid concurrency issues
                let samplesCopy = accumulatedSamples
                await MainActor.run {
                    if !Task.isCancelled {
                        self.waveformData[trackIndex] = samplesCopy
                        self.waveformLoadedFromCache = false  // No longer from cache
                    }
                }

                if update.isFinished {
                    break
                }
            }

            // Final update - create a copy to avoid concurrency issues
            let finalSamples = accumulatedSamples
            await MainActor.run {
                if !Task.isCancelled {
                    self.waveformData[trackIndex] = finalSamples
                }
                self.waveformTasks.removeValue(forKey: trackIndex)

                // Check if all extractions are complete
                if self.waveformTasks.isEmpty {
                    self.isExtractingWaveforms = false
                }
            }
            
            // Save to cache (only for first track)
            if trackIndex == 1 && !finalSamples.isEmpty {
                await CacheManager.shared.saveWaveformCache(
                    for: url,
                    samples: finalSamples,
                    isPartial: false,
                    partialDurationSeconds: nil
                )
            }
        }

        waveformTasks[trackIndex] = task
    }
    
    /// Force refresh all waveforms, bypassing cache
    func refreshWaveforms() {
        guard let url = currentVideoURL,
              let info = extendedInfo else { return }
        
        let audioTracks = info.audioTracks
        let asset = AVURLAsset(url: url)
        
        // Clear existing data
        waveformData.removeAll()
        for (_, task) in waveformTasks {
            task.cancel()
        }
        waveformTasks.removeAll()
        waveformLoadedFromCache = false
        
        // Re-extract with force refresh
        startWaveformExtraction(asset: asset, audioTracks: audioTracks, duration: durationSeconds, forceRefresh: true)
    }
}
