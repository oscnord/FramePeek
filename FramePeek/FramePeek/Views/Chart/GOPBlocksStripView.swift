import SwiftUI
import FramePeekCore

struct GOPBlocksStripView: View {
    let segments: [GOPSegment]
    let filteredSegments: [GOPSegment]
    let domainStart: Double
    let domainEnd: Double
    let maxFrameCount: Int
    let selectedGOPIndex: Int?
    let patternColor: (GOPSegment) -> Color
    let onGOPClick: (Int) -> Void
    let selectionStartTime: Double?
    let selectionEndTime: Double?

    @State private var hoveredSegmentIndex: Int?

    // Frame type colors
    private static let iColor = DesignSystem.Colors.FrameType.i
    private static let pColor = DesignSystem.Colors.FrameType.p
    private static let bColor = DesignSystem.Colors.FrameType.b

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let domainDuration = max(0.001, domainEnd - domainStart)
            // O(n) dictionary build for O(1) index lookups
            let indexMap = Dictionary(segments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, last in last })

            ZStack(alignment: .leading) {
                // Time grid lines (drawn via Canvas for consistency)
                Canvas { context, size in
                    drawTimeGrid(context: context, width: size.width, height: size.height, domainDuration: domainDuration)
                }

                // GOP blocks (single Canvas instead of 500+ SwiftUI views)
                Canvas { context, size in
                    drawGOPBlocks(
                        context: context, size: size,
                        indexMap: indexMap,
                        domainDuration: domainDuration,
                        maxHeight: size.height * 0.7
                    )
                }
                .drawingGroup()

                // Interaction layer
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let time = domainStart + (Double(location.x / width) * domainDuration)
                            hoveredSegmentIndex = nearestSegmentGlobalIndex(at: time, indexMap: indexMap)
                        case .ended:
                            hoveredSegmentIndex = nil
                        }
                    }
                    .onTapGesture { location in
                        let time = domainStart + (Double(location.x / width) * domainDuration)
                        if let idx = nearestSegmentGlobalIndex(at: time, indexMap: indexMap) {
                            onGOPClick(idx)
                        }
                    }
                    .accessibilityAddTraits(.isButton)

                // Selection overlay
                if let start = selectionStartTime, let end = selectionEndTime {
                    selectionOverlay(start: start, end: end, width: width, domainDuration: domainDuration)
                }
            }
            .clipped()
        }
    }

    // MARK: - Canvas Drawing

    private func drawTimeGrid(context: GraphicsContext, width: CGFloat, height: CGFloat, domainDuration: Double) {
        let gridCount = 5
        for i in 0...gridCount {
            let ratio = CGFloat(i) / CGFloat(gridCount)
            let x = ratio * width
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
            context.stroke(path, with: .color(DesignSystem.Colors.Chart.grid.opacity(0.2)), lineWidth: 0.5)
        }
    }

    private func drawGOPBlocks(
        context: GraphicsContext, size: CGSize,
        indexMap: [UUID: Int],
        domainDuration: Double,
        maxHeight: CGFloat
    ) {
        let width = size.width
        let height = size.height
        let minHeight: CGFloat = 40
        let safeMaxFrameCount = max(1, maxFrameCount)

        for segment in filteredSegments {
            let globalIndex = indexMap[segment.id]
            let startRatio = max(0, (segment.startTime - domainStart) / domainDuration)
            let endRatio = min(1, (segment.endTime - domainStart) / domainDuration)
            let x = CGFloat(startRatio) * width
            let w = max(2.0, CGFloat(endRatio - startRatio) * width)

            let frameCount = segment.frameCount ?? 0
            let heightRatio = CGFloat(frameCount) / CGFloat(safeMaxFrameCount)
            let barHeight = minHeight + (maxHeight - minHeight) * heightRatio
            let y = height - barHeight

            let isSelected = globalIndex.map { selectedGOPIndex == $0 } ?? false
            let isHovered = globalIndex.map { hoveredSegmentIndex == $0 } ?? false

            let rect = CGRect(x: x, y: y, width: w, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: 4)

            // Fill — frame-type gradient if available, else accent color
            if let frames = segment.frames, !frames.isEmpty {
                drawFrameTypeGradient(context: context, frames: frames, rect: rect, path: path, isHovered: isHovered)
            } else {
                let density = min(1.0, Double(frameCount) / Double(safeMaxFrameCount))
                let topOpacity = isHovered ? 0.6 : (0.3 + density * 0.2)
                let bottomOpacity = isHovered ? 0.5 : (0.2 + density * 0.15)
                let gradient = Gradient(colors: [
                    Color.accentColor.opacity(topOpacity),
                    Color.accentColor.opacity(bottomOpacity)
                ])
                context.fill(path, with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: x, y: y),
                    endPoint: CGPoint(x: x, y: y + barHeight)
                ))
            }

            // Border
            let borderColor = isSelected ? Color.accentColor : patternColor(segment)
            let borderWidth: CGFloat = isSelected ? 2.5 : 1.5
            context.stroke(path, with: .color(borderColor.opacity(isHovered ? 1.0 : 0.8)), lineWidth: borderWidth)

            // I-frame marker at start
            let markerSize: CGFloat = 6
            let markerRect = CGRect(x: x - markerSize / 2, y: y, width: markerSize, height: markerSize)
            context.fill(Path(ellipseIn: markerRect), with: .color(Self.iColor))

            // Frame count label (only if enough space)
            if w > 25 && barHeight > 25 {
                let text = Text("\(frameCount)")
                    .font(.system(size: barHeight > 35 ? 10 : 9, weight: barHeight > 35 ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                context.draw(text, at: CGPoint(x: x + 12, y: y + (barHeight > 35 ? 14 : 10)))
            }

            // Frame type distribution bar at bottom (if enough space)
            if let frames = segment.frames, !frames.isEmpty, barHeight > 30 {
                drawFrameTypeBar(context: context, frames: frames, x: x + 4, y: y + barHeight - 8, width: w - 8, height: 4)
            }
        }
    }

    private func drawFrameTypeGradient(
        context: GraphicsContext, frames: [FrameInfo],
        rect: CGRect, path: Path, isHovered: Bool
    ) {
        var iCount = 0, pCount = 0, bCount = 0, unknownCount = 0
        for frame in frames {
            switch frame.type {
            case .i: iCount += 1
            case .p: pCount += 1
            case .b: bCount += 1
            case .unknown: unknownCount += 1
            }
        }
        let total = max(1, iCount + pCount + bCount + unknownCount)
        let iRatio = CGFloat(iCount) / CGFloat(total)
        let pRatio = CGFloat(pCount) / CGFloat(total)

        let opacity: CGFloat = isHovered ? 0.75 : 0.55
        let iColor = Self.iColor.opacity(opacity)
        let pColor = Self.pColor.opacity(opacity)
        let bColor = Self.bColor.opacity(opacity)

        let gradient = Gradient(stops: [
            .init(color: iColor, location: 0),
            .init(color: iRatio > 0.1 ? iColor : pColor, location: iRatio),
            .init(color: pColor, location: iRatio + pRatio * 0.5),
            .init(color: bColor, location: 1.0)
        ])
        context.fill(path, with: .linearGradient(
            gradient,
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.minX, y: rect.maxY)
        ))
    }

    private func drawFrameTypeBar(
        context: GraphicsContext, frames: [FrameInfo],
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    ) {
        var iCount = 0, pCount = 0, bCount = 0, unknownCount = 0
        for frame in frames {
            switch frame.type {
            case .i: iCount += 1
            case .p: pCount += 1
            case .b: bCount += 1
            case .unknown: unknownCount += 1
            }
        }
        let total = max(1, iCount + pCount + bCount + unknownCount)
        var currentX = x

        if iCount > 0 {
            let w = width * CGFloat(iCount) / CGFloat(total)
            context.fill(Path(CGRect(x: currentX, y: y, width: max(1, w), height: height)), with: .color(Self.iColor))
            currentX += w
        }
        if pCount > 0 {
            let w = width * CGFloat(pCount) / CGFloat(total)
            context.fill(Path(CGRect(x: currentX, y: y, width: max(1, w), height: height)), with: .color(Self.pColor))
            currentX += w
        }
        if bCount > 0 {
            let w = width * CGFloat(bCount) / CGFloat(total)
            context.fill(Path(CGRect(x: currentX, y: y, width: max(1, w), height: height)), with: .color(Self.bColor))
            currentX += w
        }
        if unknownCount > 0 {
            let w = width * CGFloat(unknownCount) / CGFloat(total)
            context.fill(Path(CGRect(x: currentX, y: y, width: max(1, w), height: height)), with: .color(Color.gray.opacity(0.5)))
        }
    }

    // MARK: - Interaction

    private func nearestSegmentGlobalIndex(at time: Double, indexMap: [UUID: Int]) -> Int? {
        // Binary search on filteredSegments (sorted by startTime)
        guard !filteredSegments.isEmpty else { return nil }

        var lo = 0
        var hi = filteredSegments.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if filteredSegments[mid].endTime < time {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // Check if time falls within the segment at lo
        let segment = filteredSegments[lo]
        if time >= segment.startTime && time <= segment.endTime {
            return indexMap[segment.id]
        }

        // Check neighbors for closest match
        let candidates = [max(0, lo - 1), lo, min(filteredSegments.count - 1, lo + 1)]
        var bestIdx: Int?
        var bestDist = Double.infinity
        for c in candidates {
            let seg = filteredSegments[c]
            let dist = min(abs(seg.startTime - time), abs(seg.endTime - time))
            if dist < bestDist {
                bestDist = dist
                bestIdx = indexMap[seg.id]
            }
        }
        return bestIdx
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private func selectionOverlay(start: Double, end: Double, width: CGFloat, domainDuration: Double) -> some View {
        let startRatio = max(0, (start - domainStart) / domainDuration)
        let endRatio = min(1, (end - domainStart) / domainDuration)
        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width

        Rectangle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: abs(endX - startX))
            .offset(x: min(startX, endX))
    }
}
