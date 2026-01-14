import SwiftUI
import Charts

struct SyncAnalysisView: View {
    @ObservedObject var viewModel: FramePeekViewModel
    @State private var showFrameIntervalInfoPopover = false
    
    private var displaySamples: [FrameTimingSample] {
        let filteredSamples: [FrameTimingSample]
        if let range = viewModel.visibleTimeRange {
            filteredSamples = viewModel.frameTimingSamples.filter { range.contains($0.time) }
        } else {
            filteredSamples = viewModel.frameTimingSamples
        }
        return downsampleFrameTiming(filteredSamples, targetCount: 500)
    }
    
    private var frameIntervalStats: (min: Double, max: Double, avg: Double, stdDev: Double)? {
        guard !viewModel.frameTimingSamples.isEmpty else { return nil }
        let intervals = viewModel.frameTimingSamples.map { $0.intervalMs }
        let min = intervals.min() ?? 0
        let max = intervals.max() ?? 0
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - avg, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        return (min: min, max: max, avg: avg, stdDev: stdDev)
    }
    
    private var frameRateInfo: String {
        if let metadataFrameRate = viewModel.extendedInfo?.frameRate,
           metadataFrameRate != "N/A",
           !metadataFrameRate.isEmpty {
            return metadataFrameRate
        }
        
        guard let result = viewModel.syncAnalysisResult,
              let avgInterval = result.averageVideoFrameInterval,
              avgInterval > 0 else { return "N/A" }
        let fps = 1.0 / avgInterval
        return String(format: "%.2f fps", fps)
    }
    
    private var frameRateMode: String {
        guard let result = viewModel.syncAnalysisResult else { return "N/A" }
        return result.isVariableFrameRate ? "VFR" : "CFR"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            
            if viewModel.isAnalyzingSync {
                loadingSection
            } else if let result = viewModel.syncAnalysisResult {
                contentSection(result)
            } else {
                emptySection
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
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Audio/Video Sync")
                    .font(.headline)
                if viewModel.syncAnalysisResult != nil {
                    Text("Measures timing alignment between audio and video tracks")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }
            Spacer()
            if let result = viewModel.syncAnalysisResult {
                syncStatusBadge(result.overallSyncStatus)
            }
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.top, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.md)
    }
    
