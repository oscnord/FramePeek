import SwiftUI
import AppKit
import FramePeekCore

// MARK: - GOP Heatmap Configuration

private enum HeatmapConfig {
    static let maxDisplayGOPs = 2000
    static let minGOPWidth: CGFloat = 3
    static let rowHeight: CGFloat = 80
    static let frameTypeRowHeight: CGFloat = 20
    static let miniMapHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 2
    static let gopSpacing: CGFloat = 1
    static let labelHeight: CGFloat = 16
}

// MARK: - GOP Duration Category

private enum GOPDurationCategory {
    case consistent    // Within 10% of average
    case slightlyLong  // 10-30% longer
    case slightlyShort // 10-30% shorter
    case long          // >30% longer
    case short         // >30% shorter

    var color: Color {
        switch self {
        case .consistent: return Color(red: 0.3, green: 0.7, blue: 0.4)    // Soft green
        case .slightlyLong: return Color(red: 0.4, green: 0.6, blue: 0.8)  // Soft blue
        case .slightlyShort: return Color(red: 0.9, green: 0.7, blue: 0.3) // Soft yellow
        case .long: return Color(red: 0.3, green: 0.5, blue: 0.9)          // Blue
        case .short: return Color(red: 0.9, green: 0.5, blue: 0.3)         // Orange
        }
    }

    static func from(variance: Double) -> GOPDurationCategory {
        if abs(variance) < 0.1 {
            return .consistent
        } else if variance > 0.3 {
            return .long
        } else if variance < -0.3 {
            return .short
        } else if variance > 0 {
            return .slightlyLong
        } else {
            return .slightlyShort
        }
    }
}

// MARK: - Processed GOP for Display

struct DisplayGOP: Identifiable {
    let id: UUID
    let startTime: Double
    let endTime: Double
    let duration: Double
    let frameCount: Int
    let iFrameRatio: Double
    let pFrameRatio: Double
    let bFrameRatio: Double
    let originalIndices: ClosedRange<Int>
    let isAggregated: Bool
    let durationVariance: Double // 0 = matches avg, >0 = longer, <0 = shorter

    var hasFrameTypes: Bool {
        iFrameRatio > 0 || pFrameRatio > 0 || bFrameRatio > 0
    }
}

// MARK: - GOP Heatmap View

struct GOPHeatmapView: View {
    let segments: [GOPSegment]
    let domainSeconds: Double
    let visibleTimeRange: ClosedRange<Double>?
    var viewModel: FramePeekViewModel
    let onGOPSelect: (Int) -> Void

    @State private var hoveredGOP: DisplayGOP?
    @State private var hoverLocation: CGPoint = .zero
    @State private var containerSize: CGSize = .zero

    // Cached displayGOPs to avoid recomputing on every render
    @State private var cachedDisplayGOPs: [DisplayGOP] = []
    @State private var lastDisplayGOPsInputHash: Int = 0

    // Tooltip dimensions (approximate)
    private let tooltipWidth: CGFloat = 180
    private let tooltipHeight: CGFloat = 180

    // MARK: - Computed Properties

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

    private var displayGOPsInputHash: Int {
        var hasher = Hasher()
        hasher.combine(segments.count)
        hasher.combine(visibleTimeRange?.lowerBound)
        hasher.combine(visibleTimeRange?.upperBound)
        // Also include the last segment's end time to detect data changes at same count
        if let last = segments.last {
            hasher.combine(last.endTime)
        }
        return hasher.finalize()
    }

    private func recomputeDisplayGOPs() {
        cachedDisplayGOPs = prepareDisplayGOPs(
            segments: filteredSegments,
            allSegments: segments,
            maxCount: HeatmapConfig.maxDisplayGOPs,
            domain: effectiveDomain
        )
        lastDisplayGOPsInputHash = displayGOPsInputHash
    }

    private var stats: GOPStats {
        calculateStats(segments: filteredSegments)
    }

