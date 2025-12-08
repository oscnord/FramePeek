//
//  BitrateChartView.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
import Charts

struct BitrateChartView: View {
    @ObservedObject var viewModel: MediaInspectorViewModel

    private var maxBitrateKbps: Double {
        let maxBits = viewModel.samples.map(\.bitrate).max() ?? 1
        return Double(maxBits) / 1000.0
    }

    private var maxTime: Double {
        viewModel.samples.map(\.time).max() ?? 0
    }

    private var yTickStep: Double { niceStep(forMax: maxBitrateKbps, targetTicks: 7) }
    private var xTickStep: Double { niceStep(forMax: maxTime, targetTicks: 6) }

    private func niceStep(forMax max: Double, targetTicks: Int) -> Double {
        guard max > 0, targetTicks > 0 else { return 1 }
        let rough = max / Double(targetTicks)
        let magnitude = pow(10.0, floor(log10(rough)))
        let residual = rough / magnitude

        let nice: Double
        if residual < 1.5 { nice = 1 }
        else if residual < 3 { nice = 2 }
        else if residual < 7 { nice = 5 }
        else { nice = 10 }

        return nice * magnitude
    }

    private var headerPeakText: String {
        if viewModel.samples.isEmpty { return "—" }
        return String(format: "%.0f kb/s", maxBitrateKbps)
    }

    private var headerDurationText: String {
        if viewModel.samples.isEmpty { return "—" }
        return String(format: "%.0f s", maxTime)
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            Group {
                if viewModel.samples.isEmpty {
                    emptyState
                } else {
                    chartCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(.windowBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bitrate over time")
                    .font(.headline)

                Text(viewModel.isAnalyzing ? "Streaming samples…" : "Drag to inspect a point")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 14) {
                StatPill(title: "Points", value: "\(viewModel.samples.count)")
                StatPill(title: "Peak", value: headerPeakText)
                StatPill(title: "Span", value: headerDurationText)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Empty

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                )

            if viewModel.isAnalyzing {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Analyzing frames…")
                        .font(.headline)
                    Text("For long files, choose a larger interval to limit memory usage.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "No file loaded",
                    systemImage: "waveform.path.ecg",
                    description: Text("Open or drop a video file to inspect bitrate.")
                )
                .padding()
            }
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                )

            VStack(spacing: 10) {
                ChartHeaderRow(
                    hoveredSample: viewModel.hoveredSample,
                    maxBitrateKbps: maxBitrateKbps
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                chart
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            if viewModel.isAnalyzing {
                loadingBadge
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(viewModel.samples) { sample in
                BarMark(
                    x: .value("Time (s)", sample.time),
                    y: .value("Bitrate (kbps)", sample.bitrate / 1000.0)
                )
                .foregroundStyle(.tint.opacity(viewModel.isAnalyzing ? 0.80 : 1.0))
                .cornerRadius(2)
            }

            if let hovered = viewModel.hoveredSample {
                RuleMark(x: .value("Time (s)", hovered.time))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: 0...(maxBitrateKbps * 1.1))
        .chartXAxis {
            AxisMarks(position: .bottom, values: .stride(by: xTickStep)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                AxisTick().foregroundStyle(.secondary.opacity(0.35))
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text("\(t, specifier: "%.0f") s")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: yTickStep)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.20))
                AxisTick().foregroundStyle(.secondary.opacity(0.35))
                AxisValueLabel {
                    if let b = value.as(Double.self) {
                        Text("\(b, specifier: "%.0f")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let location = value.location
                                    if let time: Double = proxy.value(atX: location.x) {
                                        if let nearest = viewModel.samples.min(by: {
                                            abs($0.time - time) < abs($1.time - time)
                                        }) {
                                            viewModel.hoveredSample = nearest
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    viewModel.hoveredSample = nil
                                }
                        )

                    if let sample = viewModel.hoveredSample,
                       let xPos = proxy.position(forX: sample.time)
                    {
                        let clampedX = min(max(xPos, 14), geometry.size.width - 200)

                        Tooltip(sample: sample, maxBitrateKbps: maxBitrateKbps)
                            .position(x: clampedX, y: 16)
                    }
                }
            }
        }
        .frame(minHeight: 260)
    }

    // MARK: - Overlay

    private var loadingBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Analyzing…")
                .font(.caption)
                .fontWeight(.semibold)

            Text("\(viewModel.samples.count) pts")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        )
        .shadow(radius: 4)
    }
}

// MARK: - Components

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.30), lineWidth: 1)
        )
    }
}

private struct ChartHeaderRow: View {
    let hoveredSample: BitrateSample?
    let maxBitrateKbps: Double

    var body: some View {
        HStack {
            Text("Chart")
                .font(.subheadline)
                .fontWeight(.semibold)

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
            }
        }
    }
}

private struct Tooltip: View {
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

#Preview {
    BitrateChartView(viewModel: MediaInspectorViewModel())
}
