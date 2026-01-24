import SwiftUI

struct GOPDetailsPanel: View {
    let segment: GOPSegment
    let index: Int
    @ObservedObject var viewModel: FramePeekViewModel
    
    /// Frame details - uses ViewModel state (on-demand loaded) with fallback to segment.frames
    private var frameDetails: [FrameInfo]? {
        // First try ViewModel's on-demand loaded frames
        if let frames = viewModel.selectedGOPFrameDetails, !frames.isEmpty {
            return frames
        }
        // Fallback to segment's pre-loaded frames (if any)
        if let frames = segment.frames, !frames.isEmpty {
            return frames
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header
            HStack {
                Text("GOP #\(index + 1)")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.deselectGOP()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Metrics
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                metricRow(label: String(localized: "Start Time"), value: formatTime(segment.startTime))
                metricRow(label: String(localized: "End Time"), value: formatTime(segment.endTime))
                metricRow(label: String(localized: "Duration"), value: String(format: "%.3f s", segment.duration))

                if let frameCount = segment.frameCount {
                    metricRow(label: String(localized: "Frame Count"), value: "\(frameCount)")
                    metricRow(label: String(localized: "Avg Frame Duration"), value: String(format: "%.3f s", segment.duration / Double(frameCount)))
                }
            }

            // Frame details section
            Divider()
                .padding(.vertical, DesignSystem.Padding.xs)

            Text(String(localized: "Frames"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.bottom, DesignSystem.Padding.xs)
            
            // Loading state
            if viewModel.isLoadingGOPFrameDetails {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(String(localized: "Loading frame details..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DesignSystem.Padding.md)
            }
            // Codec not supported state
            else if !viewModel.codecSupportsFrameTypes {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Frame type detection not available for this codec"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DesignSystem.Padding.md)
            }
            // Frame details available
            else if let frames = frameDetails {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { frameIdx, frame in
                            frameRow(frame: frame, index: frameIdx, total: frames.count)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            // No frame details yet
            else {
                Text(String(localized: "No frame details available"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignSystem.Padding.md)
            }
        }
        .padding(DesignSystem.Padding.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                )
        )
    }

    @ViewBuilder
    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func frameRow(frame: FrameInfo, index: Int, total: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Frame type badge
            frameTypeBadge(type: frame.type)

            // Frame info
            VStack(alignment: .leading, spacing: 2) {
                Text("Frame \(index + 1) of \(total)")
                    .font(.caption)
                    .fontWeight(.medium)

                Text(formatTime(frame.time))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Frame size (if available)
            if let size = frame.size {
                Text(formatSize(size))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DesignSystem.Padding.sm)
        .padding(.vertical, DesignSystem.Padding.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
        )
    }

    @ViewBuilder
    private func frameTypeBadge(type: FrameType) -> some View {
        let (color, label) = frameTypeInfo(type: type)

        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color)
            )
    }

    private func frameTypeInfo(type: FrameType) -> (Color, String) {
        switch type {
        case .i:
            return (Color(red: 0.0, green: 0.48, blue: 1.0), "I")
        case .p:
            return (Color(red: 1.0, green: 0.58, blue: 0.0), "P")
        case .b:
            return (Color(red: 1.0, green: 0.23, blue: 0.19), "B")
        case .unknown:
            return (.gray, "?")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        let ms = Int((seconds - Double(totalSeconds)) * 1000)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, ms)
        } else {
            return String(format: "%d:%02d.%03d", minutes, secs, ms)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