    private var hasFrameTypes: Bool {
        segments.contains { $0.frames != nil && !($0.frames?.isEmpty ?? true) }
    }
    
    // MARK: - Tooltip Positioning
    
    /// Calculates horizontal offset for tooltip to keep it within bounds
    private var tooltipXOffset: CGFloat {
        let cursorX = hoverLocation.x
        let padding: CGFloat = 12
        
        // Default: position to the right of cursor
        var x = cursorX + padding
        
        // If tooltip would go off right edge, position to the left of cursor
        if x + tooltipWidth > containerSize.width {
            x = cursorX - tooltipWidth - padding
        }
        
        // Ensure we don't go off the left edge either
        return max(0, x)
    }
    
    /// Calculates vertical offset for tooltip to keep it within bounds
    private var tooltipYOffset: CGFloat {
        let cursorY = hoverLocation.y
        let padding: CGFloat = 8
        
        // Default: position above cursor
        var y = cursorY - tooltipHeight - padding
        
        // If tooltip would go off top edge, position below cursor
        if y < 0 {
            y = cursorY + padding
        }
        
        // If it would still go off bottom, clamp to visible area
        if y + tooltipHeight > containerSize.height {
            y = max(0, containerSize.height - tooltipHeight)
        }
        
        return y
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Mini-map (overview of entire timeline)
            if visibleTimeRange != nil {
                miniMapView
                    .frame(height: HeatmapConfig.miniMapHeight)
                    .padding(.horizontal, DesignSystem.Padding.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)
            }

            // Main heatmap
            mainHeatmapView
                .frame(height: HeatmapConfig.rowHeight + (hasFrameTypes ? HeatmapConfig.frameTypeRowHeight + 8 : 0))
                .padding(.horizontal, DesignSystem.Padding.md)

            // Time axis
            timeAxisView
                .frame(height: 24)
                .padding(.horizontal, DesignSystem.Padding.md)
                .padding(.top, DesignSystem.Spacing.xs)
        }
        .overlay(alignment: .topLeading) {
            if let gop = hoveredGOP {
                tooltipView(for: gop)
                    .offset(x: tooltipXOffset, y: tooltipYOffset)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in containerSize = newSize }
            }
        )
        .gesture(zoomGesture)
        .gesture(panGesture)
        .onAppear {
            recomputeDisplayGOPs()
            triggerPreload()
        }
        .onChange(of: segments.count) { _, _ in
            let hash = displayGOPsInputHash
            if hash != lastDisplayGOPsInputHash {
                recomputeDisplayGOPs()
            }
        }
        .onChange(of: visibleTimeRange) { _, _ in
            recomputeDisplayGOPs()
            triggerPreload()
        }
        .onChange(of: viewModel.isAnalyzingGOP) { wasAnalyzing, isAnalyzing in
            // Trigger preload when analysis completes
            if wasAnalyzing && !isAnalyzing {
                triggerPreload()
            }
        }
    }
    
    // MARK: - Preload
    
    private func triggerPreload() {
        let visibleIndices = cachedDisplayGOPs.flatMap { gop in
            Array(gop.originalIndices)
        }
        viewModel.preloadFrameDetailsForVisibleGOPs(indices: visibleIndices)
    }

    // MARK: - Mini-map View

    private var miniMapView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                // Full timeline background
                Canvas { context, size in
                    drawMiniMap(context: context, size: size, segments: segments, domain: (0, domainSeconds))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Visible range indicator
                if let range = visibleTimeRange {
                    let startRatio = range.lowerBound / domainSeconds
                    let endRatio = range.upperBound / domainSeconds
                    let x = CGFloat(startRatio) * width
                    let w = CGFloat(endRatio - startRatio) * width

                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .frame(width: max(10, w), height: height)
                        .offset(x: x - (width - max(10, w)) / 2)
                }
            }
        }
    }

    private func drawMiniMap(context: GraphicsContext, size: CGSize, segments: [GOPSegment], domain: (start: Double, end: Double)) {
        let width = size.width
        let height = size.height
        let domainDuration = max(0.001, domain.end - domain.start)

        // Background
        let bgPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
        context.fill(bgPath, with: .color(Color.secondary.opacity(0.08)))

        // Draw GOPs as simple bars with duration-based coloring
        let stats = calculateStats(segments: segments)
        for segment in segments {
            let startRatio = max(0, (segment.startTime - domain.start) / domainDuration)
            let endRatio = min(1, (segment.endTime - domain.start) / domainDuration)
            let x = CGFloat(startRatio) * width
            let w = max(1, CGFloat(endRatio - startRatio) * width - 0.5)

            let variance = stats.avgDuration > 0 ? (segment.duration - stats.avgDuration) / stats.avgDuration : 0
            let category = GOPDurationCategory.from(variance: variance)

            let rect = CGRect(x: x, y: 2, width: w, height: height - 4)
            context.fill(Path(rect), with: .color(category.color.opacity(0.7)))
        }
    }

    // MARK: - Main Heatmap View

    private var mainHeatmapView: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .topLeading) {
                // GOP blocks layer
                Canvas { context, size in
                    drawGOPBlocks(context: context, size: size)
                }
                .frame(height: HeatmapConfig.rowHeight)
                .drawingGroup()

                // Frame types layer (if available)
                if hasFrameTypes {
                    Canvas { context, size in
                        drawFrameTypes(context: context, size: size)
                    }
                    .frame(height: HeatmapConfig.frameTypeRowHeight)
                    .offset(y: HeatmapConfig.rowHeight + 8)
                    .drawingGroup()
                }

                // Interaction layer
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            NSCursor.pointingHand.push()
                            handleHover(at: location, width: width)
                        case .ended:
                            NSCursor.pop()
                            hoveredGOP = nil
                        }
                    }
                    .onTapGesture {
                        // Click to select GOP
                        if let gop = hoveredGOP {
                            onGOPSelect(gop.originalIndices.lowerBound)
                        }
                    }
                    .accessibilityAddTraits(.isButton)

                // Selection indicator - top accent bar
                if let selectedIndex = viewModel.selectedGOPIndex,
                   let gop = cachedDisplayGOPs.first(where: { $0.originalIndices.contains(selectedIndex) }) {
                    selectionIndicator(for: gop, width: width)
                }
                
                // Cross-chart sync indicator line
                if let syncTime = viewModel.hoveredTimestamp {
                    crossChartSyncIndicator(time: syncTime, width: width, height: geo.size.height)
                }
            }
        }
    }
    
    // MARK: - Cross-Chart Sync Indicator
    
    @ViewBuilder
    private func crossChartSyncIndicator(time: Double, width: CGFloat, height: CGFloat) -> some View {
        let domain = effectiveDomain
        let domainDuration = max(0.001, domain.end - domain.start)
        
        // Only show if time is within visible range
        if time >= domain.start && time <= domain.end {
            let ratio = (time - domain.start) / domainDuration
            let x = CGFloat(ratio) * width
            
            Rectangle()
                .fill(DesignSystem.Colors.Chart.hoveredLine)
                .frame(width: 2, height: height)
                .offset(x: x - 1)
                .allowsHitTesting(false)
        }
    }

    private func drawGOPBlocks(context: GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let domain = effectiveDomain
        let domainDuration = max(0.001, domain.end - domain.start)

        // Reserve space for frame count labels at top
        let chartTop: CGFloat = HeatmapConfig.labelHeight
        let chartHeight = height - chartTop

        let maxFrames = max(1, cachedDisplayGOPs.map(\.frameCount).max() ?? 1)

        for gop in cachedDisplayGOPs {
            let startRatio = max(0, (gop.startTime - domain.start) / domainDuration)
            let endRatio = min(1, (gop.endTime - domain.start) / domainDuration)
            let x = CGFloat(startRatio) * width
            let w = max(HeatmapConfig.minGOPWidth, CGFloat(endRatio - startRatio) * width - HeatmapConfig.gopSpacing)

            // Height based on frame count (minimum 40% height for visibility)
            let heightRatio = CGFloat(gop.frameCount) / CGFloat(maxFrames)
            let barHeight = max(chartHeight * 0.4, chartHeight * heightRatio)
            let y = chartTop + (chartHeight - barHeight)

            // Color based on duration category
            let category = GOPDurationCategory.from(variance: gop.durationVariance)
            let baseColor = category.color
            let isHovered = hoveredGOP?.id == gop.id
            let isSelected = viewModel.selectedGOPIndex.map { gop.originalIndices.contains($0) } ?? false

            let rect = CGRect(x: x, y: y, width: w, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: HeatmapConfig.cornerRadius)

            // Fill - use gradient for depth
            let topColor = isHovered ? baseColor.opacity(1.0) : baseColor.opacity(0.85)
            let bottomColor = isHovered ? baseColor.opacity(0.8) : baseColor.opacity(0.5)
            let gradient = Gradient(colors: [topColor, bottomColor])
            context.fill(path, with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: x, y: y),
                endPoint: CGPoint(x: x, y: y + barHeight)
            ))

            // Border for selected/hovered
            if isSelected {
                context.stroke(path, with: .color(Color.accentColor), lineWidth: 2)
            } else if isHovered {
                context.stroke(path, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)
            } else {
                context.stroke(path, with: .color(baseColor.opacity(0.3)), lineWidth: 0.5)
            }

            // I-frame indicator line at start of GOP
            let iFrameLine = Path { p in
                p.move(to: CGPoint(x: x + 1, y: y))
                p.addLine(to: CGPoint(x: x + 1, y: y + barHeight))
            }
            context.stroke(iFrameLine, with: .color(FrameTypeColors.i.opacity(0.9)), lineWidth: 2)

            // Frame count label (only if enough space)
            if w > 20 && !gop.isAggregated {
                let frameCountText = Text("\(gop.frameCount)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                context.draw(frameCountText, at: CGPoint(x: x + w / 2, y: y + 10))
            }

            // Aggregation indicator (diagonal lines pattern)
            if gop.isAggregated && w > 10 {
                var patternPath = Path()
                let spacing: CGFloat = 6
                var lineX = x + spacing
                while lineX < x + w {
                    patternPath.move(to: CGPoint(x: lineX, y: y + barHeight - 4))
                    patternPath.addLine(to: CGPoint(x: lineX + 4, y: y + barHeight))
                    lineX += spacing
                }
                context.stroke(patternPath, with: .color(Color.white.opacity(0.2)), lineWidth: 1)
            }
        }
    }

    private func drawFrameTypes(context: GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let domain = effectiveDomain
        let domainDuration = max(0.001, domain.end - domain.start)

        for gop in cachedDisplayGOPs {
            guard gop.hasFrameTypes else { continue }

            let startRatio = max(0, (gop.startTime - domain.start) / domainDuration)
            let endRatio = min(1, (gop.endTime - domain.start) / domainDuration)
            let x = CGFloat(startRatio) * width
            let totalWidth = max(HeatmapConfig.minGOPWidth, CGFloat(endRatio - startRatio) * width - HeatmapConfig.gopSpacing)

            // Draw stacked bar showing frame type ratios
            var currentX = x

            // I-frames (blue)
            if gop.iFrameRatio > 0 {
                let w = totalWidth * CGFloat(gop.iFrameRatio)
                let rect = CGRect(x: currentX, y: 0, width: max(1, w), height: height)
                context.fill(Path(rect), with: .color(FrameTypeColors.i))
                currentX += w
            }

            // P-frames (orange)
            if gop.pFrameRatio > 0 {
                let w = totalWidth * CGFloat(gop.pFrameRatio)
                let rect = CGRect(x: currentX, y: 0, width: max(1, w), height: height)
                context.fill(Path(rect), with: .color(FrameTypeColors.p))
                currentX += w
            }

            // B-frames (red)
            if gop.bFrameRatio > 0 {
                let w = totalWidth * CGFloat(gop.bFrameRatio)
                let rect = CGRect(x: currentX, y: 0, width: max(1, w), height: height)
                context.fill(Path(rect), with: .color(FrameTypeColors.b))
            }
        }
    }

    private func selectionIndicator(for gop: DisplayGOP, width: CGFloat) -> some View {
        let domain = effectiveDomain
        let domainDuration = max(0.001, domain.end - domain.start)
        let startRatio = max(0, (gop.startTime - domain.start) / domainDuration)
        let endRatio = min(1, (gop.endTime - domain.start) / domainDuration)
        let x = CGFloat(startRatio) * width
        let w = max(HeatmapConfig.minGOPWidth, CGFloat(endRatio - startRatio) * width)

        // Top accent bar indicator
        return VStack(spacing: 0) {
            // Accent bar at top
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: w, height: 4)

            // Connecting line to the GOP bar
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 2, height: HeatmapConfig.labelHeight - 4)
        }
        .offset(x: x + (w - w) / 2, y: 0)
        .allowsHitTesting(false)
    }

    // MARK: - Time Axis

    private var timeAxisView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let domain = effectiveDomain
            let domainDuration = max(0.001, domain.end - domain.start)

            Canvas { context, size in
                // Axis line
                var linePath = Path()
                linePath.move(to: CGPoint(x: 0, y: 0))
                linePath.addLine(to: CGPoint(x: size.width, y: 0))
                context.stroke(linePath, with: .color(DesignSystem.Colors.Chart.axisTick), lineWidth: 1)

                // Time labels
                let tickCount = 5
                for i in 0...tickCount {
                    let ratio = Double(i) / Double(tickCount)
                    let time = domain.start + ratio * domainDuration
                    let x = CGFloat(ratio) * width

                    // Tick mark
                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: x, y: 0))
                    tickPath.addLine(to: CGPoint(x: x, y: 4))
                    context.stroke(tickPath, with: .color(DesignSystem.Colors.Chart.axisTick), lineWidth: 1)

                    // Label
                    let text = formatTime(time)
                    let textX: CGFloat
                    if i == 0 {
                        textX = 0
                    } else if i == tickCount {
                        textX = x - 40
                    } else {
                        textX = x - 20
                    }

                    context.draw(
                        Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(DesignSystem.Colors.Chart.axisLabel),
                        at: CGPoint(x: textX + 20, y: 14)
                    )
                }
            }
        }
    }

    // MARK: - Tooltip

    private func tooltipView(for gop: DisplayGOP) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: GOP number
            HStack {
                if gop.isAggregated {
                    Text("GOPs \(gop.originalIndices.lowerBound + 1)-\(gop.originalIndices.upperBound + 1)")
                        .font(.caption.bold())
                } else {
                    Text("GOP #\(gop.originalIndices.lowerBound + 1)")
                        .font(.caption.bold())
                }
                
                Spacer()
                
                // Duration variance badge
                durationVarianceBadge(variance: gop.durationVariance)
            }
            
            Divider()
                .opacity(0.5)
            
            // Time range
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("\(formatTimeCompact(gop.startTime)) → \(formatTimeCompact(gop.endTime))")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }
            
            // Stats row
            HStack(spacing: 12) {
                // Frame count
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Frames"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("\(gop.frameCount)")
                        .font(.caption.monospacedDigit().bold())
                }
                
                // Duration
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Duration"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.3fs", gop.duration))
                        .font(.caption.monospacedDigit().bold())
                }
                
                // Avg frame duration
                if gop.frameCount > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Frame Avg"))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.1fms", (gop.duration / Double(gop.frameCount)) * 1000))
                            .font(.caption.monospacedDigit().bold())
                    }
                }
            }

            // Frame types (if available)
            if gop.hasFrameTypes {
                HStack(spacing: 8) {
                    frameTypeLabel("I", ratio: gop.iFrameRatio, color: FrameTypeColors.i)
                    frameTypeLabel("P", ratio: gop.pFrameRatio, color: FrameTypeColors.p)
                    frameTypeLabel("B", ratio: gop.bFrameRatio, color: FrameTypeColors.b)
                }
                .font(.caption2)
            }
            
            // Click hint
            Text(String(localized: "Click to inspect"))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 180)
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlassBackground(in: .rect(cornerRadius: DesignSystem.CornerRadius.large))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    @ViewBuilder
    private func durationVarianceBadge(variance: Double) -> some View {
        let (text, color) = durationVarianceInfo(variance)
        
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
    
    private func durationVarianceInfo(_ variance: Double) -> (String, Color) {
        if abs(variance) < 0.1 {
            return (String(localized: "Consistent"), Color(red: 0.3, green: 0.7, blue: 0.4))
        } else if variance > 0.3 {
            return (String(format: "+%d%%", Int(variance * 100)), Color(red: 0.3, green: 0.5, blue: 0.9))
        } else if variance < -0.3 {
            return (String(format: "%d%%", Int(variance * 100)), Color(red: 0.9, green: 0.5, blue: 0.3))
        } else if variance > 0 {
            return (String(format: "+%d%%", Int(variance * 100)), Color(red: 0.4, green: 0.6, blue: 0.8))
        } else {
            return (String(format: "%d%%", Int(variance * 100)), Color(red: 0.9, green: 0.7, blue: 0.3))
        }
    }
    
    private func formatTimeCompact(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let ms = Int((seconds - Double(totalSeconds)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, secs, ms)
    }

    private func frameTypeLabel(_ type: String, ratio: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(type): \(Int(ratio * 100))%")
        }
    }

    // MARK: - Interactions

    private func handleHover(at location: CGPoint, width: CGFloat) {
        hoverLocation = location
        let domain = effectiveDomain
        let domainDuration = max(0.001, domain.end - domain.start)
        let time = domain.start + Double(location.x / width) * domainDuration

        hoveredGOP = cachedDisplayGOPs.first { gop in
            time >= gop.startTime && time < gop.endTime
        }
    }

    private var zoomGesture: some Gesture {
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
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard let range = viewModel.visibleTimeRange else { return }

                let domain = effectiveDomain
                let domainDuration = max(0.001, domain.end - domain.start)
                let panRatio = Double(value.translation.width / containerSize.width)
                let timeDelta = panRatio * domainDuration

                let newStart = max(0, range.lowerBound - timeDelta)
                let newEnd = min(domainSeconds, range.upperBound - timeDelta)

                let rangeWidth = range.upperBound - range.lowerBound
                if abs((newEnd - newStart) - rangeWidth) < 0.001 && newStart >= 0 && newEnd <= domainSeconds {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.visibleTimeRange = newStart...newEnd
                    }
                }
            }
    }

    // MARK: - Helpers

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

