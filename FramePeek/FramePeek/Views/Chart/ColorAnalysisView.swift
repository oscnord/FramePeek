import SwiftUI
import Charts
import AVFoundation

struct ColorAnalysisView: View {
    @ObservedObject var viewModel: FramePeekViewModel
    
    @AppStorage("waveformScale") private var waveformScaleRaw: String = WaveformScale.percentage.rawValue
    @AppStorage("vectorscopeShowReferenceBoxes") private var showReferenceBoxes: Bool = true
    @AppStorage("generateWaveformData") private var generateWaveformData: Bool = true
    @AppStorage("generateVectorscopeData") private var generateVectorscopeData: Bool = true
    


    private var displaySamples: [ColorSample] {
        let filteredSamples: [ColorSample]
        if let range = viewModel.visibleTimeRange {
            filteredSamples = viewModel.colorSamples.filter { range.contains($0.time) }
        } else {
            filteredSamples = viewModel.colorSamples
        }
        return filteredSamples
    }
    
    private var waveformScale: WaveformScale {
        WaveformScale(rawValue: waveformScaleRaw) ?? .percentage
    }

    // MARK: - HDR Detection

    private var isHDRContent: Bool {
        viewModel.hdrContentType.isHDR
    }

    private var isDolbyVision: Bool {
        viewModel.hdrContentType == .dolbyVision
    }

    // MARK: - Statistics from Professional Analysis

