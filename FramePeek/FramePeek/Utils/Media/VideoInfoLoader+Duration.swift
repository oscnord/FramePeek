import Foundation
import AVFoundation
import CoreMedia

public struct DurationInfo {
    public let duration: String
    public let durationFormatted: String
    public let durationSec: Double
    
    public init(duration: String, durationFormatted: String, durationSec: Double) {
        self.duration = duration
        self.durationFormatted = durationFormatted
        self.durationSec = durationSec
    }
}

public func extractDurationInfo(asset: AVAsset) async -> DurationInfo {
    var duration = "N/A"
    var durationFormatted = "N/A"
    var durationSec: Double = 0

    if let loadedDuration = try? await asset.load(.duration) {
        durationSec = CMTimeGetSeconds(loadedDuration)
        if durationSec > 0 {
            duration = String(format: "%.2f sec", durationSec)
            durationFormatted = formatDuration(seconds: durationSec)
        }
    }

    return DurationInfo(
        duration: duration,
        durationFormatted: durationFormatted,
        durationSec: durationSec
    )
}