    private var loadingSection: some View {
        SyncAnalysisSkeletonView()
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.bottom, DesignSystem.Padding.lg)
    }
    
    private var emptySection: some View {
        Text("No sync data available")
            .font(.subheadline)
            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Padding.xxl)
    }
    
    @ViewBuilder
    private func contentSection(_ result: SyncAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            primaryMetricsSection(result)
            
            secondaryMetricsSection(result)
            
            if !viewModel.frameTimingSamples.isEmpty {
                frameTimingChartSection
            }
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.lg)
    }
    
    @ViewBuilder
    private func syncStatusBadge(_ status: SyncStatus) -> some View {
        let (color, icon) = statusAppearance(status)
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.4), lineWidth: DesignSystem.Borders.thin)
        )
    }
    
    private func statusAppearance(_ status: SyncStatus) -> (Color, String) {
        switch status {
        case .inSync:
            return (.green, "checkmark.circle.fill")
        case .minorOffset:
            return (.yellow, "exclamationmark.circle.fill")
        case .significantOffset:
            return (.orange, "exclamationmark.triangle.fill")
        case .durationMismatch:
            return (.red, "clock.badge.exclamationmark.fill")
        case .noAudio:
            return (.secondary, "speaker.slash.fill")
        case .noVideo:
            return (.secondary, "video.slash.fill")
        case .analysisError:
            return (.red, "xmark.circle.fill")
        }
    }
    
    @ViewBuilder
    private func primaryMetricsSection(_ result: SyncAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Sync Metrics")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            if result.audioTracks.isEmpty {
                Text("No audio tracks found")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .padding(.vertical, DesignSystem.Padding.sm)
            } else if result.audioTracks.count == 1, let track = result.audioTracks.first {
            HStack(spacing: DesignSystem.Spacing.md) {
                primaryMetricCard(
                    title: "A/V Sync Offset",
                        value: String(format: "%.1f ms", track.syncOffsetMs),
                        subtitle: track.syncOffsetMs > 0 ? "audio ahead" : (track.syncOffsetMs < 0 ? "video ahead" : "in sync"),
                        isHighlighted: abs(track.syncOffsetMs) > 40,
                        icon: abs(track.syncOffsetMs) > 40 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                
                primaryMetricCard(
                    title: "Duration Δ",
                        value: String(format: "%.1f ms", track.durationDifferenceMs),
                        subtitle: abs(track.durationDifferenceMs) < 1 ? "identical" : nil,
                        isHighlighted: abs(track.durationDifferenceMs) > 100,
                        icon: abs(track.durationDifferenceMs) > 100 ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill"
                    )
                }
            } else {
                compactTracksView(result)
            }
        }
    }
    
    @ViewBuilder
    private func compactTracksView(_ result: SyncAnalysisResult) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(Array(result.audioTracks.enumerated()), id: \.element.trackIndex) { _, track in
                compactTrackRow(track: track, trackInfo: getAudioTrackInfo(for: track.trackIndex))
            }
        }
    }
    
    @ViewBuilder
    private func compactTrackRow(track: AudioTrackSyncInfo, trackInfo: AudioTrackInfo?) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(trackInfo != nil ? "Track \(trackInfo!.index)" : "Track \(track.trackIndex + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let info = trackInfo {
                    Text("• \(info.codecDisplayName)")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.md) {
                compactMetric(
                    label: "Offset",
                    value: String(format: "%.1f ms", track.syncOffsetMs),
                    subtitle: track.syncOffsetMs > 0 ? "audio ahead" : (track.syncOffsetMs < 0 ? "video ahead" : "in sync"),
                    isHighlighted: abs(track.syncOffsetMs) > 40
                )
                
                compactMetric(
                    label: "Duration Δ",
                    value: String(format: "%.1f ms", track.durationDifferenceMs),
                    isHighlighted: abs(track.durationDifferenceMs) > 100
                )
            }
        }
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .strokeBorder(.separator.opacity(0.2), lineWidth: DesignSystem.Borders.thin)
                )
        )
    }
    
    @ViewBuilder
    private func compactMetric(label: String, value: String, subtitle: String? = nil, isHighlighted: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(isHighlighted ? .orange : .primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isHighlighted ? .orange.opacity(0.8) : DesignSystem.Colors.Semantic.secondary)
                }
            }
        }
    }
    
    private func getAudioTrackInfo(for trackIndex: Int) -> AudioTrackInfo? {
        guard let audioTracks = viewModel.extendedInfo?.audioTracks,
              trackIndex < audioTracks.count else {
            return nil
        }
        return audioTracks[trackIndex]
    }
    
    
    @ViewBuilder
    private func secondaryMetricsSection(_ result: SyncAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Track Information")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                metricCard(
                    title: "Frame Rate",
                    value: frameRateInfo,
                    subtitle: frameRateMode,
                    isHighlighted: viewModel.syncAnalysisResult?.isVariableFrameRate ?? false
                )
                
                metricCard(
                    title: "Video Duration",
                    value: formatDuration(result.videoDuration)
                )
                
                if result.audioTracks.count == 1, let track = result.audioTracks.first {
                metricCard(
                    title: "Audio Duration",
                        value: formatDuration(track.audioDuration)
                    )
                } else {
                    metricCard(
                        title: "Audio Tracks",
                        value: "\(result.audioTracks.count)"
                    )
                }
                
                metricCard(
                    title: "Frames Analyzed",
                    value: "\(result.videoFrameCount.formatted())"
                )
            }
        }
    }
    
    @ViewBuilder
    private func primaryMetricCard(title: String, value: String, subtitle: String? = nil, isHighlighted: Bool = false, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(isHighlighted ? .orange : .green)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                Text(value)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(isHighlighted ? .orange : .primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? .orange.opacity(0.8) : DesignSystem.Colors.Semantic.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Padding.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .strokeBorder(isHighlighted ? .orange.opacity(0.3) : .clear, lineWidth: DesignSystem.Borders.thin)
                )
        )
    }
    
    @ViewBuilder
    private func metricCard(title: String, value: String, subtitle: String? = nil, isHighlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(isHighlighted ? .orange : .primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isHighlighted ? .orange.opacity(0.8) : DesignSystem.Colors.Semantic.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Padding.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
        )
    }
    
    private var frameTimingChartSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack(spacing: 4) {
                        Text("Frame Intervals")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Button {
                            showFrameIntervalInfoPopover.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(DesignSystem.Padding.xs)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showFrameIntervalInfoPopover, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Text("Frame Intervals")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                    Text("X-Axis (Time)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Represents the timeline of the video in seconds.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Text("Y-Axis (Interval in ms)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.top, DesignSystem.Padding.xs)
                                    Text("Shows the time between consecutive video frames in milliseconds. Lower values indicate faster frame rates.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Text("Average Line")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.top, DesignSystem.Padding.xs)
                                    Text("The dashed line shows the average frame interval. Consistent intervals indicate constant frame rate (CFR), while varying intervals indicate variable frame rate (VFR).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Text("Statistics")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.top, DesignSystem.Padding.xs)
                                    Text("Min, Avg, Max show the minimum, average, and maximum frame intervals. σ (sigma) represents the standard deviation, indicating frame rate variability.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(DesignSystem.Padding.lg)
                            .frame(width: 320, alignment: .leading)
                        }
                    }
                    Text("Time between consecutive video frames")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
                Spacer()
                
                if let stats = frameIntervalStats {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        StatPill(title: "Min", value: String(format: "%.1f ms", stats.min))
                        StatPill(title: "Avg", value: String(format: "%.1f ms", stats.avg))
                        StatPill(title: "Max", value: String(format: "%.1f ms", stats.max))
                        if stats.stdDev > 0.1 {
                            StatPill(title: "σ", value: String(format: "%.2f ms", stats.stdDev))
                        }
                    }
                }
                
                if let result = viewModel.syncAnalysisResult, result.isVariableFrameRate {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("VFR")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, DesignSystem.Padding.sm)
                    .padding(.vertical, DesignSystem.Padding.xs)
                    .background(.orange.opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.orange.opacity(0.4), lineWidth: DesignSystem.Borders.thin)
                    )
                }
            }
            
            Chart {
                ForEach(displaySamples) { sample in
                    LineMark(
                        x: .value("Time (s)", sample.time),
                        y: .value("Interval (ms)", sample.intervalMs)
                    )
                    .foregroundStyle(DesignSystem.Colors.Chart.primary)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.medium))
                }
                
                if let stats = frameIntervalStats {
                    RuleMark(y: .value("Average", stats.avg))
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
                    
                    if stats.max - stats.min > 1.0 {
                        RuleMark(y: .value("Min", stats.min))
                            .foregroundStyle(.green.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.thin, dash: [2, 2]))
                        
                        RuleMark(y: .value("Max", stats.max))
                            .foregroundStyle(.red.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.thin, dash: [2, 2]))
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXScale(domain: viewModel.visibleTimeRange ?? (0...(viewModel.frameTimingSamples.last?.time ?? 1)))
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
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
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(DesignSystem.Colors.Chart.gridY)
                    AxisTick().foregroundStyle(DesignSystem.Colors.Chart.axisTick)
                    AxisValueLabel {
                        if let ms = value.as(Double.self) {
                            Text("\(ms, specifier: "%.1f")")
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
            .frame(height: 200)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, ms)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, secs, ms)
        }
    }
}