    private var professionalStats: AggregatedColorStats? {
        viewModel.aggregatedColorStats
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
            .task {
                // Detect HDR type when view appears
                await viewModel.detectHDRType()
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Color Analysis")
                        .font(.headline)
                    
                    if isHDRContent {
                        hdrBadge
                    }
                }
                
                if !viewModel.colorSamples.isEmpty {
                    Text("Color metrics, scopes, and distribution")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }
            Spacer()

            if !viewModel.isAnalyzingColor && viewModel.colorSamples.isEmpty {
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
            }
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.top, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.md)
    }
    
    private var hdrBadge: some View {
        Text(viewModel.hdrContentType.displayName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDolbyVision ? Color.purple : Color.orange)
            )
    }

    private var loadingSection: some View {
        HStack {
            Spacer()
            LoadingView(
                message: String(localized: "Analyzing..."),
                progress: viewModel.colorAnalysisProgress
            )
            Spacer()
        }
        .padding(.vertical, DesignSystem.Padding.lg)
    }

    private var emptySection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.5))
            
            Text("Click Analyze to start color analysis")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            
            if generateWaveformData || generateVectorscopeData {
                Text("Includes waveform, vectorscope, and color metrics")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Padding.xxl)
    }

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg2) {
            if isHDRContent {
                hdrWarningBanner
            }
            
            // Professional metrics
            if let stats = professionalStats {
                professionalMetricsSection(stats: stats)
            }
            
            // Scopes section (Waveform & Vectorscope)
            if generateWaveformData || generateVectorscopeData {
                scopesSection
            }

            chartsSection
        }
        .padding(.horizontal, DesignSystem.Padding.lg)
        .padding(.bottom, DesignSystem.Padding.lg)
    }
    
    // MARK: - Metrics Section
    
    @ViewBuilder
    private func professionalMetricsSection(stats: AggregatedColorStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Color Metrics")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                ColorSummaryItem(
                    label: String(localized: "Luminance"),
                    value: String(format: "%.1f%%", stats.luminanceAvg * 100),
                    icon: "sun.max",
                    detail: String(format: String(localized: "%.0f%% - %.0f%%"), stats.luminanceMin * 100, stats.luminanceMax * 100)
                )
                
                ColorSummaryItem(
                    label: String(localized: "Contrast"),
                    value: formatContrastRatio(stats.contrastRatio),
                    icon: "circle.lefthalf.filled",
                    detail: nil
                )
                
                ColorSummaryItem(
                    label: String(localized: "Saturation"),
                    value: String(format: "%.0f%%", stats.saturationAvg * 100),
                    icon: "paintpalette",
                    detail: nil
                )
                
                if let cctAvg = stats.cctAvg, !isHDRContent {
                    ColorSummaryItem(
                        label: String(localized: "CCT"),
                        value: String(format: "%.0f K", cctAvg),
                        icon: "thermometer",
                        detail: cctDescription(cctAvg)
                    )
                } else {
                    ColorSummaryItem(
                        label: String(localized: "CCT"),
                        value: isHDRContent ? "N/A" : "-",
                        icon: "thermometer",
                        detail: isHDRContent ? String(localized: "HDR") : nil
                    )
                }
            }
        }
    }
    
    private func formatContrastRatio(_ ratio: Double) -> String {
        if ratio >= 1000 {
            return String(format: "%.1fK:1", ratio / 1000)
        } else if ratio >= 100 {
            return String(format: "%.0f:1", ratio)
        } else {
            return String(format: "%.1f:1", ratio)
        }
    }
    
    private func cctDescription(_ cct: Double) -> String? {
        if cct < 3500 {
            return String(localized: "Warm")
        } else if cct < 5000 {
            return String(localized: "Neutral")
        } else if cct < 6500 {
            return String(localized: "Daylight")
        } else {
            return String(localized: "Cool")
        }
    }
    
    // MARK: - Scopes Section
    
    private var scopesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Scopes")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Side-by-side Waveform and Vectorscope
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                // Waveform (flexible width - takes remaining space)
                if generateWaveformData {
                    if let waveformData = viewModel.latestWaveformData {
                        WaveformScopeView(
                            waveformData: waveformData,
                            scale: waveformScale,
                            isHDR: isHDRContent,
                            height: 200
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        scopeNoDataView(type: "Waveform")
                            .frame(maxWidth: .infinity)
                    }
                }
                
                // Vectorscope (fixed square)
                if generateVectorscopeData {
                    if let vectorscopeData = viewModel.latestVectorscopeData {
                        VectorscopeView(
                            vectorscopeData: vectorscopeData,
                            showReferenceBoxes: showReferenceBoxes,
                            size: 200
                        )
                    } else {
                        scopeNoDataView(type: "Vectorscope")
                            .frame(width: 200, height: 200)
                    }
                }
            }
            
            // Histogram below
            if let histogram = aggregatedHistogram {
                RGBHistogramView(histogram: histogram, isHDRContent: isHDRContent, isDolbyVision: isDolbyVision)
            }
        }
    }
    
    private func scopeDisabledView(type: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "gear")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.5))
            Text("\(type) generation is disabled in settings")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }
    
    private func scopeNoDataView(type: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "waveform.slash")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.5))
            Text("No \(type.lowercased()) data available")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Timeline")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                BrightnessChartView(samples: displaySamples, frameRate: viewModel.effectiveFPS)
                    .overlay(alignment: .topTrailing) {
                        if isHDRContent {
                            hdrChartWarning
                        }
                    }
                
                if !isHDRContent {
                    ColorTemperatureChartView(samples: displaySamples, frameRate: viewModel.effectiveFPS)
                }
            }
        }
    }

    // MARK: - Subviews

    private var hdrWarningBanner: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(isDolbyVision ? String(localized: "Dolby Vision Content") : String(localized: "HDR Content"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(localized: "Some analysis features are limited. Color temperature is unavailable. Scopes show tone-mapped representation."))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                
                if let dvConfig = viewModel.dolbyVisionConfig {
                    Text("Profile \(dvConfig.profile) • Level \(dvConfig.level) • \(dvConfig.codecString)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                }
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
            .help(String(localized: "Data from tone-mapped representation"))
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
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DesignSystem.Spacing.md) {
                    SkeletonCard(width: nil, height: 70)
                    SkeletonCard(width: nil, height: 70)
                    SkeletonCard(width: nil, height: 70)
                    SkeletonCard(width: nil, height: 70)
                }
            }

            // Scopes skeleton
            SkeletonChart(height: 220)
            
            // Charts skeleton
            VStack(spacing: DesignSystem.Spacing.md) {
                SkeletonChart(height: 150)
                SkeletonChart(height: 150)
            }
        }
    }
}
