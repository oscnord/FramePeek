import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct InfoInspectorView: View {
    @ObservedObject var viewModel: FramePeekViewModel

    @State var copiedBannerText: String? = nil
    
    // Section expansion state - persisted via AppStorage
    @AppStorage("inspector.fileExpanded") var fileExpanded: Bool = false
    @AppStorage("inspector.metadataExpanded") var metadataExpanded: Bool = false
    @AppStorage("inspector.videoExpanded") var videoExpanded: Bool = false
    @AppStorage("inspector.colorExpanded") var colorExpanded: Bool = false
    @AppStorage("inspector.audioExpanded") var audioExpanded: Bool = false
    @AppStorage("inspector.analysisExpanded") var analysisExpanded: Bool = false
    
    // Track if we've auto-expanded for this video
    @State private var lastLoadedFileName: String? = nil

    var body: some View {
        Group {
            if let info = viewModel.extendedInfo {
                NoTopInsetScrollView {
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
                                if let v = info.minBitrate { KV("Min Bitrate", v) }
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
                .overlay(alignment: .top) {
                    if let banner = copiedBannerText {
                        CopiedBanner(text: banner)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: copiedBannerText)
                .onAppear {
                    DispatchQueue.main.async {
                        autoExpandIfNewFile(info.fileName)
                    }
                }
                .onChange(of: info.fileName) {
                    DispatchQueue.main.async {
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

#Preview {
    InfoInspectorView(viewModel: FramePeekViewModel())
}
