import AVFoundation
import CoreMedia

public enum AVAssetLoader {
    public static func duration(of asset: AVAsset) async -> CMTime {
        (try? await asset.load(.duration)) ?? .zero
    }

    public static func durationSeconds(of asset: AVAsset) async -> Double {
        let cm = await duration(of: asset)
        let seconds = cm.seconds
        return seconds.isFinite ? seconds : 0
    }

    public static func tracks(of asset: AVAsset, mediaType: AVMediaType) async -> [AVAssetTrack] {
        (try? await asset.loadTracks(withMediaType: mediaType)) ?? []
    }

    public static func firstTrack(of asset: AVAsset, mediaType: AVMediaType) async -> AVAssetTrack? {
        await tracks(of: asset, mediaType: mediaType).first
    }

    public static func nominalFrameRate(of track: AVAssetTrack, defaultValue: Float = 30.0) async -> Float {
        let rate = (try? await track.load(.nominalFrameRate)) ?? 0
        return rate > 0 ? rate : defaultValue
    }

    public static func estimatedDataRate(of track: AVAssetTrack) async -> Float {
        (try? await track.load(.estimatedDataRate)) ?? 0
    }

    public static func formatDescriptions(of track: AVAssetTrack) async -> [CMFormatDescription] {
        (try? await track.load(.formatDescriptions)) ?? []
    }

    public static func firstFormatDescription(of track: AVAssetTrack) async -> CMFormatDescription? {
        await formatDescriptions(of: track).first
    }
}