// MARK: - Frame Type Colors

private enum FrameTypeColors {
    static let i = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let p = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let b = Color(red: 1.0, green: 0.23, blue: 0.19)
}

// MARK: - Data Preparation

private struct GOPStats {
    let avgDuration: Double
    let minDuration: Double
    let maxDuration: Double
    let avgFrameCount: Double
}

private func calculateStats(segments: [GOPSegment]) -> GOPStats {
    let durations = segments.map(\.duration).filter { $0.isFinite && $0 > 0 }
    let frameCounts = segments.compactMap(\.frameCount)

    let avgDuration = durations.isEmpty ? 1.0 : durations.reduce(0, +) / Double(durations.count)
    let minDuration = durations.min() ?? 0
    let maxDuration = durations.max() ?? 1
    let avgFrameCount = frameCounts.isEmpty ? 30.0 : Double(frameCounts.reduce(0, +)) / Double(frameCounts.count)

    return GOPStats(avgDuration: avgDuration, minDuration: minDuration, maxDuration: maxDuration, avgFrameCount: avgFrameCount)
}

private func prepareDisplayGOPs(
    segments: [GOPSegment],
    allSegments: [GOPSegment],
    maxCount: Int,
    domain: (start: Double, end: Double)
) -> [DisplayGOP] {
    guard !segments.isEmpty else { return [] }

    let stats = calculateStats(segments: allSegments)

    // If under max count, no aggregation needed
    if segments.count <= maxCount {
        return segments.enumerated().map { index, segment in
            let globalIndex = allSegments.firstIndex(where: { $0.id == segment.id }) ?? index
            return createDisplayGOP(from: segment, indices: globalIndex...globalIndex, stats: stats)
        }
    }

    // Aggregate GOPs for large counts
    let aggregationFactor = Int(ceil(Double(segments.count) / Double(maxCount)))
    var result: [DisplayGOP] = []
    result.reserveCapacity(maxCount)

    var i = 0
    while i < segments.count {
        let endIndex = min(i + aggregationFactor, segments.count)
        let batch = Array(segments[i..<endIndex])

        let startIdx = allSegments.firstIndex(where: { $0.id == batch.first?.id }) ?? i
        let endIdx = allSegments.firstIndex(where: { $0.id == batch.last?.id }) ?? (endIndex - 1)

        result.append(createAggregatedDisplayGOP(from: batch, indices: startIdx...endIdx, stats: stats))
        i = endIndex
    }

    return result
}

