import SwiftUI
import Charts
import FramePeekCore

struct BitrateChartView: View {
    @ObservedObject var viewModel: FramePeekViewModel
    @ObservedObject private var playerManager = PlayerViewModelManager.shared

    // MARK: - Cached Display Samples

    @State private var cachedDisplaySamples: [BitrateSample] = []
    @State private var lastDisplaySamplesInputHash: Int = 0

    // MARK: - Display Settings

    /// Maximum points to render in chart for performance (LTTB downsampling)
    /// Increased when zoomed for better accuracy
    private var maxDisplayPoints: Int {
        if viewModel.visibleTimeRange != nil {
            return viewModel.chartMaxDisplayPointsZoomed
        }
        return viewModel.chartMaxDisplayPoints
    }

    // MARK: - Statistics

    private var statistics: BitrateChartStatistics {
        BitrateChartStatistics(
            samples: viewModel.samples,
            rawFrames: viewModel.rawFrames.isEmpty ? nil : viewModel.rawFrames,
            effectiveFPS: viewModel.effectiveFPS
        )
    }

    /// Recomputes downsampled display samples only when inputs change
    private func recomputeDisplaySamples() {
        let inputHash = combineHashValues(viewModel.samples.count, viewModel.visibleTimeRange?.hashValue ?? 0)
        guard inputHash != lastDisplaySamplesInputHash else { return }
        lastDisplaySamplesInputHash = inputHash

        let filteredSamples: [BitrateSample]
        if let range = viewModel.visibleTimeRange {
            filteredSamples = viewModel.samples.filter { range.contains($0.time) }
        } else {
            filteredSamples = viewModel.samples
        }
        cachedDisplaySamples = downsampleLTTB(filteredSamples, targetCount: maxDisplayPoints)
    }

    private func combineHashValues(_ a: Int, _ b: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(a)
        hasher.combine(b)
        return hasher.finalize()
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
        VStack(spacing: DesignSystem.Spacing.md2) {
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
        .padding(DesignSystem.Padding.lg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md2) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.md2) {
                Spacer()

                if !viewModel.samples.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.lg2) {
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
        .padding(.horizontal, DesignSystem.Padding.sm)
    }

    // MARK: - Empty

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                )

