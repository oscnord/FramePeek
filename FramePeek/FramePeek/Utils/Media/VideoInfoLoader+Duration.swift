//
//  VideoInfoLoader+Duration.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia

struct DurationInfo {
    let duration: String
    let durationFormatted: String
    let durationSec: Double
}

func extractDurationInfo(asset: AVAsset) async -> DurationInfo {
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