private func downsampleFrameTiming(_ samples: [FrameTimingSample], targetCount: Int) -> [FrameTimingSample] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }
    
    var result: [FrameTimingSample] = []
    result.reserveCapacity(targetCount)
    
    result.append(samples[0])
    
    let bucketSize = Double(samples.count - 2) / Double(targetCount - 2)
    var lastSelectedIndex = 0
    
    for i in 0..<(targetCount - 2) {
        let bucketStart = Int(Double(i) * bucketSize) + 1
        let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, samples.count - 1)
        
        let nextBucketStart = bucketEnd
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, samples.count - 1)
        
        var avgX: Double = 0
        var avgY: Double = 0
        let nextBucketCount = nextBucketEnd - nextBucketStart + 1
        
        for j in nextBucketStart...nextBucketEnd {
            avgX += samples[j].time
            avgY += samples[j].intervalMs
        }
        avgX /= Double(nextBucketCount)
        avgY /= Double(nextBucketCount)
        
        var maxArea: Double = -1
        var maxAreaIndex = bucketStart
        
        let pointA = samples[lastSelectedIndex]
        
        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            let area = abs(
                (pointA.time - avgX) * (pointB.intervalMs - pointA.intervalMs) -
                (pointA.time - pointB.time) * (avgY - pointA.intervalMs)
            ) * 0.5
            
            if area > maxArea {
                maxArea = area
                maxAreaIndex = j
            }
        }
        
        result.append(samples[maxAreaIndex])
        lastSelectedIndex = maxAreaIndex
    }
    
    result.append(samples[samples.count - 1])
    
    return result
}

// MARK: - Skeleton View

private struct SyncAnalysisSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            // Primary metrics skeleton
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                SkeletonText(width: 120, height: 16)
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    SkeletonCard(width: nil, height: 100)
                    SkeletonCard(width: nil, height: 100)
                }
            }
            
            // Secondary metrics skeleton
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                SkeletonText(width: 140, height: 16)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DesignSystem.Spacing.md) {
                    SkeletonCard(width: nil, height: 70)
                    SkeletonCard(width: nil, height: 70)
                    SkeletonCard(width: nil, height: 70)
                }
            }
            
            // Chart skeleton
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    SkeletonText(width: 150, height: 16)
                    Spacer()
                    HStack(spacing: DesignSystem.Spacing.md) {
                        SkeletonText(width: 50, height: 20)
                        SkeletonText(width: 50, height: 20)
                        SkeletonText(width: 50, height: 20)
                    }
                }
                
                SkeletonChart(height: 200)
            }
        }
    }
}
