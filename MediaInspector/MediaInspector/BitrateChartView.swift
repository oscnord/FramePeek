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
    
    private var maxBitrateKbps: Double {
        let maxBits = viewModel.samples.map(\.bitrate).max() ?? 1
        return Double(maxBits) / 1000.0
    }
    
    private var minBitrateKbps: Double {
        let minBits = viewModel.samples.map(\.bitrate).min() ?? 0
        return Double(minBits) / 1000.0
    }
    
    private var avgBitrateKbps: Double {
        guard !viewModel.samples.isEmpty else { return 0 }
        
        // Use weighted average if durations are available
        let totalDuration = viewModel.samples.reduce(0.0) { $0 + $1.duration }
        if totalDuration > 0 {
            // Weighted average: sum(bitrate * duration) / sum(duration)
            let weightedSum = viewModel.samples.reduce(0.0) { $0 + ($1.bitrate * $1.duration) }
            return (weightedSum / totalDuration) / 1000.0
        } else {
            // Fallback to simple average if no durations
            let sum = viewModel.samples.reduce(0.0) { $0 + $1.bitrate }
            return (sum / Double(viewModel.samples.count)) / 1000.0
        }
    }
    
    private var stdDevKbps: Double {
        guard viewModel.samples.count > 1 else { return 0 }
        let avg = avgBitrateKbps * 1000.0
        let variance = viewModel.samples.reduce(0.0) { sum, sample in
            let diff = sample.bitrate - avg
            return sum + diff * diff
        } / Double(viewModel.samples.count)
        return sqrt(variance) / 1000.0
    }

    private var maxTime: Double {
        viewModel.samples.map(\.time).max() ?? 0
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

    private var yTickStep: Double { niceStep(forMax: maxBitrateKbps, targetTicks: 7) }
    private var xTickStep: Double { 
        let duration = (viewModel.visibleTimeRange?.upperBound ?? maxTime) - (viewModel.visibleTimeRange?.lowerBound ?? 0)
        return niceStep(forMax: duration, targetTicks: 6) 
    }

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
    
    private var headerAvgText: String {
        if viewModel.samples.isEmpty { return "—" }
        return String(format: "%.0f kb/s", avgBitrateKbps)
    }
    
    private var headerStdDevText: String {
        if viewModel.samples.isEmpty { return "—" }
        return String(format: "±%.0f", stdDevKbps)
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
                    StatPill(title: "Avg", value: headerAvgText)
                    StatPill(title: "Peak", value: headerPeakText)
                    StatPill(title: "σ", value: headerStdDevText)
                    StatPill(title: "Span", value: headerDurationText)
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
                    maxBitrateKbps: maxBitrateKbps,
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
                                duration: maxTime == 0 ? viewModel.durationSeconds : maxTime,
                                hoveredKeyframeTime: viewModel.hoveredKeyframeTime,
                                visibleTimeRange: $viewModel.visibleTimeRange
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
                RuleMark(y: .value("Avg", avgBitrateKbps))
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
        .chartYScale(domain: 0...(maxBitrateKbps * 1.1))
        .chartXScale(domain: (viewModel.visibleTimeRange?.lowerBound ?? 0)...(viewModel.visibleTimeRange?.upperBound ?? maxTime))
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
                let endTime = viewModel.visibleTimeRange?.upperBound ?? maxTime
                let duration = endTime - startTime
                
                if duration > 0 && sample.time >= startTime && sample.time <= endTime {
                    let timeRatio = (sample.time - startTime) / duration
                    let chartWidth = geometry.size.width
                    let xPos = timeRatio * chartWidth
                    let clampedX = min(max(xPos, 80), chartWidth - 80)
                    
                    Tooltip(sample: sample, maxBitrateKbps: maxBitrateKbps)
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

// MARK: - Keyframe Loading View

private struct KeyframeLoadingView: View {
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
                    .help("Stop extraction and keep loaded keyframes")
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

// MARK: - Downsampling Algorithms

/// Largest-Triangle-Three-Buckets (LTTB) downsampling algorithm
/// Preserves visual shape of the data while reducing point count for performance
private func downsampleLTTB(_ samples: [BitrateSample], targetCount: Int) -> [BitrateSample] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }
    
    var result: [BitrateSample] = []
    result.reserveCapacity(targetCount)
    
    // Always include first point
    result.append(samples[0])
    
    let bucketSize = Double(samples.count - 2) / Double(targetCount - 2)
    var lastSelectedIndex = 0
    
    for i in 0..<(targetCount - 2) {
        // Calculate bucket boundaries
        let bucketStart = Int(Double(i) * bucketSize) + 1
        let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, samples.count - 1)
        
        // Calculate the average point for the next bucket (used as target)
        let nextBucketStart = bucketEnd
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, samples.count - 1)
        
        var avgX: Double = 0
        var avgY: Double = 0
        let nextBucketCount = nextBucketEnd - nextBucketStart + 1
        
        for j in nextBucketStart...nextBucketEnd {
            avgX += samples[j].time
            avgY += samples[j].bitrate
        }
        avgX /= Double(nextBucketCount)
        avgY /= Double(nextBucketCount)
        
        // Find the point in current bucket that creates largest triangle
        var maxArea: Double = -1
        var maxAreaIndex = bucketStart
        
        let pointA = samples[lastSelectedIndex]
        
        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            // Triangle area using cross product
            let area = abs(
                (pointA.time - avgX) * (pointB.bitrate - pointA.bitrate) -
                (pointA.time - pointB.time) * (avgY - pointA.bitrate)
            ) * 0.5
            
            if area > maxArea {
                maxArea = area
                maxAreaIndex = j
            }
        }
        
        result.append(samples[maxAreaIndex])
        lastSelectedIndex = maxAreaIndex
    }
    
    // Always include last point
    result.append(samples[samples.count - 1])
    
    return result
}

/// Downsample keyframes evenly across the video duration for chart display
private func downsampleKeyframes(_ keyframes: [KeyframeMarker], maxCount: Int, visibleRange: ClosedRange<Double>?) -> [KeyframeMarker] {
    let filteredKeyframes: [KeyframeMarker]
    if let range = visibleRange {
        filteredKeyframes = keyframes.filter { range.contains($0.time) }
    } else {
        filteredKeyframes = keyframes
    }
    
    guard filteredKeyframes.count > maxCount else { return filteredKeyframes }
    
    let step = Double(filteredKeyframes.count) / Double(maxCount)
    var result: [KeyframeMarker] = []
    result.reserveCapacity(maxCount)
    
    for i in 0..<maxCount {
        let index = min(Int(Double(i) * step), filteredKeyframes.count - 1)
        result.append(filteredKeyframes[index])
    }
    
    return result
}
