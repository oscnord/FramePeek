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

    private var yTickStep: Double {
        niceStep(forMax: maxBitrateKbps, targetTicks: 8)
    }

    private var xTickStep: Double {
        niceStep(forMax: maxTime, targetTicks: 6)
    }

    private func niceStep(forMax max: Double, targetTicks: Int) -> Double {
        guard max > 0, targetTicks > 0 else { return 1 }
        let rough = max / Double(targetTicks)
        let magnitude = pow(10.0, floor(log10(rough)))
        let residual = rough / magnitude

        let nice: Double
        if residual < 1.5 {
            nice = 1
        } else if residual < 3 {
            nice = 2
        } else if residual < 7 {
            nice = 5
        } else {
            nice = 10
        }

        return nice * magnitude
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.samples.isEmpty {
                if viewModel.isAnalyzing {
                    VStack(spacing: 12) {
                        ProgressView("Analyzing frames…")
                            .progressViewStyle(.circular)
                        Text("This may take a while for long or high-bitrate files.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No file loaded",
                        systemImage: "waveform.path.ecg",
                        description: Text("Open a video file to inspect bitrate over time.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ZStack {
                    Chart {
                        ForEach(viewModel.samples) { sample in
                            BarMark(
                                x: .value("Time (s)", sample.time),
                                y: .value("Bitrate (kbps)", sample.bitrate / 1000.0)
                            )
                            .foregroundStyle(.green.opacity(1.0))
                            .cornerRadius(2)
                        }

                        if let hovered = viewModel.hoveredSample {
                            RuleMark(
                                x: .value("Time (s)", hovered.time)
                            )
                            .foregroundStyle(.white.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .chartYScale(domain: 0...(maxBitrateKbps * 1.1))
                    .chartXAxis {
                        AxisMarks(
                            position: .bottom,
                            values: .stride(by: xTickStep)
                        ) { value in
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.25))
                            AxisTick()
                            AxisValueLabel {
                                if let t = value.as(Double.self) {
                                    Text("\(t, specifier: "%.0f") s")
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(
                            position: .leading,
                            values: .stride(by: yTickStep)
                        ) { value in
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.35))
                            AxisTick()
                            AxisValueLabel {
                                if let b = value.as(Double.self) {
                                    Text("\(b, specifier: "%.0f")")
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plot in
                        plot
                            .background(.black.opacity(0.12))
                            .cornerRadius(10)
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
                                   let xPos = proxy.position(forX: sample.time) {
                                    let clampedX = min(
                                        max(xPos, 12),
                                        geometry.size.width - 180
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Text("Time")
                                            Text(sample.time, format: .number.precision(.fractionLength(2)))
                                            Text("s")
                                        }
                                        .fontWeight(.semibold)

                                        HStack(spacing: 4) {
                                            Text("Bitrate")
                                            Text(sample.bitrate / 1000.0, format: .number.precision(.fractionLength(0)))
                                            Text("kb/s")
                                        }

                                        let fraction = maxBitrateKbps > 0 ? (sample.bitrate / 1000.0) / maxBitrateKbps : 0
                                        HStack(spacing: 4) {
                                            Text("≈")
                                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                            Text("of peak")
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                    .padding(8)
                                    .background(.thickMaterial)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 8,
                                            style: .continuous
                                        )
                                    )
                                    .shadow(radius: 4)
                                    .position(x: clampedX, y: 18)
                                }
                            }
                        }
                    }

                    if viewModel.isAnalyzing {
                        VStack {
                            HStack {
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
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                                )
                                .shadow(radius: 4)

                                Spacer()
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    BitrateChartView(viewModel: MediaInspectorViewModel())
}