            if viewModel.isAnalyzing {
                VStack(spacing: DesignSystem.Spacing.md2) {
                    SafeProgressView(controlSize: .regular)
                        .frame(width: 32, height: 32)
                    Text("Analyzing frames…")
                        .font(.headline)
                    Text("For long files, choose a larger interval to limit memory usage.")
                        .font(.callout)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
                .padding()
            } else {
                // Check if file is loaded but can't be analyzed
                if viewModel.extendedInfo != nil {
                    ContentUnavailableView(
                        "Unable to Analyze",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This file was loaded but FramePeek cannot extract bitrate data. The file may be missing video information or use an unsupported format.")
                    )
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
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                )

            VStack(spacing: DesignSystem.Spacing.md2) {
                ChartHeaderRow(
                    viewModel: viewModel,
                    visibleTimeRange: $viewModel.visibleTimeRange
                )
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.top, DesignSystem.Padding.lg)

                chart
                    .padding(.horizontal, DesignSystem.Padding.lg)
                    .padding(.bottom, DesignSystem.Padding.md)

                if viewModel.isGeneratingThumbnails {
                    KeyframeLoadingView(
                        message: "Generating thumbnails...",
                        isExtracting: false,
                        onCancel: {
                            viewModel.cancelThumbnailGeneration()
                        }
                    )
                    .padding(.horizontal, DesignSystem.Padding.lg)
                    .padding(.bottom, DesignSystem.Padding.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !viewModel.keyframeThumbs.isEmpty {
                    KeyframeThumbnailStrip(
                        thumbs: viewModel.keyframeThumbs,
                        totalKeyframes: viewModel.keyframeThumbs.count,
                        hoveredKeyframeTime: $viewModel.hoveredKeyframeTime,
                        visibleTimeRange: viewModel.visibleTimeRange,
                        frameRate: viewModel.effectiveFPS
                    )
                    .padding(.horizontal, DesignSystem.Padding.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if viewModel.isAnalyzing {
                loadingBadge
                    .padding(DesignSystem.Padding.lg)
                    .allowsHitTesting(false)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(cachedDisplaySamples) { sample in
                AreaMark(
                    x: .value("Time (s)", sample.time),
                    y: .value("Bitrate (kbps)", sample.bitrate / 1000.0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: viewModel.isAnalyzing ? [
                            DesignSystem.Colors.Chart.primaryAreaTopAnalyzing,
                            DesignSystem.Colors.Chart.primaryAreaBottomAnalyzing
                        ] : [
                            DesignSystem.Colors.Chart.primaryAreaTop,
                            DesignSystem.Colors.Chart.primaryAreaBottom
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
                .foregroundStyle(viewModel.isAnalyzing ? DesignSystem.Colors.Chart.primaryAnalyzing : DesignSystem.Colors.Chart.primary)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.medium))
            }

            if !viewModel.samples.isEmpty {
                RuleMark(y: .value("Avg", statistics.avgBitrateKbps))
                    .foregroundStyle(DesignSystem.Colors.Chart.averageOpacity)
                    .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.thin, dash: [6, 4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.Chart.average)
                            .padding(.horizontal, DesignSystem.Padding.sm)
                            .background(DesignSystem.Materials.ultraThin)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous))
                    }
            }

            if let time = viewModel.hoveredTimestamp {
                RuleMark(x: .value("Time (s)", time))
                    .foregroundStyle(DesignSystem.Colors.Chart.hoveredLine)
                    .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.medium, dash: [4, 4]))
            }

            if let keyframeTime = viewModel.hoveredKeyframeTime {
                RuleMark(x: .value("Keyframe", keyframeTime))
                    .foregroundStyle(DesignSystem.Colors.Chart.keyframeOpacity)
                    .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.thick))
            }

            // Playback position indicator
            if let playbackTime = playerManager.currentPlaybackTime {
                RuleMark(x: .value("Playback", playbackTime))
                    .foregroundStyle(.blue.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.thick))
            }
        }
        .chartYScale(domain: 0...(statistics.maxBitrateKbps * 1.1))
        .chartXScale(domain: xAxisDomain)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .stride(by: xTickStep)) { value in
                AxisGridLine().foregroundStyle(DesignSystem.Colors.Chart.grid)
                AxisTick().foregroundStyle(DesignSystem.Colors.Chart.axisTick)
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text(formatTimeForChart(t, frameRate: viewModel.effectiveFPS))
                            .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: yTickStep)) { value in
                AxisGridLine().foregroundStyle(DesignSystem.Colors.Chart.gridY)
                AxisTick().foregroundStyle(DesignSystem.Colors.Chart.axisTick)
                AxisValueLabel {
                    if let b = value.as(Double.self) {
                        Text("\(b, specifier: "%.0f")")
                            .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(DesignSystem.Colors.Chart.background)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let time: Double = proxy.value(atX: location.x) {
                                // Find nearest sample
                                if let nearest = viewModel.samples.min(by: {
                                    abs($0.time - time) < abs($1.time - time)
                                }) {
                                    viewModel.hoveredSample = nearest
                                }
                                // Set shared timestamp for cross-chart sync
                                viewModel.hoveredTimestamp = time
                            }
                        case .ended:
                            viewModel.hoveredSample = nil
                            viewModel.hoveredTimestamp = nil
                        }
                    }
                    .onTapGesture { location in
                        // Seek on click
                        if let time: Double = proxy.value(atX: location.x) {
                            PlayerViewModelManager.shared.seekToTime(time)
                        }
                    }
            }
        }
        .drawingGroup()
        .frame(minHeight: 400)
        .onAppear { recomputeDisplaySamples() }
        .onChange(of: viewModel.samples.count) { _, _ in recomputeDisplaySamples() }
        .onChange(of: viewModel.visibleTimeRange) { _, _ in recomputeDisplaySamples() }
    }

    // MARK: - Overlay

    private var loadingBadge: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            SafeProgressView(controlSize: .small)
                .frame(width: 16, height: 16)

            Text("Analyzing…")
                .font(.caption)
                .fontWeight(.semibold)

            Text("\(viewModel.samples.count) pts")
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
        }
        .padding(.vertical, DesignSystem.Padding.sm2)
        .padding(.horizontal, DesignSystem.Padding.md3)
        .background(DesignSystem.Materials.regular)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.panel, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
        )
        .shadow(radius: 4)
    }
}

#Preview {
    BitrateChartView(viewModel: FramePeekViewModel())
}
