import SwiftUI
import FramePeekCore

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, DesignSystem.Padding.sm2)
        .padding(.horizontal, DesignSystem.Padding.md3)
        .liquidGlassBackground(in: .rect(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(.separator.opacity(0.30), lineWidth: DesignSystem.Borders.thin)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ChartHeaderRow: View {
    var viewModel: FramePeekViewModel
    @Binding var visibleTimeRange: ClosedRange<Double>?
    @State private var showingLegend = false

    var body: some View {
        HStack {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text("Bitrate")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                // Info button with legend popover
                Button {
                    showingLegend.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Show tooltip legend"))
                .popover(isPresented: $showingLegend, arrowEdge: .bottom) {
                    TooltipLegendPopover()
                }
            }

            Spacer()

            // Unified tooltip on hover, or hint when not hovering
            if let time = displayTime {
                let data = TimestampDataProvider.getData(at: time, from: viewModel)
                UnifiedTooltip(data: data)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Text("Hover chart for details")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .padding(.vertical, DesignSystem.Padding.sm2)
            }
        }
    }
    
    /// Determine the timestamp to display (hoveredSample or keyframe)
    private var displayTime: Double? {
        if let sample = viewModel.hoveredSample {
            return sample.time
        } else if let keyframeTime = viewModel.hoveredKeyframeTime {
            return keyframeTime
        }
        return nil
    }
}

// MARK: - Tooltip Legend Popover

struct TooltipLegendPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md2) {
            // Time
            legendRow(
                icon: "clock",
                iconColor: .secondary,
                title: String(localized: "Time"),
                description: String(localized: "Position in the video (minutes:seconds.milliseconds)")
            )
            
            // Bitrate
            legendRow(
                icon: "speedometer",
                iconColor: DesignSystem.Colors.Chart.primary,
                title: String(localized: "Bitrate"),
                description: String(localized: "Data rate at this point (kb/s or Mb/s). Percentage shows relative to peak.")
            )
            
            // GOP
            legendRow(
                icon: "rectangle.split.3x1",
                iconColor: .orange,
                title: String(localized: "GOP"),
                description: String(localized: "Group of Pictures number. Shows frame type (I/P/B) and frame count if GOP analysis was run.")
            )
            
            // Frame types explanation
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    frameTypeBadge("I", color: Color(red: 0.0, green: 0.48, blue: 1.0))
                    Text("Keyframe (full image)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: DesignSystem.Spacing.md) {
                    frameTypeBadge("P", color: Color(red: 1.0, green: 0.58, blue: 0.0))
                    Text("Predicted frame (from previous)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: DesignSystem.Spacing.md) {
                    frameTypeBadge("B", color: Color(red: 1.0, green: 0.23, blue: 0.19))
                    Text("Bidirectional frame")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 28)
            
            // Audio
            legendRow(
                icon: "waveform",
                iconColor: .green,
                title: String(localized: "Audio"),
                description: String(localized: "Audio amplitude with level bar and decibels (dB). -∞ dB is silence, 0 dB is maximum.")
            )
            
            // Brightness
            legendRow(
                icon: "sun.max",
                iconColor: .yellow,
                title: String(localized: "Brightness"),
                description: String(localized: "Average frame brightness (0-100%) and color temperature in Kelvin if color analysis was run.")
            )
            
            // Keyframe
            legendRow(
                icon: "diamond.fill",
                iconColor: .blue,
                title: String(localized: "KF (Keyframe)"),
                description: String(localized: "Distance to nearest keyframe. \"KF\" badge means you're at a keyframe.")
            )
            
            Divider()
            
            Text("Tip: Click on the chart to seek the video to that position.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
        }
        .padding(DesignSystem.Padding.lg)
        .frame(width: 320)
    }
    
    @ViewBuilder
    private func legendRow(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    private func frameTypeBadge(_ type: String, color: Color) -> some View {
        Text(type)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
            )
            .frame(width: 20)
    }
}

struct KeyframeLoadingView: View {
    let message: String
    let isExtracting: Bool
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Invisible placeholder to maintain layout (matching KeyframeThumbnailStrip)
                Color.clear
                    .frame(height: 24)

                Spacer()

                if let onCancel = onCancel {
                    Button(action: onCancel) {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9, weight: .medium))
                            Text("Cancel")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .padding(.horizontal, DesignSystem.Padding.sm)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: DesignSystem.Borders.thin)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Stop thumbnail generation"))
                }
            }
            .frame(height: 24)
            .padding(.horizontal, DesignSystem.Padding.sm)
            .padding(.top, DesignSystem.Padding.sm)

            // Placeholder area to match thumbnail strip height with centered content
            ZStack {
                Color.clear
                    .frame(height: 80)

                HStack(spacing: DesignSystem.Spacing.md2) {
                    SafeProgressView(controlSize: .small)
                        .frame(width: 16, height: 16)

                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }
        }
    }
}
