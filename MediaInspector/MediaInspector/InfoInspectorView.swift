//
//  InfoInspectorView.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

struct InfoInspectorView: View {
    @ObservedObject var viewModel: MediaInspectorViewModel

    var body: some View {
        ZStack {
            if let info = viewModel.extendedInfo {
                ScrollView {
                    Form {
                        FileSection(info: info)

                        if info.hasMetadata {
                            MetadataSection(info: info)
                        }

                        VideoSection(
                            info: info,
                            effectiveFPS: viewModel.effectiveFPS,
                            minInterval: viewModel.minInterval,
                            maxInterval: viewModel.maxInterval
                        )

                        ColorSection(info: info)

                        if !info.audioTracks.isEmpty {
                            AudioSection(info: info)
                        }
                    }
                    .formStyle(.grouped)
                    .controlSize(.small)
                    .environment(\.defaultMinListRowHeight, 22)
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            } else {
                ContentUnavailableView(
                    "No asset loaded",
                    systemImage: "film",
                    description: Text("Open a file from the toolbar to inspect its properties.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding()
            }
        }
        .background(.windowBackground)
    }
}

private struct FileSection: View {
    let info: ExtendedVideoInfo

    var body: some View {
        Section("File") {
            LabeledContent("Name", value: info.fileName)
            LabeledContent("Size", value: info.fileSize)
            LabeledContent("Overall Bitrate", value: info.overallBitrate)
            LabeledContent("Duration", value: info.duration)
        }
    }
}

private struct MetadataSection: View {
    let info: ExtendedVideoInfo

    var body: some View {
        Section("Metadata") {
            if let v = info.creationDate {
                LabeledContent("Created", value: v)
            }
            if let v = info.metadataTitle {
                LabeledContent("Title", value: v)
            }
            if let v = info.metadataArtist {
                LabeledContent("Artist", value: v)
            }
            if let v = info.metadataEncoder {
                LabeledContent("Encoder", value: v)
            }
            if let v = info.metadataDescription {
                LabeledContent("Description") {
                    Text(v)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct VideoSection: View {
    let info: ExtendedVideoInfo
    let effectiveFPS: Double?
    let minInterval: Double?
    let maxInterval: Double?

    var body: some View {
        Section("Video") {
            LabeledContent("Resolution", value: info.resolution)
            LabeledContent("Nominal FPS", value: info.frameRate)
            LabeledContent("Codec", value: info.codec)

            if let bitrate = info.trackBitrate {
                LabeledContent("Video Bitrate", value: bitrate)
            }
            if let deg = info.orientationDegrees {
                LabeledContent("Orientation", value: "\(deg)°")
            }
            if let par = info.pixelAspectRatio {
                LabeledContent("Pixel Aspect Ratio", value: par)
            }
            if let ca = info.cleanAperture {
                LabeledContent("Clean Aperture", value: ca)
            }
            if let scan = info.scanType {
                LabeledContent("Scan Type", value: scan)
            }

            if let fps = effectiveFPS {
                LabeledContent("Effective FPS") {
                    Text(String(format: "%.2f", fps))
                        .monospacedDigit()
                }
            }

            if let min = minInterval, let max = maxInterval {
                LabeledContent("Frame Interval") {
                    Text(String(format: "min %.3f s, max %.3f s", min, max))
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct ColorSection: View {
    let info: ExtendedVideoInfo

    var body: some View {
        Section("Color") {
            if let v = info.colorPrimaries {
                LabeledContent("Primaries", value: v)
            }
            if let v = info.transferFunction {
                LabeledContent("Transfer", value: v)
            }
            if let v = info.matrixCoefficients {
                LabeledContent("Matrix", value: v)
            }
            if let v = info.colorRange {
                LabeledContent("Range", value: v)
            }
            if let v = info.bitDepth {
                LabeledContent("Bit Depth", value: v)
            }
            if let v = info.av1CSize {
                LabeledContent("av1C Box", value: "\(v) bytes")
            }
            if let v = info.av1Profile {
                LabeledContent("AV1 Profile", value: v)
            }
            if let v = info.av1Level {
                LabeledContent("AV1 Level", value: v)
            }
            if let v = info.av1ChromaSubsampling {
                LabeledContent("Chroma Subsampling", value: v)
            }
            if let v = info.av1FullRange {
                LabeledContent("AV1 Range", value: v)
            }
        }
    }
}

private struct AudioSection: View {
    let info: ExtendedVideoInfo

    var body: some View {
        Section("Audio") {
            ForEach(info.audioTracks, id: \.index) { track in
                LabeledContent("Track \(track.index)") {
                    Text(track.displayString)
                        .monospacedDigit()
                }
            }
        }
    }
}

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
