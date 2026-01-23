import SwiftUI
import Charts
import AVFoundation

struct ColorAnalysisView: View {
    @ObservedObject var viewModel: FramePeekViewModel

    private var displaySamples: [ColorSample] {
        let filteredSamples: [ColorSample]
        if let range = viewModel.visibleTimeRange {
            filteredSamples = viewModel.colorSamples.filter { range.contains($0.time) }
        } else {
            filteredSamples = viewModel.colorSamples
        }
        return filteredSamples
    }

    // MARK: - HDR Detection

    private var isHDRContent: Bool {
        viewModel.extendedInfo?.hdrFormat != nil
    }

    private var isDolbyVision: Bool {
        viewModel.extendedInfo?.hdrFormat == "Dolby Vision"
    }

    // MARK: - Statistics

    private var brightnessStats: (min: Double, max: Double, avg: Double)? {
        guard !displaySamples.isEmpty else { return nil }
        let brightnesses = displaySamples.map { $0.brightness }
        guard let min = brightnesses.min(), let max = brightnesses.max() else { return nil }
        let avg = brightnesses.reduce(0, +) / Double(brightnesses.count)
        return (min: min, max: max, avg: avg)
    }

    private var temperatureStats: (min: Double, max: Double, avg: Double)? {
        let validTemps = displaySamples.compactMap { $0.colorTemperature }
        guard !validTemps.isEmpty else { return nil }
        guard let min = validTemps.min(), let max = validTemps.max() else { return nil }
        let avg = validTemps.reduce(0, +) / Double(validTemps.count)
        return (min: min, max: max, avg: avg)
    }

    private var aggregatedHistogram: ColorHistogram? {
        let samplesWithHist = displaySamples.compactMap { $0.histogram }
        guard !samplesWithHist.isEmpty else { return nil }

        var redSum = Array(repeating: 0.0, count: 256)
        var greenSum = Array(repeating: 0.0, count: 256)
        var blueSum = Array(repeating: 0.0, count: 256)

        for hist in samplesWithHist {
            for i in 0..<256 {
                redSum[i] += hist.red[i]
                greenSum[i] += hist.green[i]
                blueSum[i] += hist.blue[i]
            }
        }

        let count = Double(samplesWithHist.count)
        return ColorHistogram(
            red: redSum.map { $0 / count },
            green: greenSum.map { $0 / count },
            blue: blueSum.map { $0 / count }
        )
    }

    var body: some View {
        if viewModel.isFileUnanalyzable {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headerSection

                if viewModel.isAnalyzingColor {
                    loadingSection
                } else if viewModel.colorSamples.isEmpty {
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
        }
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Color Analysis")
                    .font(.headline)
                if !viewModel.colorSamples.isEmpty {
                    Text("Analyzes brightness, color temperature, and RGB distribution")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }
            Spacer()

            if viewModel.colorSamples.isEmpty {
                Button {
                    if let url = viewModel.currentVideoURL {
                        let asset = AVURLAsset(url: url)
                        viewModel.startColorAnalysis(asset: asset)
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Analyze")
                    }
                }
                .disabled(viewModel.isAnalyzingColor)
                .opacity(viewModel.isAnalyzingColor ? 0.5 : 1.0)
            }
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.top, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.md)
    }

    private var loadingSection: some View {
        ColorAnalysisSkeletonView()
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.bottom, DesignSystem.Padding.lg)
    }

    private var emptySection: some View {
        Text("Click Analyze to start color analysis")
            .font(.subheadline)
            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Padding.xxl)
    }

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            if isHDRContent {
                hdrWarningBanner
            } else if let brightnessStats = brightnessStats {
                statisticsSummarySection(brightnessStats: brightnessStats)
            }

            chartsSection
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.lg)
    }

    private var chartsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            BrightnessChartView(samples: displaySamples, frameRate: viewModel.effectiveFPS)
                .overlay(alignment: .topTrailing) {
                    if isHDRContent {
                        hdrChartWarning
                    }
                }
            ColorTemperatureChartView(samples: displaySamples, frameRate: viewModel.effectiveFPS)
                .overlay(alignment: .topTrailing) {
                    if isHDRContent {
                        hdrChartWarning
                    }
                }

            if let histogram = aggregatedHistogram {
                RGBHistogramView(histogram: histogram, isHDRContent: isHDRContent, isDolbyVision: isDolbyVision)
            }
        }
    }

    // MARK: - Subviews

    private var hdrWarningBanner: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(isDolbyVision ? String(localized: "Dolby Vision Detected") : String(localized: "HDR Content Detected"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(localized: "Color analysis may be inaccurate for HDR content. Thumbnail colors do not accurately represent HDR video."))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
            Spacer()
        }
        .padding(DesignSystem.Padding.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .strokeBorder(.orange.opacity(0.3), lineWidth: DesignSystem.Borders.thin)
                )
        )
    }

    private var hdrChartWarning: some View {
        Image(systemName: "info.circle.fill")
            .font(.caption)
            .foregroundStyle(.orange.opacity(0.7))
            .padding(DesignSystem.Padding.xs)
            .help(String(localized: "Color data may be inaccurate for HDR content"))
    }

    @ViewBuilder
    private func statisticsSummarySection(brightnessStats: (min: Double, max: Double, avg: Double)) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Color Metrics")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                if let tempStats = temperatureStats {
                    ColorSummaryItem(
                        label: String(localized: "Brightness"),
                        value: String(format: "%.1f%%", brightnessStats.avg * 100),
                        icon: "sun.max",
                        detail: String(format: String(localized: "Min: %.1f%% • Max: %.1f%%"), brightnessStats.min * 100, brightnessStats.max * 100)
                    )
                    ColorSummaryItem(
                        label: String(localized: "Temperature"),
                        value: String(format: "%.0f K", tempStats.avg),
                        icon: "thermometer",
                        detail: String(format: String(localized: "Min: %.0f K • Max: %.0f K"), tempStats.min, tempStats.max)
                    )
                } else {
                    ColorSummaryItem(
                        label: String(localized: "Brightness"),
                        value: String(format: "%.1f%%", brightnessStats.avg * 100),
                        icon: "sun.max",
                        detail: String(format: String(localized: "Min: %.1f%% • Max: %.1f%%"), brightnessStats.min * 100, brightnessStats.max * 100)
                    )
                }
            }
        }
    }
}

// MARK: - Color Summary Item with Detail

struct ColorSummaryItem: View {
    let label: String
    let value: String
    let icon: String
    let detail: String?

    init(label: String, value: String, icon: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.icon = icon
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let detail = detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
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
}

// MARK: - Skeleton View

private struct ColorAnalysisSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            // Statistics summary skeleton
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                SkeletonText(width: 120, height: 16)

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

            // Charts skeleton
            VStack(spacing: DesignSystem.Spacing.md) {
                SkeletonChart(height: 200)
                SkeletonChart(height: 200)
                SkeletonChart(height: 200)
            }
        }
    }
}
