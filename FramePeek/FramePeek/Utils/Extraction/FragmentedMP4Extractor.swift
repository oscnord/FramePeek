import AVFoundation
import CoreMedia

/// Extracts bitrate from fragmented MP4 (fMP4/CMAF) files.
/// Segment boundaries produce PTS gaps that must not skew FPS statistics.
public func extractFragmentedMP4(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    durationSeconds: Double,
    nominalFrameRate: Double,
    options: FrameSamplingOptions,
    continuation: AsyncStream<FrameAnalysisUpdate>.Continuation
) async {
    let finish = FrameAnalysisUpdate(appendedSamples: [], isFinished: true)

    guard let reader = try? AVAssetReader(asset: asset) else {
        continuation.yield(finish)
        continuation.finish()
        return
    }

    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    output.alwaysCopiesSampleData = false

    guard reader.canAdd(output) else {
        continuation.yield(finish)
        continuation.finish()
        return
    }
    reader.add(output)

    guard reader.startReading() else {
        continuation.yield(finish)
        continuation.finish()
        return
    }

    let estimatedFPS = nominalFrameRate > 0 ? nominalFrameRate : 30.0
    let defaultFrameDuration = 1.0 / estimatedFPS

    let allSamples = await collectVideoSamples(
        reader: reader,
        output: output,
        estimatedCount: Int(durationSeconds * estimatedFPS)
    )

    var config = BucketEmissionConfig(estimatedFPS: estimatedFPS, options: options)
    config.maxFPSStatInterval = defaultFrameDuration * 2.0

    emitBucketedBitrates(
        allSamples: allSamples,
        config: config,
        continuation: continuation
    )
}
