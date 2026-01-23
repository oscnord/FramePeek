import SwiftUI

struct GOPStructureView: View {
    @ObservedObject var viewModel: FramePeekViewModel
    @State private var showGOPInfoPopover = false
    @State private var selectedRangeStart: Double = 0
    @State private var selectedRangeEnd: Double = 60
    @State private var showRangePicker = false

    private var analysis: GOPAnalysisResult? { viewModel.gopAnalysis }

    private var duration: Double {
        if viewModel.durationSeconds.isFinite, viewModel.durationSeconds > 0 {
            return viewModel.durationSeconds
        }
        return 60
    }

    private var domainSeconds: Double {
        if let analysis, analysis.isPreview {
            return max(0.1, analysis.scannedUntilSeconds)
        }
        if viewModel.durationSeconds.isFinite, viewModel.durationSeconds > 0 {
            return viewModel.durationSeconds
        }
        return max(0.1, analysis?.scannedUntilSeconds ?? 0.1)
    }

    private var frameTypeStats: (iCount: Int, pCount: Int, bCount: Int, unknownCount: Int, total: Int)? {
        guard let analysis else { return nil }
        let allFrames = analysis.segments.compactMap { $0.frames }.flatMap { $0 }
        guard !allFrames.isEmpty else { return nil }

        let iCount = allFrames.filter { $0.type == .i }.count
        let pCount = allFrames.filter { $0.type == .p }.count
        let bCount = allFrames.filter { $0.type == .b }.count
        let unknownCount = allFrames.filter { $0.type == .unknown }.count

        return (iCount, pCount, bCount, unknownCount, allFrames.count)
    }

    private var hasFrameTypes: Bool {
        analysis?.segments.contains(where: { $0.frames != nil && !$0.frames!.isEmpty }) ?? false
    }

