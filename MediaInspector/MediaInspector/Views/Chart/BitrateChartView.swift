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
    
    // MARK: - Display Settings
    
    /// Maximum points to render in chart for performance (LTTB downsampling)
    /// Increased when zoomed for better accuracy
    private var maxDisplayPoints: Int {
        // When zoomed, show more points for better accuracy
        if viewModel.visibleTimeRange != nil {
            return 2000  // More points when zoomed
        }
        return 1000  // Increased from 500 for better accuracy
    }
    
    // MARK: - Statistics
    
    private var statistics: BitrateChartStatistics {
        BitrateChartStatistics(samples: viewModel.samples)
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

                HStack(spacing: 14) {
                    StatPill(title: "Points", value: "\(viewModel.samples.count)")
                    StatPill(title: "Avg", value: statistics.headerAvgText)
                    StatPill(title: "Peak", value: statistics.headerPeakText)
                    StatPill(title: "σ", value: statistics.headerStdDevText)
                    StatPill(title: "Span", value: statistics.headerDurationText)
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
                
                // Keyframe section with animated reveal
                if !viewModel.keyframes.isEmpty || viewModel.isExtractingKeyframes || viewModel.isGeneratingThumbnails {
                    VStack(spacing: 8) {
                        // Show loading state or actual timeline
                        if viewModel.isExtractingKeyframes {
                            KeyframeLoadingView(
                                message: viewModel.keyframeExtractionProgress ?? "Extracting keyframes...",
                                isExtracting: true,
                                onCancel: {
                                    viewModel.cancelKeyframeExtraction()
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if !viewModel.keyframes.isEmpty {
                            KeyframeTimelineView(
                                keyframes: viewModel.keyframes,
                                duration: statistics.maxTime == 0 ? viewModel.durationSeconds : statistics.maxTime,
                                hoveredKeyframeTime: viewModel.hoveredKeyframeTime,
                                visibleTimeRange: $viewModel.visibleTimeRange,
                                maxKeyframes: viewModel.maxPointsTarget  // Match chart resolution
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Show thumbnail loading or actual thumbnails
                        if viewModel.isGeneratingThumbnails {
                            KeyframeLoadingView(
                                message: "Generating thumbnails...",
                                isExtracting: false,
                                onCancel: {
                                    viewModel.cancelThumbnailGeneration()
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if !viewModel.keyframeThumbs.isEmpty {
                            KeyframeThumbnailStrip(
                                thumbs: viewModel.keyframeThumbs,
                                totalKeyframes: viewModel.keyframes.count,
                                hoveredKeyframeTime: $viewModel.hoveredKeyframeTime,
                                visibleTimeRange: viewModel.visibleTimeRange
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.keyframes.isEmpty)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.keyframeThumbs.isEmpty)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isExtractingKeyframes)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isGeneratingThumbnails)

            if viewModel.isAnalyzing {
                loadingBadge
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    private var chart: some View {
        Chart {
            // Area chart with gradient fill
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
            
            // Average bitrate reference line
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
            
            // Keyframe markers on chart - downsampled for performance
            ForEach(downsampleKeyframes(viewModel.keyframes, maxCount: 200, visibleRange: viewModel.visibleTimeRange)) { keyframe in
                RuleMark(x: .value("Keyframe", keyframe.time))
                    .foregroundStyle(.green.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            if let hovered = viewModel.hoveredSample {
                RuleMark(x: .value("Time (s)", hovered.time))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            
            // Highlight from keyframe thumbnail hover
            if let keyframeTime = viewModel.hoveredKeyframeTime {
                RuleMark(x: .value("Keyframe", keyframeTime))
                    .foregroundStyle(.green.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: 0...(statistics.maxBitrateKbps * 1.1))
        .chartXScale(domain: (viewModel.visibleTimeRange?.lowerBound ?? 0)...(viewModel.visibleTimeRange?.upperBound ?? statistics.maxTime))
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
        .drawingGroup() // Metal-accelerated rendering for better performance
        .frame(minHeight: 260)
        .overlay(alignment: .topLeading) {
            // Tooltip overlay - outside chart clipping area
            tooltipOverlay
        }
    }

    // MARK: - Tooltip Overlay

    @ViewBuilder
    private var tooltipOverlay: some View {
        GeometryReader { geometry in
            // Determine which sample to show tooltip for
            let tooltipSample: BitrateSample? = {
                if let sample = viewModel.hoveredSample {
                    return sample
                } else if let keyframeTime = viewModel.hoveredKeyframeTime {
                    return viewModel.samples.min(by: { abs($0.time - keyframeTime) < abs($1.time - keyframeTime) })
                }
                return nil
            }()
            
            if let sample = tooltipSample {
                // Calculate x position based on time ratio
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
    BitrateChartView(viewModel: MediaInspectorViewModel())
}

