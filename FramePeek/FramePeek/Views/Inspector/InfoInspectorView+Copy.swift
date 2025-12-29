//
//  InfoInspectorView+Copy.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension InfoInspectorView {
    // MARK: - Copy

    func copyAll(info: ExtendedVideoInfo) {
        let text = buildCopyText(info: info, includeAll: true)
        copyToPasteboard(text)
        showCopied("Copied all text")
    }

    func showCopied(_ message: String) {
        copiedBannerText = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedBannerText == message {
                copiedBannerText = nil
            }
        }
    }

    func copyToPasteboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    func buildCopyText(info: ExtendedVideoInfo, includeAll: Bool) -> String {
        var lines: [String] = []
        func kv(_ k: String, _ v: String?) { if let v, !v.isEmpty { lines.append("\(k): \(v)") } }

        lines.append("Media Inspector")
        lines.append("")

        lines.append("[File]")
        kv("Name", info.fileName)
        kv("Format", info.containerFormat)
        kv("Size", info.fileSize)
        kv("Overall Bitrate", info.overallBitrate)
        kv("Duration", info.duration)
        lines.append("")

        if includeAll, info.hasMetadata {
            lines.append("[Metadata]")
            kv("Created", info.creationDate)
            kv("Title", info.metadataTitle)
            kv("Artist", info.metadataArtist)
            kv("Encoder", info.metadataEncoder)
            if let d = info.metadataDescription { lines.append("Description: \(d)") }
            lines.append("")
        }

        lines.append("[Video]")
        kv("Resolution", info.resolution)
        kv("Nominal FPS", info.frameRate)
        kv("Frame Rate Mode", info.frameRateMode)
        kv("Codec", info.codec)
        kv("Profile", info.codecProfile)
        kv("Codec ID", info.codecIdRaw)
        kv("Video Bitrate", info.trackBitrate)
        kv("Max Bitrate", info.maxBitrate)
        kv("Min Bitrate", info.minBitrate)
        kv("Stream Size", info.videoStreamSize)
        kv("Bits/(Pixel*Frame)", info.bitsPerPixelFrame)
        if let deg = info.orientationDegrees { kv("Orientation", "\(deg)°") }
        kv("Pixel Aspect Ratio", info.pixelAspectRatio)
        kv("Clean Aperture", info.cleanAperture)
        kv("Scan Type", info.scanType)
        if let fps = viewModel.effectiveFPS { kv("Effective FPS", String(format: "%.2f", fps)) }
        if let min = viewModel.minInterval, let max = viewModel.maxInterval {
            kv("Frame Interval", String(format: "min %.3f s, max %.3f s", min, max))
        }
        lines.append("")

        if includeAll {
            lines.append("[Color]")
            kv("Color Space", info.colorSpace)
            kv("Chroma Subsampling", info.chromaSubsampling)
            kv("Primaries", info.colorPrimaries)
            kv("Transfer", info.transferFunction)
            kv("Matrix", info.matrixCoefficients)
            kv("Range", info.colorRange)
            kv("Bit Depth", info.bitDepth)
            if let v = info.av1CSize { kv("av1C Box", "\(v) bytes") }
            kv("AV1 Profile", info.av1Profile)
            kv("AV1 Level", info.av1Level)
            kv("AV1 Chroma", info.av1ChromaSubsampling)
            kv("AV1 Range", info.av1FullRange)
            lines.append("")
        }

        if includeAll, !info.audioTracks.isEmpty {
            lines.append("[Audio]")
            for track in info.audioTracks {
                lines.append("Track \(track.index): \(track.displayString)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

