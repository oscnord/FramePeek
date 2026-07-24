import Foundation
import AVFoundation
import FramePeekCore

extension FramePeekViewModel {
    /// Starts EBU R128 loudness measurement for the first audio track
    func startLoudnessAnalysis(asset: AVAsset, audioTracks: [AudioTrackInfo]) {
        guard !audioTracks.isEmpty, let url = currentVideoURL else { return }

        loudnessTask?.cancel()

        isAnalyzingLoudness = true
        loudnessResult = nil
        shortTermLoudness = []

        let assetForLoudness = AVURLAsset(url: url)

        loudnessTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            guard let audioTrack = try? await assetForLoudness.loadTracks(withMediaType: .audio).first else {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isAnalyzingLoudness = false
                }
                return
            }

            for await update in analyzeLoudness(asset: assetForLoudness, audioTrack: audioTrack) {
                if Task.isCancelled { break }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if !update.appendedShortTermSamples.isEmpty {
                        self.shortTermLoudness.append(contentsOf: update.appendedShortTermSamples)
                    }
                    if let result = update.result {
                        self.loudnessResult = result
                    }
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isAnalyzingLoudness = false
                self.loudnessTask = nil
            }
        }
    }

    func cancelLoudnessAnalysis() {
        loudnessTask?.cancel()
        loudnessTask = nil
        isAnalyzingLoudness = false
    }
}
