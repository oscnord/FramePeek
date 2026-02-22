import SwiftUI
import FramePeekCore

struct GOPTimelineView: View {
    let segments: [GOPSegment]
    let domainSeconds: Double
    let visibleTimeRange: ClosedRange<Double>?
    let showFrameTypes: Bool
    var viewModel: FramePeekViewModel
    let onGOPClick: (Int) -> Void

    @State private var isDragging = false
    @State private var dragStartLocation: CGPoint = .zero
    @State private var selectionStartTime: Double?
    @State private var selectionEndTime: Double?

    private var effectiveDomain: (start: Double, end: Double) {
        if let range = visibleTimeRange {
            return (range.lowerBound, range.upperBound)
        }
        return (0, domainSeconds)
    }

    private var filteredSegments: [GOPSegment] {
        let domain = effectiveDomain
        return segments.filter { segment in
            segment.endTime >= domain.start && segment.startTime <= domain.end
        }
    }

    private var maxFrameCount: Int {
        filteredSegments.compactMap { $0.frameCount }.max() ?? 1
    }

    private func patternColor(for segment: GOPSegment, avgDuration: Double?) -> Color {
        guard let avg = avgDuration, avg > 0 else {
            return .secondary.opacity(0.3)
        }

        let variance = abs(segment.duration - avg) / avg

        if variance < 0.1 {
            return .green
        } else if variance < 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    /// Computes the average duration of all segments (used for pattern coloring).
    /// Computed once per body evaluation, not per segment.
    private var cachedAvgDuration: Double? {
        let durations = segments.map(\.duration).filter { $0.isFinite && $0 > 0 }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Main timeline
            VStack(spacing: 0) {
                // Use the first segment's startTime to ensure alignment between GOP blocks and frames
                let alignmentStart = filteredSegments.first?.startTime ?? effectiveDomain.start

                // GOP blocks row — compute avg duration once, not per segment
                let avgDur = cachedAvgDuration
                GOPBlocksStripView(
                    segments: segments,
                    filteredSegments: filteredSegments,
                    domainStart: alignmentStart,
                    domainEnd: effectiveDomain.end,
                    maxFrameCount: maxFrameCount,
                    selectedGOPIndex: viewModel.selectedGOPIndex,
                    patternColor: { segment in
                        patternColor(for: segment, avgDuration: avgDur)
                    },
                    onGOPClick: onGOPClick,
                    selectionStartTime: selectionStartTime,
                    selectionEndTime: selectionEndTime
                )
                .frame(height: 140)
                .padding(.horizontal, DesignSystem.Padding.md)

                // Frame type strip (if enabled and available) with label
                if showFrameTypes, segments.contains(where: { $0.frames != nil && !$0.frames!.isEmpty }) {
                    let allFrames = segments.compactMap { $0.frames }.flatMap { $0 }
                    if !allFrames.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Frame Types")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DesignSystem.Padding.md)
                                .padding(.top, DesignSystem.Padding.sm)

                            FrameTypeStripView(
                                frames: allFrames,
                                domainStart: alignmentStart,
                                domainEnd: effectiveDomain.end,
                                onFrameClick: { _ in
                                    // Could navigate to frame details
                                }
                            )
                            .frame(height: 32)
                            .padding(.horizontal, DesignSystem.Padding.md)
                        }
                    }
                }

                // Time axis with clearer labels
                timeAxis(domain: (alignmentStart, effectiveDomain.end))
                    .padding(.horizontal, DesignSystem.Padding.md)
                    .padding(.top, DesignSystem.Padding.xs)
                    .padding(.bottom, DesignSystem.Padding.sm)
            }
            .clipped()
        }
        .gesture(
            MagnifyGesture()
                .onEnded { value in
                    let currentRange = viewModel.visibleTimeRange
                    let fullDuration = domainSeconds

                    if let range = currentRange {
                        let center = (range.lowerBound + range.upperBound) / 2
                        let currentWidth = range.upperBound - range.lowerBound
                        let newWidth = currentWidth / value.magnification
                        let minWidth = fullDuration * 0.01
                        let maxWidth = fullDuration

                        let clampedWidth = max(minWidth, min(maxWidth, newWidth))
                        let newStart = max(0, center - clampedWidth / 2)
                        let newEnd = min(fullDuration, center + clampedWidth / 2)

                        if newEnd - newStart >= minWidth {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.visibleTimeRange = newStart...newEnd
                            }
                        }
                    } else {
                        let center = fullDuration / 2
                        let newWidth = fullDuration / value.magnification
                        let minWidth = fullDuration * 0.01
                        let clampedWidth = max(minWidth, min(fullDuration, newWidth))
                        let newStart = max(0, center - clampedWidth / 2)
                        let newEnd = min(fullDuration, center + clampedWidth / 2)

                        if newEnd - newStart >= minWidth {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.visibleTimeRange = newStart...newEnd
                            }
                        }
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            // Zoom controls when zoomed
            if visibleTimeRange != nil {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.visibleTimeRange = nil
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(DesignSystem.Padding.sm)
                .help(String(localized: "Reset zoom"))
            }
        }
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                // Pan when zoomed
                                if let range = viewModel.visibleTimeRange {
                                    let domain = effectiveDomain
                                    let domainDuration = max(0.001, domain.end - domain.start)
                                    let w = geometry.size.width

                                    let panRatio = Double(value.translation.width / w)
                                    let rangeWidth = range.upperBound - range.lowerBound
                                    let timeDelta = panRatio * domainDuration

                                    let newStart = max(0, range.lowerBound - timeDelta)
                                    let newEnd = min(domainSeconds, range.upperBound - timeDelta)

                                    if newEnd - newStart == rangeWidth && newStart >= 0 && newEnd <= domainSeconds {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            viewModel.visibleTimeRange = newStart...newEnd
                                        }
                                    }
                                }
                            }
                    )
            }
        }
    }

    @ViewBuilder
    private func timeAxis(domain: (start: Double, end: Double)) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let domainDuration = max(0.001, domain.end - domain.start)
            let tickCount = 5
            let labelWidth: CGFloat = 50
            let tickIndices: [Int] = (0...tickCount).map { $0 }

            ZStack(alignment: .leading) {
                // Axis line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: width, y: 0))
                }
                .stroke(DesignSystem.Colors.Chart.axisTick, lineWidth: 1)

                // Time labels
                ForEach(tickIndices, id: \.self) { i in
                    TimeAxisLabel(
                        index: i,
                        tickCount: tickCount,
                        domain: domain,
                        domainDuration: domainDuration,
                        width: width,
                        labelWidth: labelWidth,
                        formatTime: formatTime
                    )
                }
            }
        }
        .frame(height: 28)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

private struct TimeAxisLabel: View {
    let index: Int
    let tickCount: Int
    let domain: (start: Double, end: Double)
    let domainDuration: Double
    let width: CGFloat
    let labelWidth: CGFloat
    let formatTime: (Double) -> String

    private var ratio: Double {
        Double(index) / Double(tickCount)
    }

    private var time: Double {
        domain.start + ratio * domainDuration
    }

    private var x: CGFloat {
        CGFloat(ratio) * width
    }

    private var labelX: CGFloat {
        if index == 0 {
            // First label: align to left edge
            return 0
        } else if index == tickCount {
            // Last label: align to right edge
            return max(0, width - labelWidth)
        } else {
            // Middle labels: center on tick, but clamp to bounds
            return max(0, min(width - labelWidth, x - labelWidth / 2))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(formatTime(time))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
        }
        .frame(width: labelWidth, alignment: index == 0 ? .leading : (index == tickCount ? .trailing : .center))
        .offset(x: labelX, y: 4)
    }
}
