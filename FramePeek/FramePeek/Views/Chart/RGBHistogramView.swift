import SwiftUI
import FramePeekCore

struct RGBHistogramView: View {
    let histogram: ColorHistogram
    let isHDRContent: Bool
    let isDolbyVision: Bool

    @State private var showInfoPopover = false

    private func percentileValue(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count - 1) * percentile / 100.0)
        return sorted[min(index, sorted.count - 1)]
    }

    private var effectiveMaxFrequency: Double {
        let allValues = histogram.red + histogram.green + histogram.blue
        let p95 = percentileValue(allValues, percentile: 95)
        let absoluteMax = max(histogram.red.max() ?? 0, histogram.green.max() ?? 0, histogram.blue.max() ?? 0)

        if p95 > 0 && p95 < absoluteMax * 0.5 {
            return p95 * 1.2
        } else {
            return max(absoluteMax * 0.1, p95, 0.0001)
        }
    }

    private var yAxisLabels: [Double] {
        let max = effectiveMaxFrequency
        return [0, max * 0.25, max * 0.5, max * 0.75, max]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("RGB Histogram")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Button {
                    showInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(DesignSystem.Padding.xs)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfoPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("RGB Histogram")
                            .font(.headline)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("X-Axis (0-255)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Represents pixel intensity levels from black (0) to full brightness (255).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Y-Axis (Percentage)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.top, DesignSystem.Padding.xs)
                            Text("Shows what percentage of pixels have each intensity level.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Color Channels")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.top, DesignSystem.Padding.xs)
                            Text("Red, green, and blue channels are shown separately. A peak at 0 indicates many dark pixels, while peaks at higher values indicate brighter areas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(DesignSystem.Padding.lg)
                    .frame(width: 320, alignment: .leading)
                }

                if isHDRContent {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(String(localized: "May be inaccurate for HDR"))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if isDolbyVision {
                Text(String(localized: "Histogram data is not available for Dolby Vision content due to color accuracy limitations."))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .padding(.vertical, DesignSystem.Padding.sm)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    // Y-axis labels
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(yAxisLabels.reversed().enumerated()), id: \.offset) { _, value in
                            Text(formatFrequency(value))
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
                                .frame(height: 26, alignment: .center)
                        }
                    }
                    .frame(width: 50)

                    // Chart area
                    VStack(spacing: 0) {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let height = geometry.size.height

                            ZStack(alignment: .bottomLeading) {
                                // Background
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                                    .fill(DesignSystem.Colors.Chart.background)

                                // Grid lines
                                gridLines(width: width, height: height)

                                // RGB curves
                                histogramPath(data: histogram.red, color: .red, width: width, height: height)
                                histogramPath(data: histogram.green, color: .green, width: width, height: height)
                                histogramPath(data: histogram.blue, color: .blue, width: width, height: height)
                            }
                            .drawingGroup()
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
                        }
                        .frame(height: 130)

                        // X-axis labels
                        HStack {
                            Text("0")
                            Spacer()
                            Text("64")
                            Spacer()
                            Text("128")
                            Spacer()
                            Text("192")
                            Spacer()
                            Text("255")
                        }
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                }
                .padding(.top, DesignSystem.Padding.sm)
                .padding(.bottom, DesignSystem.Padding.lg)
            }
        }
        .padding(.top, DesignSystem.Padding.md)
    }

    @ViewBuilder
    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            // Vertical grid lines at 64, 128, 192
            for x in [64, 128, 192] {
                let xPos = CGFloat(x) / 255.0 * width
                path.move(to: CGPoint(x: xPos, y: 0))
                path.addLine(to: CGPoint(x: xPos, y: height))
            }
            // Horizontal grid lines at 25%, 50%, 75%
            for i in 1..<4 {
                let yPos = height * CGFloat(i) / 4.0
                path.move(to: CGPoint(x: 0, y: yPos))
                path.addLine(to: CGPoint(x: width, y: yPos))
            }
        }
        .stroke(DesignSystem.Colors.Chart.grid, lineWidth: 0.5)
    }

    @ViewBuilder
    private func histogramPath(data: [Double], color: Color, width: CGFloat, height: CGFloat) -> some View {
        let max = effectiveMaxFrequency

        // Filled area
        Path { path in
            guard data.count == 256 else { return }

            let xStep = width / 255.0

            path.move(to: CGPoint(x: 0, y: height))

            for i in 0..<256 {
                let x = CGFloat(i) * xStep
                let clampedValue = min(data[i], max)
                let normalizedY = clampedValue / max
                let y = height - (normalizedY * height * 0.95)

                if i == 0 {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
        .fill(color.opacity(0.2))

        // Line stroke
        Path { path in
            guard data.count == 256 else { return }

            let xStep = width / 255.0

            for i in 0..<256 {
                let x = CGFloat(i) * xStep
                let clampedValue = min(data[i], max)
                let normalizedY = clampedValue / max
                let y = height - (normalizedY * height * 0.95)

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, lineWidth: 1.5)
    }

    private func formatFrequency(_ value: Double) -> String {
        let pct = value * 100
        if value >= 0.01 {
            return "\(pct.formatted(.number.precision(.fractionLength(1))))%"
        } else if value > 0.001 {
            return "\(pct.formatted(.number.precision(.fractionLength(2))))%"
        } else if value > 0 {
            return "\(pct.formatted(.number.precision(.fractionLength(3))))%"
        } else {
            return "0%"
        }
    }
}
