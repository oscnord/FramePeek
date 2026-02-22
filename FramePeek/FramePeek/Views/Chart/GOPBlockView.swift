import SwiftUI
import FramePeekCore

struct GOPBlockView: View {
    let segment: GOPSegment
    let index: Int
    let isSelected: Bool
    let patternColor: Color
    let maxFrameCount: Int
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onClick: () -> Void

    @State private var isHovered = false

    private var frameCount: Int {
        segment.frameCount ?? 0
    }

    private var height: CGFloat {
        guard maxFrameCount > 0 else { return minHeight }
        let ratio = CGFloat(frameCount) / CGFloat(maxFrameCount)
        return minHeight + (maxHeight - minHeight) * ratio
    }

    private var frameDensity: Double {
        guard maxFrameCount > 0 else { return 0.5 }
        return min(1.0, Double(frameCount) / Double(maxFrameCount))
    }
    
    // Frame type statistics (single-pass)
    private var frameTypeStats: (i: Int, p: Int, b: Int, unknown: Int)? {
        guard let frames = segment.frames, !frames.isEmpty else { return nil }
        var i = 0, p = 0, b = 0, unknown = 0
        for frame in frames {
            switch frame.type {
            case .i: i += 1
            case .p: p += 1
            case .b: b += 1
            case .unknown: unknown += 1
            }
        }
        return (i, p, b, unknown)
    }
    
    private var hasFrameTypes: Bool {
        if let stats = frameTypeStats {
            return stats.i > 0 || stats.p > 0 || stats.b > 0
        }
        return false
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // GOP block with frame type gradient if available
            if hasFrameTypes, let stats = frameTypeStats {
                frameTypeGradientBlock(stats: stats)
            } else {
                // Default gradient block
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.3 + frameDensity * 0.2),
                                Color.accentColor.opacity(0.2 + frameDensity * 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Border overlay
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : patternColor,
                    lineWidth: isSelected ? 2.5 : 1.5
                )
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 4 : 2, y: 1)

            // I-frame marker at start
            VStack {
                Circle()
                    .fill(FrameTypeColor.i)
                    .frame(width: 6, height: 6)
                    .offset(x: -3)
                Spacer()
            }
            .frame(height: height)

            // Frame count badge and frame type indicators
            VStack(spacing: 0) {
                if height > 35 {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(frameCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("FRAMES")
                                .font(.system(size: 7, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                        Spacer()
                    }
                    .padding(6)
                } else if height > 25 {
                    HStack {
                        Text("\(frameCount)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                        Spacer()
                    }
                    .padding(4)
                }
                
                Spacer()
                
                // Frame type distribution bar at bottom
                if hasFrameTypes, let stats = frameTypeStats, height > 30 {
                    frameTypeDistributionBar(stats: stats)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onTapGesture {
            onClick()
        }
        .help(tooltipText)
    }
    
    // MARK: - Frame Type Gradient Block
    
    @ViewBuilder
    private func frameTypeGradientBlock(stats: (i: Int, p: Int, b: Int, unknown: Int)) -> some View {
        let total = max(1, stats.i + stats.p + stats.b + stats.unknown)
        let iRatio = CGFloat(stats.i) / CGFloat(total)
        let pRatio = CGFloat(stats.p) / CGFloat(total)
        let bRatio = CGFloat(stats.b) / CGFloat(total)
        
        // Create a gradient that represents the frame type composition
        let iColor = FrameTypeColor.i.opacity(0.6)
        let pColor = FrameTypeColor.p.opacity(0.5)
        let bColor = FrameTypeColor.b.opacity(0.5)
        let baseColor = Color.accentColor.opacity(0.25)
        
        // Blend colors based on frame type ratios
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: iColor, location: 0),
                        .init(color: iRatio > 0.1 ? iColor : pColor, location: iRatio),
                        .init(color: pColor, location: iRatio + pRatio * 0.5),
                        .init(color: bRatio > 0.1 ? bColor : pColor, location: iRatio + pRatio),
                        .init(color: bColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    // MARK: - Frame Type Distribution Bar
    
    @ViewBuilder
    private func frameTypeDistributionBar(stats: (i: Int, p: Int, b: Int, unknown: Int)) -> some View {
        let total = max(1, stats.i + stats.p + stats.b + stats.unknown)
        
        GeometryReader { geo in
            HStack(spacing: 0) {
                // I-frames (blue)
                if stats.i > 0 {
                    Rectangle()
                        .fill(FrameTypeColor.i)
                        .frame(width: geo.size.width * CGFloat(stats.i) / CGFloat(total))
                }
                
                // P-frames (orange)
                if stats.p > 0 {
                    Rectangle()
                        .fill(FrameTypeColor.p)
                        .frame(width: geo.size.width * CGFloat(stats.p) / CGFloat(total))
                }
                
                // B-frames (red)
                if stats.b > 0 {
                    Rectangle()
                        .fill(FrameTypeColor.b)
                        .frame(width: geo.size.width * CGFloat(stats.b) / CGFloat(total))
                }
                
                // Unknown (gray)
                if stats.unknown > 0 {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(stats.unknown) / CGFloat(total))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
    }

    private var tooltipText: String {
        var parts: [String] = []
        parts.append("GOP #\(index + 1)")
        if frameCount > 0 {
            parts.append("\(frameCount) frames")
        }
        parts.append(String(format: "%.2fs", segment.duration))

        if let stats = frameTypeStats {
            var typeInfo: [String] = []
            if stats.i > 0 { typeInfo.append("\(stats.i)I") }
            if stats.p > 0 { typeInfo.append("\(stats.p)P") }
            if stats.b > 0 { typeInfo.append("\(stats.b)B") }
            if !typeInfo.isEmpty {
                parts.append("(" + typeInfo.joined(separator: "/") + ")")
            }
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Frame Type Colors

private enum FrameTypeColor {
    static let i = Color(red: 0.0, green: 0.48, blue: 1.0)   // Blue
    static let p = Color(red: 1.0, green: 0.58, blue: 0.0)   // Orange
    static let b = Color(red: 1.0, green: 0.23, blue: 0.19)  // Red
}
