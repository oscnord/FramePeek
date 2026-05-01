import Foundation
import AVFoundation
import CoreMedia

// MARK: - Audio Info Loading

/// Loads audio track information from an AVAsset
/// - Parameter asset: The AVAsset to analyze
/// - Returns: Array of AudioTrackInfo for each audio track
public func loadAudioInfo(asset: AVAsset) async -> [AudioTrackInfo] {
    var result: [AudioTrackInfo] = []

    let tracks = await AVAssetLoader.tracks(of: asset, mediaType: .audio)

    for (idx, track) in tracks.enumerated() {
        let index = idx + 1

        var codec = "Unknown"
        var channels = 0
        var sampleRateHz: Double = 0

        if let formatDesc = await AVAssetLoader.firstFormatDescription(of: track) {
            let codecFourCC = CMFormatDescriptionGetMediaSubType(formatDesc)
            codec = fourCCToString(codecFourCC)

            // Check if it's an audio format description by trying to get the stream basic description
            if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc as CMAudioFormatDescription) {
                let asbd = asbdPtr.pointee
                channels = Int(asbd.mChannelsPerFrame)
                sampleRateHz = asbd.mSampleRate
            }
        }

        let bitrateBps = await AVAssetLoader.estimatedDataRate(of: track)
        let bitrateKbps: Float? = bitrateBps > 0 ? bitrateBps / 1000.0 : nil
        let languageCode = try? await track.load(.languageCode)

        result.append(
            AudioTrackInfo(
                index: index,
                codec: codec,
                codecDisplayName: audioCodecName(codec),
                channels: channels,
                channelLayout: channelLayoutDescription(channels: channels),
                sampleRateHz: sampleRateHz,
                bitrateKbps: bitrateKbps,
                languageCode: languageCode
            )
        )
    }

    return result
}
