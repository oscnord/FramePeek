import SwiftUI
import FramePeekCore

struct WaveformContainerView: View {
    var viewModel: FramePeekViewModel

    private var audioTracks: [AudioTrackInfo] {
        viewModel.extendedInfo?.audioTracks ?? []
    }

    private var hasTracks: Bool {
        !audioTracks.isEmpty
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Group {
            if hasTracks {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    // Header with controls
                    headerView

                    // Scrollable waveform tracks
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(audioTracks, id: \.index) { track in
                                CollapsibleWaveformTrack(
                                    trackInfo: track,
                                    duration: viewModel.durationSeconds,
                                    viewModel: viewModel,
                                    expandedTracks: $viewModel.expandedWaveformTracks
                                )
                            }
                        }
                        .padding(.horizontal, DesignSystem.Padding.lg)
                        .padding(.vertical, DesignSystem.Padding.lg)
                    }
                    .frame(maxHeight: audioTracks.count <= 3 ? 400 : nil) // Limit height for few tracks
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                        .fill(DesignSystem.Materials.thin)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                                .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                        )
                )
                .padding(DesignSystem.Padding.lg) // Match chart outer padding
            }
        }
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "waveform")
                    .foregroundStyle(DesignSystem.Colors.Chart.primary)
                Text("Audio")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("(\(audioTracks.count))")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                
                // Refresh button - show when any waveform data exists
                if !viewModel.waveformData.isEmpty && !viewModel.isExtractingWaveforms {
                    Button {
                        viewModel.refreshWaveforms()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            if viewModel.waveformLoadedFromCache {
                                Text("Cached")
                                    .font(.system(size: 10))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Refresh waveform data"))
                }
            }

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.top, DesignSystem.Padding.lg)
    }
}
