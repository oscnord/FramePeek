//
//  FastBitrateExtractor.swift
//  FramePeek
//
//  Efficient bitrate extraction using a rolling time-window over sample sizes.
//  Calculates bitrate using the standard formula: bitrate = (bytes * 8) / duration
//

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

            // Load video track
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Get duration and frame rate
            let duration = (try? await asset.load(.duration)) ?? .zero
            let durationSeconds = duration.seconds
            let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0

            guard durationSeconds.isFinite, durationSeconds > 0 else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            // Get URL from asset if it's an AVURLAsset
            let url: URL? = (asset as? AVURLAsset)?.url

            // Detect container format and route to appropriate extractor
            let format = await detectContainerFormat(asset: asset, url: url ?? URL(fileURLWithPath: "/"))
            
            // Route to format-specific extractor based on format and accuracy mode
            switch format {
            case .fragmentedMP4, .cmaf:
                // Use fragment-aware extraction for fragmented MP4 and CMAF
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
                // Use TS-specific extraction
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
                // Use standard extraction for other formats
                // Choose extraction method based on preferAccuracy option
                if options.preferAccuracy {
                    // Skip cursor path and go directly to reader for accuracy
                    await extractWithReader(
                        asset: asset,
                        videoTrack: videoTrack,
                        durationSeconds: durationSeconds,
                        nominalFrameRate: Double(nominalFrameRate),
                        options: options,
                        continuation: continuation
                    )
                } else {
                    // Try cursor first (fast, metadata-only). Fall back to reader if unavailable.
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

