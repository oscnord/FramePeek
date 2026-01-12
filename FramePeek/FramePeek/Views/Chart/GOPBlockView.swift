import SwiftUI

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
    
    var body: some View {
        ZStack(alignment: .leading) {
            // GOP block
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
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : patternColor,
                            lineWidth: isSelected ? 2.5 : 1.5
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 4 : 2, y: 1)
            
            // I-frame marker at start
            VStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .offset(x: -3)
                Spacer()
            }
            .frame(height: height)
            
            // Frame count badge (always show if there's space)
            if height > 35 {
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(frameCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("frames")
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
                    Spacer()
                }
            } else if height > 25 {
                // Compact version for smaller blocks
                VStack {
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
                    Spacer()
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
    
    private var tooltipText: String {
        var parts: [String] = []
        parts.append("GOP #\(index + 1)")
        if frameCount > 0 {
            parts.append("\(frameCount) frames")
        }
        parts.append(String(format: "%.2fs", segment.duration))
        
        if let frames = segment.frames, !frames.isEmpty {
            let frameTypes = frames.map { $0.type.rawValue }.joined(separator: "-")
            parts.append("(\(frameTypes))")
        }
        
        return parts.joined(separator: ", ")
    }
}

