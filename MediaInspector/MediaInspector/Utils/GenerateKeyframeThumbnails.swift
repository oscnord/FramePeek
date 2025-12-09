//
//  GenerateKeyframeThumbnails.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//

import AVFoundation
import AppKit

func GenerateKeyframeThumbnails(
    asset: AVAsset,
    keyframeTimes: [Double],
    maxThumbnails: Int = 90,
    thumbHeight: CGFloat = 38
) async -> [KeyframeThumbnail] {

    guard !keyframeTimes.isEmpty else { return [] }

    // Downsample keyframe times evenly to avoid generating thousands of images
    let step = max(1, keyframeTimes.count / maxThumbnails)
    let chosen: [Double] = keyframeTimes.enumerated().compactMap { idx, t in
        (idx % step == 0) ? t : nil
    }.prefix(maxThumbnails).map { $0 }

    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: thumbHeight * 2.2, height: thumbHeight)

    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero

    let times = chosen.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }

    return await withCheckedContinuation { cont in
        let lock = NSLock()
        var out: [KeyframeThumbnail] = []
        out.reserveCapacity(times.count)

        var completed = 0
        let total = times.count

        gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
            lock.lock()
            defer { lock.unlock() }

            completed += 1

            if result == .succeeded, let cgImage {
                let img = NSImage(cgImage: cgImage, size: .zero)
                out.append(KeyframeThumbnail(time: requestedTime.seconds, image: img))
            }

            if completed == total {
                cont.resume(returning: out.sorted { $0.time < $1.time })
            }
        }
    }
}
