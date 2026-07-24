import AVFoundation
import CoreMedia

/// Extracts bitrate samples efficiently using AVSampleCursor when possible,
/// falling back to AVAssetReader.
/// Routes to format-specific extractors based on detected container format.
public func extractBitratesFast(
    asset: AVAsset,
    options: FrameSamplingOptions
) -> AsyncStream<FrameAnalysisUpdate> {

    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

            guard let videoTrack = await AVAssetLoader.firstTrack(of: asset, mediaType: .video) else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            let durationSeconds = await AVAssetLoader.durationSeconds(of: asset)
            let nominalFrameRate = await AVAssetLoader.nominalFrameRate(of: videoTrack)

            guard durationSeconds > 0 else {
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
                    let formatDescriptions = await AVAssetLoader.formatDescriptions(of: videoTrack)
                    if !formatDescriptions.isEmpty {

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

@inline(__always)
func appendBitrateSampleRespectingLimit(
    _ sample: BitrateSample,
    to pending: inout [BitrateSample],
    totalEmitted: inout Int,
    maxSamples: Int
) -> Bool {
    guard totalEmitted < maxSamples else { return false }
    pending.append(sample)
    totalEmitted += 1
    return true
}
