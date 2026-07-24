import AVFoundation
import CoreMedia

/// Extracts bitrate from MPEG-TS files with optional TS packet overhead accounting
public func extractTS(
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

    var config = BucketEmissionConfig(estimatedFPS: estimatedFPS, options: options)
    if options.accountTSOverhead && options.formatAccuracyMode != .performance {
        // 188-byte TS packets carry 184 payload bytes; subtract the estimated
        // 4-byte-per-packet header share from each bucket
        config.adjustBitrate = { bitrate, totalBytes, duration in
            let estimatedPackets = Double(totalBytes) / 184.0
            let overheadBits = estimatedPackets * 4.0 * 8.0
            return max(0, bitrate - overheadBits / duration)
        }
    }

    emitBucketedBitrates(
        allSamples: allSamples,
        config: config,
        continuation: continuation
    )
}
