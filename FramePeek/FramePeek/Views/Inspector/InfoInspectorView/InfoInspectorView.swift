import SwiftUI
import FramePeekCore
#if canImport(AppKit)
import AppKit
#endif

struct InfoInspectorView: View {
    var viewModel: FramePeekViewModel

    @State var copiedBannerText: String?

    // Section expansion state - persisted via AppStorage
    @AppStorage("inspector.fileExpanded") var fileExpanded: Bool = false
    @AppStorage("inspector.metadataExpanded") var metadataExpanded: Bool = false
    @AppStorage("inspector.videoExpanded") var videoExpanded: Bool = false
    @AppStorage("inspector.colorExpanded") var colorExpanded: Bool = false
    @AppStorage("inspector.audioExpanded") var audioExpanded: Bool = false
    @AppStorage("inspector.analysisExpanded") var analysisExpanded: Bool = false
    @AppStorage("inspector.containerExpanded") var containerExpanded: Bool = false

    // Track if we've auto-expanded for this video
    @State private var lastLoadedFileName: String?

    var body: some View {
        Group {
            if let info = viewModel.extendedInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Top padding spacer
                        Color.clear
                            .frame(height: DesignSystem.Padding.lg2)

                        header(info: info)

                        // Quick Summary Card (always visible)
                        QuickSummaryCard(info: info)

                        // Video Preview (thumbnail)
                        VideoPreviewView(viewModel: viewModel)
                            .frame(maxHeight: 300)
                            .frame(maxWidth: .infinity)

                        actionBar(info: info)

                        // Collapsible sections
                        VStack(spacing: 12) {
                            CollapsibleSection(
                                title: "File Details",
                                systemImage: "doc.fill",
                                isExpanded: $fileExpanded
                            ) {
                                KVRow("Name", info.fileName)
                                if let v = info.containerFormat { KVRow("Format", v) }
                                KVRow("Size", info.fileSize)
                                KVRow("Overall Bitrate", info.overallBitrate)
                                KVRow("Duration", info.durationFormatted)
                            }

                            if info.hasMetadata {
                                CollapsibleSection(
                                    title: "Metadata",
                                    systemImage: "tag.fill",
                                    isExpanded: $metadataExpanded
                                ) {
                                    if let v = info.creationDate { KVRow("Created", v) }
                                    if let v = info.metadataTitle { KVRow("Title", v) }
                                    if let v = info.metadataArtist { KVRow("Artist", v) }
                                    if let v = info.metadataEncoder { KVRow("Encoder", v) }
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
                                KVRow("Resolution", info.resolution)
                                if let v = info.displayAspectRatio { KVRow("Aspect Ratio", v) }
                                KVRow("Nominal FPS", info.frameRate)
                                if let v = info.frameRateMode { KVRow("Frame Rate Mode", v) }
                                KVRow("Codec", info.codec)
                                if let v = info.codecProfile { KVRow("Profile", v) }
                                if let v = info.codecIdRaw { KVRow("Codec ID", v) }
                                if let v = info.trackBitrate { KVRow("Video Bitrate", v) }
                                if let v = info.maxBitrate { KVRow("Max Bitrate", v) }
                                if let v = info.minBitrate { KVRow("Min Bitrate", v) }
                                if let v = info.videoStreamSize { KVRow("Stream Size", v) }
                                if let v = info.bitsPerPixelFrame { KVRow("Bits/(Pixel*Frame)", v, monospace: true) }
                                if let v = info.orientationDegrees { KVRow("Orientation", "\(v)°") }
                                if let v = info.pixelAspectRatio { KVRow("Pixel Aspect Ratio", v) }
                                if let v = info.cleanAperture { KVRow("Clean Aperture", v) }
                                if let v = info.scanType { KVRow("Scan Type", v) }
                            }

                            CollapsibleSection(
                                title: "Color",
                                systemImage: "paintpalette.fill",
                                isExpanded: $colorExpanded
                            ) {
                                if let v = info.hdrFormat { KVRow("HDR Format", v) }
                                if let v = info.colorSpace { KVRow("Color Space", v) }
                                if let v = info.chromaSubsampling { KVRow("Chroma Subsampling", v) }
                                if let v = info.colorPrimaries { KVRow("Primaries", v) }
                                if let v = info.transferFunction { KVRow("Transfer", v) }
                                if let v = info.matrixCoefficients { KVRow("Matrix", v) }
                                if let v = info.colorRange { KVRow("Range", v) }
                                if let v = info.bitDepth { KVRow("Bit Depth", v) }
                                if let v = info.av1CSize { KVRow("av1C Box", "\(v) bytes", monospace: true) }
                                if let v = info.av1Profile { KVRow("AV1 Profile", v) }
                                if let v = info.av1Level { KVRow("AV1 Level", v) }
                                if let v = info.av1ChromaSubsampling { KVRow("AV1 Chroma", v) }
                                if let v = info.av1FullRange { KVRow("AV1 Range", v) }
                            }

                            if !info.audioTracks.isEmpty {
                                CollapsibleSection(
                                    title: "Audio (\(info.audioTracks.count))",
                                    systemImage: "speaker.wave.2.fill",
                                    isExpanded: $audioExpanded
                                ) {
                                    ForEach(info.audioTracks, id: \.index) { track in
                                        KVRow("Track \(track.index)", track.displayString, monospace: true)
                                    }
                                }
                            }

                            // Container structure section
                            if let containerResult = viewModel.containerAnalysis {
                                CollapsibleSection(
                                    title: "Container (\(containerResult.totalAtomCount))",
                                    systemImage: "shippingbox.fill",
                                    isExpanded: $containerExpanded,
                                    isLoading: viewModel.isAnalyzingContainer
                                ) {
                                    ContainerInspectorView(result: containerResult)
                                }
                            } else if viewModel.isAnalyzingContainer {
                                CollapsibleSection(
                                    title: "Container",
                                    systemImage: "shippingbox.fill",
                                    isExpanded: $containerExpanded,
                                    isLoading: true
                                ) {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Analyzing container structure…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
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
                                        KVRow("Effective FPS", String(format: "%.2f", fps), monospace: true)
                                    }
                                    if let min = viewModel.minInterval, let max = viewModel.maxInterval {
                                        KVRow("Frame Interval",
                                           String(format: "min %.3f s, max %.3f s", min, max),
                                           monospace: true)
                                    }
                                    if viewModel.isAnalyzing && viewModel.effectiveFPS == nil {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                                .layoutPriority(-1)
                                            Text("Analyzing frames…")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignSystem.Padding.md) // Consistent horizontal padding for all content
                    .padding(.bottom, DesignSystem.Padding.md3)
                }
                .modifier(ScrollEdgeEffectModifier())
                .overlay(alignment: .top) {
                    if let banner = copiedBannerText {
                        CopiedBanner(text: banner)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: copiedBannerText)
                .onAppear {
                    Task { @MainActor in
                        autoExpandIfNewFile(info.fileName)
                    }
                }
                .onChange(of: info.fileName) {
                    Task { @MainActor in
                        autoExpandIfNewFile(info.fileName)
                    }
                }
            } else {
                EmptyInspectorState()
            }
        }
    }

    // MARK: - Auto Expand

    private func autoExpandIfNewFile(_ fileName: String) {
        guard lastLoadedFileName != fileName else { return }
        lastLoadedFileName = fileName

        // Expand key sections when a new video loads
        withAnimation(.snappy(duration: 0.3)) {
            fileExpanded = true
            videoExpanded = true
            analysisExpanded = true
        }
    }

}

// MARK: - Scroll Edge Effect Modifier

/// Applies native scroll edge effect on macOS 26+
private struct ScrollEdgeEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

#Preview {
    InfoInspectorView(viewModel: FramePeekViewModel())
}
