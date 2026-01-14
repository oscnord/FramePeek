import SwiftUI
import AVFoundation

struct CollapsibleWaveformTrack: View {
    let trackInfo: AudioTrackInfo
    let duration: Double
    @ObservedObject var viewModel: FramePeekViewModel
    @Binding var expandedTracks: Set<Int>
    
    private var isExpanded: Bool {
        expandedTracks.contains(trackInfo.index)
    }
    
    private var hasWaveformData: Bool {
        viewModel.waveformData[trackInfo.index] != nil
    }
    
    private var isExtracting: Bool {
        viewModel.waveformTasks[trackInfo.index] != nil && !hasWaveformData
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Track header
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if isExpanded {
                        expandedTracks.remove(trackInfo.index)
                    } else {
                        expandedTracks.insert(trackInfo.index)
                        // Trigger extraction if needed
                        if !hasWaveformData && !isExtracting {
                            triggerExtraction()
                        }
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Chevron - use rotation to prevent layout shift
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12, height: 12)
                        .animation(nil, value: isExpanded) // Prevent animation on rotation
                    
                    // Track info
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Track \(trackInfo.index)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(trackInfo.displayString)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                Group {
                    if isExpanded {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                            .fill(DesignSystem.Materials.thin)
                    } else {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                            .fill(Color.clear)
                    }
                }
            )
            
            // Waveform content (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    if isExtracting {
                        // Loading state
                        WaveformSkeletonView()
                            .padding(.horizontal, DesignSystem.Padding.lg)
                            .padding(.vertical, DesignSystem.Padding.md)
                    } else if let samples = viewModel.waveformData[trackInfo.index] {
                        // Waveform view
                        AudioWaveformView(
                            trackIndex: trackInfo.index,
                            trackInfo: trackInfo,
                            samples: samples,
                            duration: duration,
                            viewModel: viewModel
                        )
                        .padding(.horizontal, DesignSystem.Padding.lg)
                        .padding(.vertical, DesignSystem.Padding.md)
                    } else {
                        // No data state
                        Text("No waveform data available")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            .padding(.vertical, DesignSystem.Padding.xl)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .fill(DesignSystem.Materials.ultraThin)
                )
            }
        }
    }
    
    private func triggerExtraction() {
        guard let url = viewModel.currentVideoURL else { return }
        let asset = AVURLAsset(url: url)
        
        Task.detached(priority: .userInitiated) { [weak viewModel] in
            guard let viewModel else { return }
            
                do {
                    let tracks = try await asset.loadTracks(withMediaType: AVMediaType.audio)
                guard let audioTrack = tracks.first(where: { track in
                    let trackIndexInArray = tracks.firstIndex(of: track) ?? -1
                    return trackIndexInArray + 1 == trackInfo.index
                }) else {
                    return
                }
                
                await MainActor.run {
                    viewModel.extractWaveformForTrack(
                        trackIndex: trackInfo.index,
                        asset: asset,
                        audioTrack: audioTrack,
                        duration: duration
                    )
                }
            } catch {
                // Handle error silently
            }
        }
    }
}

// MARK: - Skeleton View

private struct WaveformSkeletonView: View {
    var body: some View {
        SkeletonChart(height: 80)
    }
}

