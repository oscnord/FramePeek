import SwiftUI

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.30), lineWidth: 1)
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
            HStack(spacing: 8) {
                Text("Chart")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if visibleTimeRange != nil {
                    Button {
                        withAnimation {
                            visibleTimeRange = nil
                        }
                    } label: {
                        Label("Reset Zoom", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .tint(.orange)
                }
            }

            Spacer()

            if let s = hoveredSample {
                let kbps = s.bitrate / 1000.0
                HStack(spacing: 10) {
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
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("Hover/drag to see a point")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
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

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("\(sample.time, format: .number.precision(.fractionLength(2))) s")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)
                Text("\(kbps, format: .number.precision(.fractionLength(0))) kb/s")
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.secondary)
                Text(frac, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        )
        .shadow(radius: 6)
    }
}

struct KeyframeLoadingView: View {
    let message: String
    let isExtracting: Bool
    var onCancel: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isExtracting ? "film" : "photo.on.rectangle.angled")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(isExtracting ? "Keyframe Distribution" : "Keyframe Thumbnails")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.9)
                
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let onCancel = onCancel {
                    Button(action: onCancel) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                            Text("Cancel")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Stop extraction and keep loaded keyframes"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: 1)
        )
    }
}

