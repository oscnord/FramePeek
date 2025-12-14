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
    
    // Section expansion state - persisted via AppStorage
    @AppStorage("inspector.fileExpanded") private var fileExpanded: Bool = false
    @AppStorage("inspector.metadataExpanded") private var metadataExpanded: Bool = false
    @AppStorage("inspector.videoExpanded") private var videoExpanded: Bool = false
    @AppStorage("inspector.colorExpanded") private var colorExpanded: Bool = false
    @AppStorage("inspector.audioExpanded") private var audioExpanded: Bool = false
    @AppStorage("inspector.analysisExpanded") private var analysisExpanded: Bool = false
    
    // Track if we've auto-expanded for this video
    @State private var lastLoadedFileName: String? = nil

    var body: some View {
        Group {
            if let info = viewModel.extendedInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(info: info)
                        actionBar(info: info)
                        
                        // Quick Summary Card (always visible)
                        QuickSummaryCard(info: info)
                        
                        // Collapsible sections
                        VStack(spacing: 0) {
                            CollapsibleSection(
                                title: "File Details",
                                systemImage: "doc.fill",
                                isExpanded: $fileExpanded
                            ) {
                                KV("Name", info.fileName)
                                if let v = info.containerFormat { KV("Format", v) }
                                KV("Size", info.fileSize)
                                KV("Overall Bitrate", info.overallBitrate)
                                KV("Duration", info.durationFormatted)
                            }

                            if info.hasMetadata {
                                CollapsibleSection(
                                    title: "Metadata",
                                    systemImage: "tag.fill",
                                    isExpanded: $metadataExpanded
                                ) {
                                    if let v = info.creationDate { KV("Created", v) }
                                    if let v = info.metadataTitle { KV("Title", v) }
                                    if let v = info.metadataArtist { KV("Artist", v) }
                                    if let v = info.metadataEncoder { KV("Encoder", v) }
                                    if let v = info.metadataDescription {
                                        KVMultiline("Description", v)
                                    }
                                }
                            }

                            CollapsibleSection(
                                title: "Video",
                                systemImage: "film.fill",
                                isExpanded: $videoExpanded
                            ) {
                                KV("Resolution", info.resolution)
                                if let v = info.displayAspectRatio { KV("Aspect Ratio", v) }
                                KV("Nominal FPS", info.frameRate)
                                if let v = info.frameRateMode { KV("Frame Rate Mode", v) }
                                KV("Codec", info.codec)
                                if let v = info.codecProfile { KV("Profile", v) }
                                if let v = info.codecIdRaw { KV("Codec ID", v) }
                                if let v = info.trackBitrate { KV("Video Bitrate", v) }
                                if let v = info.maxBitrate { KV("Max Bitrate", v) }
                                if let v = info.videoStreamSize { KV("Stream Size", v) }
                                if let v = info.bitsPerPixelFrame { KV("Bits/(Pixel*Frame)", v, monospace: true) }
                                if let v = info.orientationDegrees { KV("Orientation", "\(v)°") }
                                if let v = info.pixelAspectRatio { KV("Pixel Aspect Ratio", v) }
                                if let v = info.cleanAperture { KV("Clean Aperture", v) }
                                if let v = info.scanType { KV("Scan Type", v) }
                            }
                            
                            

                            CollapsibleSection(
                                title: "Color",
                                systemImage: "paintpalette.fill",
                                isExpanded: $colorExpanded
                            ) {
                                if let v = info.hdrFormat { KV("HDR Format", v) }
                                if let v = info.colorSpace { KV("Color Space", v) }
                                if let v = info.chromaSubsampling { KV("Chroma Subsampling", v) }
                                if let v = info.colorPrimaries { KV("Primaries", v) }
                                if let v = info.transferFunction { KV("Transfer", v) }
                                if let v = info.matrixCoefficients { KV("Matrix", v) }
                                if let v = info.colorRange { KV("Range", v) }
                                if let v = info.bitDepth { KV("Bit Depth", v) }
                                if let v = info.av1CSize { KV("av1C Box", "\(v) bytes", monospace: true) }
                                if let v = info.av1Profile { KV("AV1 Profile", v) }
                                if let v = info.av1Level { KV("AV1 Level", v) }
                                if let v = info.av1ChromaSubsampling { KV("AV1 Chroma", v) }
                                if let v = info.av1FullRange { KV("AV1 Range", v) }
                            }

                            if !info.audioTracks.isEmpty {
                                
                                
                                CollapsibleSection(
                                    title: "Audio (\(info.audioTracks.count))",
                                    systemImage: "speaker.wave.2.fill",
                                    isExpanded: $audioExpanded
                                ) {
                                    ForEach(info.audioTracks, id: \.index) { track in
                                        KV("Track \(track.index)", track.displayString, monospace: true)
                                    }
                                }
                            }
                            
                            // Analysis section
                            if viewModel.effectiveFPS != nil || viewModel.minInterval != nil || viewModel.isAnalyzing {
                                
                                
                                CollapsibleSection(
                                    title: "Frame Analysis",
                                    systemImage: "waveform.badge.magnifyingglass",
                                    isExpanded: $analysisExpanded,
                                    isLoading: viewModel.isAnalyzing
                                ) {
                                    if let fps = viewModel.effectiveFPS {
                                        KV("Effective FPS", String(format: "%.2f", fps), monospace: true)
                                    }
                                    if let min = viewModel.minInterval, let max = viewModel.maxInterval {
                                        KV("Frame Interval",
                                           String(format: "min %.3f s, max %.3f s", min, max),
                                           monospace: true)
                                    }
                                    if viewModel.isAnalyzing && viewModel.effectiveFPS == nil {
                                        HStack(spacing: 8) {
                                            ProgressView().controlSize(.small)
                                            Text("Analyzing frames…")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(14)
                }
                .overlay(alignment: .top) {
                    if let banner = copiedBannerText {
                        CopiedBanner(text: banner)
                            .padding(.top, 10)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .top)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.9, anchor: .top)),
                                    removal: .move(edge: .top)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.95, anchor: .top))
                                )
                            )
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: copiedBannerText)
                .onAppear {
                    autoExpandIfNewFile(info.fileName)
                }
                .onChange(of: info.fileName) {
                    autoExpandIfNewFile(info.fileName)
                }
            } else {
                EmptyInspectorState()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.extendedInfo != nil)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Auto Expand
    
    private func autoExpandIfNewFile(_ fileName: String) {
        guard lastLoadedFileName != fileName else { return }
        lastLoadedFileName = fileName
        
        // Expand key sections when a new video loads
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            fileExpanded = true
            videoExpanded = true
            analysisExpanded = true
        }
    }

    // MARK: - Header / Actions

    private func header(info: ExtendedVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.fileName)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(info.resolution) • \(info.codec)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionBar(info: ExtendedVideoInfo) -> some View {
        HStack(spacing: 8) {
            Button {
                copyAll(info: info)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    let allExpanded = fileExpanded && videoExpanded && colorExpanded && audioExpanded && analysisExpanded
                    if allExpanded {
                        collapseAll()
                    } else {
                        expandAll()
                    }
                }
            } label: {
                let allExpanded = fileExpanded && videoExpanded && colorExpanded && audioExpanded && analysisExpanded
                Label(allExpanded ? "Collapse" : "Expand", 
                      systemImage: allExpanded ? "chevron.up.2" : "chevron.down.2")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
    }
    
    private func expandAll() {
        fileExpanded = true
        metadataExpanded = true
        videoExpanded = true
        colorExpanded = true
        audioExpanded = true
        analysisExpanded = true
    }
    
    private func collapseAll() {
        fileExpanded = false
        metadataExpanded = false
        videoExpanded = false
        colorExpanded = false
        audioExpanded = false
        analysisExpanded = false
    }

    // MARK: - Copy

    private func copyAll(info: ExtendedVideoInfo) {
        let text = buildCopyText(info: info, includeAll: true)
        copyToPasteboard(text)
        showCopied("Copied all text")
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

#Preview {
    InfoInspectorView(viewModel: MediaInspectorViewModel())
}