private func createDisplayGOP(from segment: GOPSegment, indices: ClosedRange<Int>, stats: GOPStats) -> DisplayGOP {
    let frames = segment.frames ?? []
    let totalFrames = max(1, frames.count)

    // Single-pass frame type counting
    var iCount = 0, pCount = 0, bCount = 0
    for frame in frames {
        switch frame.type {
        case .i: iCount += 1
        case .p: pCount += 1
        case .b: bCount += 1
        case .unknown: break
        }
    }

    let variance = stats.avgDuration > 0 ? (segment.duration - stats.avgDuration) / stats.avgDuration : 0

    return DisplayGOP(
        id: segment.id,
        startTime: segment.startTime,
        endTime: segment.endTime,
        duration: segment.duration,
        frameCount: segment.frameCount ?? 0,
        iFrameRatio: Double(iCount) / Double(totalFrames),
        pFrameRatio: Double(pCount) / Double(totalFrames),
        bFrameRatio: Double(bCount) / Double(totalFrames),
        originalIndices: indices,
        isAggregated: false,
        durationVariance: variance
    )
}

private func createAggregatedDisplayGOP(from segments: [GOPSegment], indices: ClosedRange<Int>, stats: GOPStats) -> DisplayGOP {
    let startTime = segments.first?.startTime ?? 0
    let endTime = segments.last?.endTime ?? 0
    let totalDuration = segments.map(\.duration).reduce(0, +)
    let totalFrameCount = segments.compactMap(\.frameCount).reduce(0, +)

    // Aggregate frame types (single-pass)
    var totalI = 0, totalP = 0, totalB = 0, total = 0
    for segment in segments {
        if let frames = segment.frames {
            for frame in frames {
                switch frame.type {
                case .i: totalI += 1
                case .p: totalP += 1
                case .b: totalB += 1
                case .unknown: break
                }
                total += 1
            }
        }
    }

    let avgDuration = totalDuration / Double(segments.count)
    let variance = stats.avgDuration > 0 ? (avgDuration - stats.avgDuration) / stats.avgDuration : 0

    return DisplayGOP(
        id: UUID(),
        startTime: startTime,
        endTime: endTime,
        duration: totalDuration,
        frameCount: totalFrameCount,
        iFrameRatio: total > 0 ? Double(totalI) / Double(total) : 0,
        pFrameRatio: total > 0 ? Double(totalP) / Double(total) : 0,
        bFrameRatio: total > 0 ? Double(totalB) / Double(total) : 0,
        originalIndices: indices,
        isAggregated: true,
        durationVariance: variance
    )
}
