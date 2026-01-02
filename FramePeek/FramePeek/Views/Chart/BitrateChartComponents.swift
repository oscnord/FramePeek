import SwiftUI

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
        .background(DesignSystem.Materials.thin)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(.separator.opacity(0.30), lineWidth: DesignSystem.Borders.thin)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ChartHeaderRow: View {
    let hoveredSample: BitrateSample?
    let maxBitrateKbps: Double
    @Binding var visibleTimeRange: ClosedRange<Double>?

    var body: some View {
        HStack {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text("Chart")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer()

            if let s = hoveredSample {
                let kbps = s.bitrate / 1000.0
                HStack(spacing: DesignSystem.Spacing.md2) {
                    Label {
                        Text("\(s.time, format: .number.precision(.fractionLength(2))) s")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption)

                    Label {
                        Text("\(kbps, format: .number.precision(.fractionLength(0))) kb/s")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "speedometer")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption)

                    let frac = maxBitrateKbps > 0 ? kbps / maxBitrateKbps : 0
                    Text(frac, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
                .padding(.vertical, DesignSystem.Padding.sm2)
                .padding(.horizontal, DesignSystem.Padding.md2)
                .background(DesignSystem.Materials.thin)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            } else {
                Text("Hover/drag to see a point")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .padding(.vertical, DesignSystem.Padding.sm2)
            }
        }
    }
}

struct Tooltip: View {
    let sample: BitrateSample
    let maxBitrateKbps: Double

    var body: some View {
        let kbps = sample.bitrate / 1000.0
        let frac = maxBitrateKbps > 0 ? kbps / maxBitrateKbps : 0

        VStack(alignment: .leading, spacing: DesignSystem.Padding.sm2) {
            HStack(spacing: DesignSystem.Spacing.sm3) {
                Image(systemName: "clock")
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text("\(sample.time, format: .number.precision(.fractionLength(2))) s")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            HStack(spacing: DesignSystem.Spacing.sm3) {
                Image(systemName: "speedometer")
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text("\(kbps, format: .number.precision(.fractionLength(0))) kb/s")
                    .monospacedDigit()
            }

            HStack(spacing: DesignSystem.Spacing.sm3) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text(frac, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
        }
        .font(.caption)
        .padding(DesignSystem.Padding.md3)
        .background(DesignSystem.Materials.regular)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.panel, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
        )
        .shadow(radius: DesignSystem.Shadows.small)
    }
}

struct KeyframeLoadingView: View {
    let message: String
    let isExtracting: Bool
    var onCancel: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm3) {
            HStack(spacing: DesignSystem.Spacing.sm3) {
                Image(systemName: isExtracting ? "film" : "photo.on.rectangle.angled")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.Chart.keyframe)
                Text(isExtracting ? "Keyframe Distribution" : "Keyframe Thumbnails")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Padding.sm)
            
            HStack(spacing: DesignSystem.Spacing.md2) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.9)
                
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                
                Spacer()
                
                if let onCancel = onCancel {
                    Button(action: onCancel) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                            Text("Cancel")
                                .font(.caption)
                        }
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .padding(.horizontal, DesignSystem.Padding.md)
                        .padding(.vertical, DesignSystem.Padding.sm)
                        .background(DesignSystem.Materials.regular, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Stop extraction and keep loaded keyframes"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Padding.xl)
            .padding(.horizontal, DesignSystem.Padding.md3)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.06),
                                Color.black.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .strokeBorder(.separator.opacity(0.15), lineWidth: DesignSystem.Borders.thin)
            )
        }
        .padding(.vertical, DesignSystem.Padding.md)
        .padding(.horizontal, DesignSystem.Padding.md3)
        .background(DesignSystem.Materials.thin, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: DesignSystem.Borders.thin)
        )
    }
}

