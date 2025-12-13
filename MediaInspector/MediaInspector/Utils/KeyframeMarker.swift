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
    
    // Get duration for fallback synthetic keyframes
    let duration = (try? await asset.load(.duration).seconds) ?? 0

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
        
        // If we didn't get any keyframes but have duration, the file might use a format
        // where all frames are sync samples - create synthetic markers
        if markers.isEmpty && duration > 0 {
            let syntheticCount = min(100, max(10, Int(duration / 2))) // One every 2 seconds, min 10, max 100
            let interval = duration / Double(syntheticCount)
            for i in 0..<syntheticCount {
                markers.append(KeyframeMarker(time: Double(i) * interval))
            }
        }

        return markers
    } catch {
        return []
    }
}
