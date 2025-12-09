//
//  KeyframeMarker.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//


import AVFoundation
import CoreMedia
import AppKit

struct KeyframeMarker: Identifiable {
    let id = UUID()
    let time: Double
}

struct KeyframeThumbnail: Identifiable {
    let id = UUID()
    let time: Double
    let image: NSImage
}

func extractKeyframes(
    asset: AVAsset,
    maxKeyframes: Int = 20_000,           // safety cap
    minSpacingSeconds: Double = 0.0       // optional downsample to avoid “solid line”
) async -> [KeyframeMarker] {

    // Load the video track
    let tracks = try? await asset.loadTracks(withMediaType: .video)
    guard let track = tracks?.first else { return [] }

    do {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)

        guard reader.startReading() else { return [] }

        var markers: [KeyframeMarker] = []
        markers.reserveCapacity(2048)

        var lastAccepted: Double? = nil

        while let sbuf = output.copyNextSampleBuffer() {
            let t = CMSampleBufferGetPresentationTimeStamp(sbuf).seconds

            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: false),
               CFArrayGetCount(attachments) > 0,
               let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self) as? [CFString: Any]
            {
                // If NotSync is missing or false -> sync sample (keyframe)
                let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
                let isKeyframe = !notSync

                if isKeyframe {
                    if let last = lastAccepted, minSpacingSeconds > 0, (t - last) < minSpacingSeconds {
                        continue
                    }
                    markers.append(KeyframeMarker(time: t))
                    lastAccepted = t
                    if markers.count >= maxKeyframes { break }
                }
            }
        }

        return markers
    } catch {
        return []
    }
}
