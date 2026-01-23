import AVFoundation
import CoreMedia

/// Extracts bitrate samples efficiently using AVSampleCursor when possible,
/// falling back to AVAssetReader.
/// Routes to format-specific extractors based on detected container format.
func extractBitratesFast(
    asset: AVAsset,
    options: FrameSamplingOptions
) -> AsyncStream<FrameAnalysisUpdate> {

    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            let duration = (try? await asset.load(.duration)) ?? .zero
            let durationSeconds = duration.seconds
            let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0

            guard durationSeconds.isFinite, durationSeconds > 0 else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            let url: URL? = (asset as? AVURLAsset)?.url

            let format = await detectContainerFormat(asset: asset, url: url ?? URL(fileURLWithPath: "/"))

            switch format {
            case .fragmentedMP4, .cmaf:
                await extractFragmentedMP4(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
                return

            case .mpegTS:
                await extractTS(
                    asset: asset,
                    videoTrack: videoTrack,
                    durationSeconds: durationSeconds,
                    nominalFrameRate: Double(nominalFrameRate),
                    options: options,
                    continuation: continuation
                )
                return

            default:
                if options.preferAccuracy {
                    await extractWithReader(
                        asset: asset,
                        videoTrack: videoTrack,
                        durationSeconds: durationSeconds,
                        nominalFrameRate: Double(nominalFrameRate),
                        options: options,
                        continuation: continuation
                    )
                } else {
                    if let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
                       !formatDescriptions.isEmpty {

                        let success = await extractWithCursor(
                            track: videoTrack,
                            durationSeconds: durationSeconds,
                            nominalFrameRate: Double(nominalFrameRate),
                            options: options,
                            continuation: continuation
                        )

                        if success { return }
                    }

                    await extractWithReader(
                        asset: asset,
                        videoTrack: videoTrack,
                        durationSeconds: durationSeconds,
                        nominalFrameRate: Double(nominalFrameRate),
                        options: options,
                        continuation: continuation
                    )
                }
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}
