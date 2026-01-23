import SwiftUI

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

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let domainDuration = max(0.001, domainEnd - domainStart)

            ZStack(alignment: .leading) {
                // Time grid lines
                timeGridLines(width: width, domain: (domainStart, domainEnd), domainDuration: domainDuration, height: height)

                // GOP blocks
                HStack(spacing: 0) {
                    ForEach(Array(filteredSegments.enumerated()), id: \.element.id) { idx, segment in
                        let segmentIndex = segments.firstIndex(where: { $0.id == segment.id }) ?? idx
                        let startRatio = max(0, (segment.startTime - domainStart) / domainDuration)
                        let endRatio = min(1, (segment.endTime - domainStart) / domainDuration)
                        let segmentWidth = max(2.0, (endRatio - startRatio) * width)

                        GOPBlockView(
                            segment: segment,
                            index: segmentIndex,
                            isSelected: selectedGOPIndex == segmentIndex,
                            patternColor: patternColor(segment),
                            maxFrameCount: maxFrameCount,
                            minHeight: 40,
                            maxHeight: height * 0.7,
                            onClick: {
                                onGOPClick(segmentIndex)
                            }
                        )
                        .frame(width: segmentWidth)
                    }
                }
                .frame(maxWidth: width)

                // Selection overlay
                if let start = selectionStartTime, let end = selectionEndTime {
                    selectionOverlay(start: start, end: end, width: width, domain: (domainStart, domainEnd), domainDuration: domainDuration)
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func timeGridLines(width: CGFloat, domain: (start: Double, end: Double), domainDuration: Double, height: CGFloat) -> some View {
        let gridCount = 5
        let gridIndices: [Int] = (0...gridCount).map { $0 }
        ForEach(gridIndices, id: \.self) { i in
            let ratio = Double(i) / Double(gridCount)
            let time = domain.start + ratio * domainDuration
            let x = CGFloat(ratio) * width

            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
            .stroke(DesignSystem.Colors.Chart.grid.opacity(0.2), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func selectionOverlay(start: Double, end: Double, width: CGFloat, domain: (start: Double, end: Double), domainDuration: Double) -> some View {
        let startRatio = max(0, (start - domain.start) / domainDuration)
        let endRatio = min(1, (end - domain.start) / domainDuration)
        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width

        Rectangle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: abs(endX - startX))
            .offset(x: min(startX, endX))
    }
}