    var body: some View {
        if viewModel.isFileUnanalyzable {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headerSection

                if viewModel.isAnalyzingGOP {
                    loadingSection
                } else if analysis == nil {
                    emptySection
                } else {
                    contentSection
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                    .fill(DesignSystem.Materials.thin)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                            .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                    )
            )
            .padding(DesignSystem.Padding.lg)
            .onAppear {
                initializeRangeValues()
            }
            .onChange(of: duration) { _, _ in
                initializeRangeValues()
            }
            .sheet(isPresented: $showRangePicker) {
                GOPRangePickerSheet(
                    startTime: $selectedRangeStart,
                    endTime: $selectedRangeEnd,
                    duration: duration,
                    onAnalyze: {
                        viewModel.analyzeGOPTimeRange(selectedRangeStart...selectedRangeEnd, detectFrameTypes: true)
                        showRangePicker = false
                    },
                    onCancel: {
                        showRangePicker = false
                    }
                )
            }
        }
    }

    private func initializeRangeValues() {
        let defaultEnd = min(60.0, duration)
        selectedRangeStart = 0
        selectedRangeEnd = defaultEnd
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack(spacing: 4) {
                        Text("GOP Structure")
                            .font(.headline)

                        Button {
                            showGOPInfoPopover.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(DesignSystem.Padding.xs)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showGOPInfoPopover, arrowEdge: .top) {
                            gopInfoPopoverContent
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("GOPs (Groups of Pictures) are sequences between I-frames. They determine compression efficiency and seeking performance.")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)

                        if let analysis, !analysis.segments.isEmpty {
                            if analysis.isPreview {
                                Text("Analyzed \(analysis.segments.count) GOPs in this range. Each block shows one GOP - wider blocks last longer, taller blocks contain more frames.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("This video has \(analysis.segments.count) GOPs. Each block shows one GOP - wider blocks last longer, taller blocks contain more frames.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Spacer()

                if let analysis {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        StatPill(title: "GOPs", value: "\(analysis.stats.gopCount)")
                        if let avg = analysis.stats.avgDuration {
                            StatPill(title: "Avg", value: String(format: "%.2fs", avg))
                        }
                        if let pattern = patternInfo(stats: analysis.stats) {
                            StatPill(title: "Pattern", value: pattern.label)
                        }
                    }
                }
            }

            // Frame type legend (if frame types are shown)
            if hasFrameTypes {
                frameTypeLegend
            }
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.top, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.md)
    }

    @ViewBuilder
    private var frameTypeLegend: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            Text("Frame Types:")
                .font(.caption2)
                    .foregroundStyle(.secondary)

            frameTypeLegendItem(type: .i, color: Color(red: 0.0, green: 0.48, blue: 1.0))
            frameTypeLegendItem(type: .p, color: Color(red: 1.0, green: 0.58, blue: 0.0))
            frameTypeLegendItem(type: .b, color: Color(red: 1.0, green: 0.23, blue: 0.19))

            Spacer()
        }
    }

    @ViewBuilder
    private func frameTypeLegendItem(type: FrameType, color: Color) -> some View {
        HStack(spacing: 4) {
                        Circle()
                .fill(color)
                            .frame(width: 8, height: 8)
            Text(type.rawValue)
                .font(.caption2)
                            .fontWeight(.medium)
                    }
    }

    private func patternInfo(stats: GOPAnalysisStats) -> (label: String, color: Color)? {
        // Need at least 3 GOPs to reliably determine pattern
        guard stats.gopCount >= 3,
              let min = stats.minDuration,
              let max = stats.maxDuration,
              let avg = stats.avgDuration,
              avg > 0 else {
            return nil
        }

        let variance = (max - min) / avg
        if variance < 0.1 {
            return ("Fixed", .green)
        } else if variance < 0.5 {
            return ("Variable", .orange)
        } else {
            return ("Irregular", .red)
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        GOPStructureSkeletonView()
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.bottom, DesignSystem.Padding.lg)
    }

    // MARK: - Empty Section

    private var emptySection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "rectangle.split.3x1")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("No GOP data available")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)

            Text("Select a range to analyze or use a quick preset")
                .font(.caption)
                .foregroundStyle(.tertiary)

            quickActionsBar
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Padding.xl)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            if let analysis {
                // Visual guide
                GOPVisualGuide()

                // Main timeline visualization
                GOPTimelineView(
                    segments: analysis.segments,
                    domainSeconds: domainSeconds,
                    visibleTimeRange: viewModel.visibleTimeRange,
                    showFrameTypes: hasFrameTypes,
                    viewModel: viewModel
                ) { index in
                    viewModel.selectGOP(at: index)
                }
                .frame(height: 180)

                // Selected GOP details panel
                if let selectedIndex = viewModel.selectedGOPIndex,
                   selectedIndex < analysis.segments.count {
                    GOPDetailsPanel(
                        segment: analysis.segments[selectedIndex],
                        index: selectedIndex,
                        viewModel: viewModel
                    )
                }

                // Statistics panel
                GOPStatsPanel(
                    stats: analysis.stats,
                    frameTypeStats: frameTypeStats
                )

                // Action bar
                actionBar(analysis: analysis)
            }
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.lg)
    }

    // MARK: - Quick Actions Bar

    private var quickActionsBar: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                    presetButton("First 30s", start: 0, end: min(30, duration))
                    presetButton("First 60s", start: 0, end: min(60, duration))
                    if duration > 120 {
                        presetButton("First 2min", start: 0, end: min(120, duration))
                    }
                presetButton("Entire File", start: 0, end: duration)
            }

                    Button {
                showRangePicker = true
                    } label: {
                Label("Custom Range", systemImage: "slider.horizontal.3")
                    }
            .buttonStyle(.bordered)
                    .controlSize(.small)
        }
        .padding(DesignSystem.Padding.lg)
    }

    @ViewBuilder
    private func presetButton(_ title: String, start: Double, end: Double) -> some View {
        Button {
            viewModel.analyzeGOPTimeRange(start...end, detectFrameTypes: true)
        } label: {
            Text(title)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(analysis: GOPAnalysisResult) -> some View {
        HStack {
            Spacer()

            if analysis.isPreview {
                Button {
                    viewModel.analyzeGOPFullFile(detectFrameTypes: true)
                } label: {
                    Label("Full Analysis", systemImage: "doc.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                showRangePicker = true
            } label: {
                Label("Analyze Range", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Info Popover

    private var gopInfoPopoverContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("GOP Structure")
                .font(.headline)
                .fontWeight(.semibold)

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("What is a GOP?")
                .font(.subheadline)
                    .fontWeight(.medium)
                Text("A Group of Pictures (GOP) is a sequence of video frames between two I-frames (keyframes). The GOP structure determines how frames are encoded and affects video quality, file size, and seeking performance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Frame Types")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, DesignSystem.Padding.xs)
                VStack(alignment: .leading, spacing: 4) {
                    frameTypeExplanation(type: .i, color: Color(red: 0.0, green: 0.48, blue: 1.0), description: "Keyframes that can be decoded independently. They mark the start of each GOP and are essential for seeking.")
                    frameTypeExplanation(type: .p, color: Color(red: 1.0, green: 0.58, blue: 0.0), description: "Frames that reference the previous I or P-frame. More efficient than I-frames but require previous frames to decode.")
                    frameTypeExplanation(type: .b, color: Color(red: 1.0, green: 0.23, blue: 0.19), description: "Frames that reference both previous and future frames. Most efficient compression but require buffering.")
                }

                Text("Pattern Types")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, DesignSystem.Padding.xs)
                VStack(alignment: .leading, spacing: 4) {
                    patternExplanation(label: "Fixed", color: .green, description: "GOPs have consistent duration, indicating predictable encoding.")
                    patternExplanation(label: "Variable", color: .orange, description: "GOP durations vary moderately, common in adaptive encoding.")
                    patternExplanation(label: "Irregular", color: .red, description: "GOP durations vary significantly, may indicate encoding issues.")
                }
            }
        }
        .padding(DesignSystem.Padding.lg)
        .frame(width: 360, alignment: .leading)
    }

    @ViewBuilder
    private func frameTypeExplanation(type: FrameType, color: Color, description: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(type.rawValue)-frames")
                .font(.caption)
                .fontWeight(.medium)
        }
        Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 18)
    }

    @ViewBuilder
    private func patternExplanation(label: String, color: Color, description: String) -> some View {
                    HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                            .font(.caption)
                            .fontWeight(.medium)
                        }
        Text(description)
            .font(.caption)
                    .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 18)
    }
}

// MARK: - Skeleton View

private struct GOPStructureSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            // Visual guide skeleton
            SkeletonView(width: nil, height: 40, cornerRadius: DesignSystem.CornerRadius.small)

            // Timeline visualization skeleton
            SkeletonChart(height: 180)

            // Stats panel skeleton
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DesignSystem.Spacing.md) {
                    SkeletonCard(width: nil, height: 80)
                    SkeletonCard(width: nil, height: 80)
                    SkeletonCard(width: nil, height: 80)
                    SkeletonCard(width: nil, height: 80)
                }

                // Frame distribution skeleton
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    SkeletonText(width: 140, height: 16)
                    SkeletonView(width: nil, height: 16, cornerRadius: 4)
                    HStack(spacing: DesignSystem.Spacing.lg) {
                        SkeletonText(width: 60, height: 14)
                        SkeletonText(width: 60, height: 14)
                        SkeletonText(width: 60, height: 14)
                    }
                }
                .padding(DesignSystem.Padding.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .fill(DesignSystem.Materials.ultraThin)
                )
            }

            // Action bar skeleton
            HStack {
                Spacer()
                SkeletonText(width: 120, height: 28)
                SkeletonText(width: 120, height: 28)
            }
        }
    }
}
