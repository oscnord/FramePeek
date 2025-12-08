//
//  InfoInspectorView.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct InfoInspectorView: View {
    @ObservedObject var viewModel: MediaInspectorViewModel

    @State private var copiedBannerText: String? = nil

    var body: some View {
        Group {
            if let info = viewModel.extendedInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        header(info: info)

                        actionBar(info: info)

                        InspectorCard(title: "File", systemImage: "doc") {
                            KV("Name", info.fileName)
                            KV("Size", info.fileSize)
                            KV("Overall Bitrate", info.overallBitrate)
                            KV("Duration", info.duration)
                        }

                        if info.hasMetadata {
                            InspectorCard(title: "Metadata", systemImage: "tag") {
                                if let v = info.creationDate { KV("Created", v) }
                                if let v = info.metadataTitle { KV("Title", v) }
                                if let v = info.metadataArtist { KV("Artist", v) }
                                if let v = info.metadataEncoder { KV("Encoder", v) }
                                if let v = info.metadataDescription {
                                    KVMultiline("Description", v)
                                }
                            }
                        }

                        InspectorCard(title: "Video", systemImage: "film") {
                            KV("Resolution", info.resolution)
                            KV("Nominal FPS", info.frameRate)
                            KV("Codec", info.codec)

                            if let v = info.trackBitrate { KV("Video Bitrate", v) }
                            if let v = info.orientationDegrees { KV("Orientation", "\(v)°") }
                            if let v = info.pixelAspectRatio { KV("Pixel Aspect Ratio", v) }
                            if let v = info.cleanAperture { KV("Clean Aperture", v) }
                            if let v = info.scanType { KV("Scan Type", v) }

                            if let fps = viewModel.effectiveFPS {
                                KV("Effective FPS", String(format: "%.2f", fps), monospace: true)
                            }

                            if let min = viewModel.minInterval, let max = viewModel.maxInterval {
                                KV("Frame Interval",
                                   String(format: "min %.3f s, max %.3f s", min, max),
                                   monospace: true)
                            }
                        }

                        InspectorCard(title: "Color", systemImage: "paintpalette") {
                            if let v = info.colorPrimaries { KV("Primaries", v) }
                            if let v = info.transferFunction { KV("Transfer", v) }
                            if let v = info.matrixCoefficients { KV("Matrix", v) }
                            if let v = info.colorRange { KV("Range", v) }
                            if let v = info.bitDepth { KV("Bit Depth", v) }

                            if let v = info.av1CSize { KV("av1C Box", "\(v) bytes", monospace: true) }
                            if let v = info.av1Profile { KV("AV1 Profile", v) }
                            if let v = info.av1Level { KV("AV1 Level", v) }
                            if let v = info.av1ChromaSubsampling { KV("Chroma Subsampling", v) }
                            if let v = info.av1FullRange { KV("AV1 Range", v) }
                        }

                        if !info.audioTracks.isEmpty {
                            InspectorCard(title: "Audio", systemImage: "speaker.wave.2") {
                                ForEach(info.audioTracks, id: \.index) { track in
                                    KV("Track \(track.index)", track.displayString, monospace: true)
                                }
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(12)
                }
                .overlay(alignment: .top) {
                    if let banner = copiedBannerText {
                        CopiedBanner(text: banner)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: copiedBannerText)
            }
        }
        .background(.windowBackground)
    }

    // MARK: - Header / Actions

    private func header(info: ExtendedVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.fileName)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("\(info.resolution) • \(info.codec)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if viewModel.isAnalyzing {
                    Divider().frame(height: 14)
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Analyzing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func actionBar(info: ExtendedVideoInfo) -> some View {
        HStack(spacing: 10) {
            Button {
                copyAll(info: info)
            } label: {
                Label("Copy All Text", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)

            Button {
                copySummary(info: info)
            } label: {
                Label("Copy Summary", systemImage: "text.quote")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - Copy

    private func copyAll(info: ExtendedVideoInfo) {
        let text = buildCopyText(info: info, includeAll: true)
        copyToPasteboard(text)
        showCopied("Copied all text")
    }

    private func copySummary(info: ExtendedVideoInfo) {
        let text = buildCopyText(info: info, includeAll: false)
        copyToPasteboard(text)
        showCopied("Copied summary")
    }

    private func showCopied(_ message: String) {
        copiedBannerText = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedBannerText == message {
                copiedBannerText = nil
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func buildCopyText(info: ExtendedVideoInfo, includeAll: Bool) -> String {
        var lines: [String] = []
        func add(_ s: String?) { if let s, !s.isEmpty { lines.append(s) } }
        func kv(_ k: String, _ v: String?) { if let v, !v.isEmpty { lines.append("\(k): \(v)") } }

        lines.append("Media Inspector")
        lines.append("")

        lines.append("[File]")
        kv("Name", info.fileName)
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
        kv("Codec", info.codec)
        kv("Video Bitrate", info.trackBitrate)
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
            kv("Primaries", info.colorPrimaries)
            kv("Transfer", info.transferFunction)
            kv("Matrix", info.matrixCoefficients)
            kv("Range", info.colorRange)
            kv("Bit Depth", info.bitDepth)
            if let v = info.av1CSize { kv("av1C Box", "\(v) bytes") }
            kv("AV1 Profile", info.av1Profile)
            kv("AV1 Level", info.av1Level)
            kv("Chroma Subsampling", info.av1ChromaSubsampling)
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

// MARK: - Components

private struct InspectorCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

private struct KV: View {
    let key: String
    let value: String
    let monospace: Bool

    init(_ key: String, _ value: String, monospace: Bool = false) {
        self.key = key
        self.value = value
        self.monospace = monospace
    }

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.primary)
                .if(monospace) { $0.monospacedDigit() }
                .textSelection(.enabled)
        } label: {
            Text(key)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KVMultiline: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(key)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CopiedBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        )
        .shadow(radius: 6)
    }
}

// MARK: - Helpers

private extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Existing extensions

extension ExtendedVideoInfo {
    var hasMetadata: Bool {
        creationDate != nil ||
        metadataTitle != nil ||
        metadataArtist != nil ||
        metadataEncoder != nil ||
        metadataDescription != nil
    }
}

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
        return "\(codec), \(channels) ch, \(sr), \(bitrate), lang \(lang)"
    }
}

#Preview {
    InfoInspectorView(viewModel: MediaInspectorViewModel())
}
