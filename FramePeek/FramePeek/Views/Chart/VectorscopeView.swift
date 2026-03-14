import SwiftUI
import FramePeekCore

/// Vectorscope view showing color distribution
/// Displays UV/CbCr color space with reference markers
struct VectorscopeView: View {
    let vectorscopeData: VectorscopeData?
    let showReferenceBoxes: Bool
    let size: CGFloat
    
    @State private var hoveredPoint: (u: Double, v: Double)?
    @State private var showInfoPopover: Bool = false
    
    init(
        vectorscopeData: VectorscopeData?,
        showSkinToneLine: Bool = true,  // Deprecated, kept for compatibility
        showReferenceBoxes: Bool = true,
        size: CGFloat = 200
    ) {
        self.vectorscopeData = vectorscopeData
        self.showReferenceBoxes = showReferenceBoxes
        self.size = size
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            headerView
                .frame(width: size)
            
            if let data = vectorscopeData {
                vectorscopeCanvas(data: data)
                    .frame(width: size, height: size)
            } else {
                emptyStateView
            }
        }
        .padding(DesignSystem.Padding.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .strokeBorder(.separator.opacity(0.3), lineWidth: DesignSystem.Borders.thin)
                )
        )
        .fixedSize()
    }
    
    private var headerView: some View {
        HStack {
            Text("Vectorscope")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Button {
                showInfoPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfoPopover, arrowEdge: .top) {
                vectorscopeInfoContent
            }
            
            Spacer()
            
            if let point = hoveredPoint {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("U: \(point.u.formatted(.number.precision(.fractionLength(2))))")
                    Text("V: \(point.v.formatted(.number.precision(.fractionLength(2))))")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(DesignSystem.Colors.Chart.primary)
                .monospacedDigit()
            }
        }
    }
    
    private var vectorscopeInfoContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Vectorscope")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Color Wheel")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Shows color distribution. Distance from center = saturation, angle = hue. Primary (R, G, B) and secondary (C, M, Y) colors are marked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Usage")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, DesignSystem.Padding.xs)
                Text("Check color balance and saturation. Oversaturated colors extend beyond the outer circle. Neutral images cluster at center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignSystem.Padding.lg)
        .frame(width: 280, alignment: .leading)
    }
    
    private var emptyStateView: some View {
        VStack {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.5))
            Text("No vectorscope data")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
        }
        .frame(width: size, height: size)
    }
    
    private func vectorscopeCanvas(data: VectorscopeData) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 10
            
            // Draw background circle
            drawBackground(context: context, center: center, radius: radius)
            
            // Draw graticule (reference circles and lines)
            drawGraticule(context: context, center: center, radius: radius)
            
            // Draw reference boxes (color targets)
            if showReferenceBoxes {
                drawReferenceBoxes(context: context, center: center, radius: radius)
            }
            
            // Draw the actual color data
            drawColorData(context: context, center: center, radius: radius, data: data)
        }
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let radius = size / 2 - 10
                    
                    // Convert position to UV coordinates
                    let u = (value.location.x - center.x) / radius * 0.5
                    let v = -(value.location.y - center.y) / radius * 0.5  // Flip Y
                    
                    hoveredPoint = (u: Double(u), v: Double(v))
                }
                .onEnded { _ in
                    hoveredPoint = nil
                }
        )
    }
    
    private func drawBackground(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Outer circle
        let circlePath = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.stroke(circlePath, with: .color(.white.opacity(0.3)), lineWidth: 1)
    }
    
    private func drawGraticule(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Draw center crosshairs
        var crossPath = Path()
        crossPath.move(to: CGPoint(x: center.x - radius, y: center.y))
        crossPath.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        crossPath.move(to: CGPoint(x: center.x, y: center.y - radius))
        crossPath.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        
        context.stroke(crossPath, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
        
        // Draw inner circles at 50% and 75%
        for scale in [0.5, 0.75] {
            let innerRadius = radius * CGFloat(scale)
            let innerPath = Path(ellipseIn: CGRect(
                x: center.x - innerRadius,
                y: center.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ))
            context.stroke(innerPath, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }
    }
    
    private func drawReferenceBoxes(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Standard color bar reference positions (75% color bars)
        // These are the UV coordinates for standard color bar colors
        let references: [(name: String, u: Double, v: Double, color: Color)] = [
            ("R", 0.301, 0.411, .red),      // Red
            ("G", -0.293, -0.257, .green),  // Green
            ("B", 0.212, -0.367, .blue),    // Blue
            ("Cy", -0.212, 0.367, .cyan),   // Cyan
            ("Mg", 0.293, 0.257, Color(red: 1, green: 0, blue: 1)), // Magenta
            ("Yl", -0.301, -0.411, .yellow) // Yellow
        ]
        
        for ref in references {
            let x = center.x + CGFloat(ref.u) * radius * 2
            let y = center.y - CGFloat(ref.v) * radius * 2  // Flip Y
            
            // Draw small target box
            let boxSize: CGFloat = 10
            let boxRect = CGRect(
                x: x - boxSize / 2,
                y: y - boxSize / 2,
                width: boxSize,
                height: boxSize
            )
            
            context.stroke(
                Path(boxRect),
                with: .color(ref.color.opacity(0.6)),
                lineWidth: 1
            )
            
            // Draw label
            let text = Text(ref.name)
                .font(.system(size: 8))
                .foregroundStyle(ref.color.opacity(0.7))
            
            context.draw(
                context.resolve(text),
                at: CGPoint(x: x, y: y - boxSize - 2),
                anchor: .bottom
            )
        }
    }
    
    
    private func drawColorData(context: GraphicsContext, center: CGPoint, radius: CGFloat, data: VectorscopeData) {
        // Draw using the pre-computed grid for efficiency
        guard let grid = data.grid else {
            drawPoints(context: context, center: center, radius: radius, points: data.points)
            return
        }
        
        let gridSize = data.gridSize
        let cellWidth = radius * 2 / CGFloat(gridSize)
        let cellHeight = radius * 2 / CGFloat(gridSize)
        
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let intensity = grid[y][x]
                guard intensity > 0.01 else { continue }
                
                // Convert grid position to screen coordinates
                let screenX = center.x - radius + CGFloat(x) * cellWidth
                let screenY = center.y - radius + CGFloat(y) * cellHeight
                
                // Color with green phosphor aesthetic
                let alpha = min(1.0, intensity * 2)
                let color = Color.green.opacity(alpha)
                
                let rect = CGRect(x: screenX, y: screenY, width: cellWidth + 0.5, height: cellHeight + 0.5)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
    
    private func drawPoints(context: GraphicsContext, center: CGPoint, radius: CGFloat, points: [VectorscopePoint]) {
        for point in points {
            let x = center.x + CGFloat(point.u) * radius * 2
            let y = center.y - CGFloat(point.v) * radius * 2  // Flip Y
            
            // Check if within circle bounds
            let dx = x - center.x
            let dy = y - center.y
            guard dx * dx + dy * dy <= radius * radius else { continue }
            
            let alpha = min(1.0, point.intensity)
            let color = Color.green.opacity(alpha)
            
            let pointRect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
            context.fill(Path(pointRect), with: .color(color))
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        VectorscopeView(
            vectorscopeData: nil,
            showReferenceBoxes: true,
            size: 250
        )
    }
    .padding()
    .frame(width: 300, height: 300)
}
