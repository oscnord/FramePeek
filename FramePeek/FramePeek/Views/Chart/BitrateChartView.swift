import SwiftUI
import Charts

struct BitrateChartView: View {
    @ObservedObject var viewModel: FramePeekViewModel

    // MARK: - Display Settings

    /// Maximum points to render in chart for performance (LTTB downsampling)
    /// Increased when zoomed for better accuracy
    private var maxDisplayPoints: Int {
        if viewModel.visibleTimeRange != nil {
            return 2000  // More points when zoomed
        }
        return 1000
    }
    
    // MARK: - Statistics
    
    private var statistics: BitrateChartStatistics {
        BitrateChartStatistics(
            samples: viewModel.samples,
            rawFrames: viewModel.rawFrames.isEmpty ? nil : viewModel.rawFrames,
            effectiveFPS: viewModel.effectiveFPS
        )
    }
    
    /// Downsampled samples for efficient chart rendering using LTTB algorithm
    private var displaySamples: [BitrateSample] {
        let filteredSamples: [BitrateSample]
        if let range = viewModel.visibleTimeRange {
            filteredSamples = viewModel.samples.filter { range.contains($0.time) }
        } else {
            filteredSamples = viewModel.samples
        }
        return downsampleLTTB(filteredSamples, targetCount: maxDisplayPoints)
    }

    private var yTickStep: Double {
        statistics.niceStep(forMax: statistics.maxBitrateKbps, targetTicks: 7)
    }
    
    private var xTickStep: Double {
        let duration = (viewModel.visibleTimeRange?.upperBound ?? statistics.maxTime) - (viewModel.visibleTimeRange?.lowerBound ?? 0)
        return statistics.niceStep(forMax: duration, targetTicks: 6)
    }
    
    /// X-axis domain with padding for better visibility of start/end points
    private var xAxisDomain: ClosedRange<Double> {
        if let range = viewModel.visibleTimeRange {
            let padding = (range.upperBound - range.lowerBound) * 0.02
            let start = max(0, range.lowerBound - padding)
            return start...(range.upperBound + padding)
        } else {
            let duration = statistics.maxTime
            let padding = min(duration * 0.02, 5.0)
            let start = max(0, -padding)
            return start...(statistics.maxTime + padding)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bitrate over time")
                        .font(.headline)

                    Text(viewModel.isAnalyzing ? "Streaming samples…" : "Drag to inspect a point")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !viewModel.samples.isEmpty {
                    HStack(spacing: 14) {
                        StatPill(title: "Points", value: "\(viewModel.samples.count)")
                        StatPill(title: "Avg", value: statistics.headerAvgText)
                        StatPill(title: "Peak", value: statistics.headerPeakText)
                        StatPill(title: "σ", value: statistics.headerStdDevText)
                        StatPill(title: "Span", value: statistics.headerDurationText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
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
                    maxBitrateKbps: statistics.maxBitrateKbps,
                    visibleTimeRange: $viewModel.visibleTimeRange
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                chart
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                
                TimelineView(
                    duration: statistics.maxTime == 0 ? viewModel.durationSeconds : statistics.maxTime,
                    visibleTimeRange: $viewModel.visibleTimeRange
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                
                if viewModel.isGeneratingThumbnails {
                    KeyframeLoadingView(
                        message: "Generating thumbnails...",
                        isExtracting: false,
                        onCancel: {
                            viewModel.cancelThumbnailGeneration()
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !viewModel.keyframeThumbs.isEmpty {
                    KeyframeThumbnailStrip(
                        thumbs: viewModel.keyframeThumbs,
                        totalKeyframes: viewModel.keyframeThumbs.count,
                        hoveredKeyframeTime: $viewModel.hoveredKeyframeTime,
                        visibleTimeRange: viewModel.visibleTimeRange
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
            ForEach(displaySamples) { sample in
                AreaMark(
                    x: .value("Time (s)", sample.time),
                    y: .value("Bitrate (kbps)", sample.bitrate / 1000.0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(viewModel.isAnalyzing ? 0.5 : 0.7),
                            Color.accentColor.opacity(viewModel.isAnalyzing ? 0.1 : 0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)
                
                LineMark(
                    x: .value("Time (s)", sample.time),
                    y: .value("Bitrate (kbps)", sample.bitrate / 1000.0)
                )
                .foregroundStyle(Color.accentColor.opacity(viewModel.isAnalyzing ? 0.7 : 1.0))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            
            if !viewModel.samples.isEmpty {
                RuleMark(y: .value("Avg", statistics.avgBitrateKbps))
                    .foregroundStyle(.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
            }
            
            if let hovered = viewModel.hoveredSample {
                RuleMark(x: .value("Time (s)", hovered.time))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            
            if let keyframeTime = viewModel.hoveredKeyframeTime {
                RuleMark(x: .value("Keyframe", keyframeTime))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: 0...(statistics.maxBitrateKbps * 1.1))
        .chartXScale(domain: xAxisDomain)
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
            }
        }
        .drawingGroup()
        .frame(minHeight: 260)
        .overlay(alignment: .topLeading) {
            tooltipOverlay
        }
    }

    // MARK: - Tooltip Overlay

    @ViewBuilder
    private var tooltipOverlay: some View {
        GeometryReader { geometry in
            let tooltipSample: BitrateSample? = {
                if let sample = viewModel.hoveredSample {
                    return sample
                } else if let keyframeTime = viewModel.hoveredKeyframeTime {
                    return viewModel.samples.min(by: { abs($0.time - keyframeTime) < abs($1.time - keyframeTime) })
                }
                return nil
            }()
            
            if let sample = tooltipSample {
                let startTime = viewModel.visibleTimeRange?.lowerBound ?? 0
                let endTime = viewModel.visibleTimeRange?.upperBound ?? statistics.maxTime
                let duration = endTime - startTime
                
                if duration > 0 && sample.time >= startTime && sample.time <= endTime {
                    let timeRatio = (sample.time - startTime) / duration
                    let chartWidth = geometry.size.width
                    let xPos = timeRatio * chartWidth
                    let clampedX = min(max(xPos, 80), chartWidth - 80)
                    
                    Tooltip(sample: sample, maxBitrateKbps: statistics.maxBitrateKbps)
                        .position(x: clampedX, y: 50)
                }
            }
        }
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

#Preview {
    BitrateChartView(viewModel: FramePeekViewModel())
}

