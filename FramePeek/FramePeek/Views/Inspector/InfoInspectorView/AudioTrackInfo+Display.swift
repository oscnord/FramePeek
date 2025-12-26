//
//  AudioTrackInfo+Display.swift
//  FramePeek
//

import Foundation

extension AudioTrackInfo {
    var displayString: String {
        let sr = sampleRateHz > 0
            ? String(format: "%.1f kHz", sampleRateHz / 1000.0)
            : "Unknown rate"

        let bitrate: String
        if let kbps = bitrateKbps, kbps > 0 {
            bitrate = String(format: "%.0f kb/s", kbps)
        } else {
            bitrate = "Unknown bitrate"
        }

        let lang = languageCode?.uppercased() ?? "N/A"
        return "\(codecDisplayName), \(channelLayout), \(sr), \(bitrate), lang \(lang)"
    }
}
