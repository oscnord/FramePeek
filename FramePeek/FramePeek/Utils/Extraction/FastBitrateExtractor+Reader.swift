import AVFoundation
import CoreMedia

// MARK: - Reader-based extraction (accurate sample sizes)

public func extractWithReader(
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

    let allSamples = await collectVideoSamples(
        reader: reader,
        output: output,
        estimatedCount: Int(durationSeconds * estimatedFPS)
    )

    emitBucketedBitrates(
        allSamples: allSamples,
        config: BucketEmissionConfig(estimatedFPS: estimatedFPS, options: options),
        continuation: continuation
    )
}
