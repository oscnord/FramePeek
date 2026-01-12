import Foundation
import AVFoundation

extension FramePeekViewModel {
    /// Starts waveform extraction for expanded audio tracks
    func startWaveformExtraction(asset: AVAsset, audioTracks: [AudioTrackInfo], duration: Double) {
        guard !audioTracks.isEmpty, let url = currentVideoURL else { return }
        
        let expandedTracks = audioTracks.filter { expandedWaveformTracks.contains($0.index) }
        guard !expandedTracks.isEmpty else { return }
        
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
                    
                    let samples = await extractWaveform(
                        asset: assetForWaveform,
                        audioTrack: audioTrack,
                        durationSeconds: duration,
                        maxSamples: 2000
                    )
                    
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.waveformData[trackIndex] = samples
                        }
                        self.waveformTasks.removeValue(forKey: trackIndex)
                        
                        // Check if all extractions are complete
                        if self.waveformTasks.isEmpty {
                            self.isExtractingWaveforms = false
                        }
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
    func extractWaveformForTrack(trackIndex: Int, asset: AVAsset, audioTrack: AVAssetTrack, duration: Double) {
        // Skip if already extracted or already extracting
        if waveformData[trackIndex] != nil || waveformTasks[trackIndex] != nil {
            return
        }
        
        isExtractingWaveforms = true
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let samples = await extractWaveform(
                asset: asset,
                audioTrack: audioTrack,
                durationSeconds: duration,
                maxSamples: 2000
            )
            
            await MainActor.run {
                if !Task.isCancelled {
                    self.waveformData[trackIndex] = samples
                }
                self.waveformTasks.removeValue(forKey: trackIndex)
                
                // Check if all extractions are complete
                if self.waveformTasks.isEmpty {
                    self.isExtractingWaveforms = false
                }
            }
        }
        
        waveformTasks[trackIndex] = task
    }
}

