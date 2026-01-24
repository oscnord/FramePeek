import SwiftUI

/// Traditional broadcast-style waveform scope view
/// Shows luminance distribution across horizontal position
struct WaveformScopeView: View {
    let waveformData: WaveformData?
    let scale: WaveformScale
    let isHDR: Bool
    let height: CGFloat
    
    @State private var hoveredColumn: Int?
    @State private var hoveredLevel: Double?
    @State private var showInfoPopover: Bool = false
    
    init(
        waveformData: WaveformData?,
        scale: WaveformScale = .percentage,
        isHDR: Bool = false,
        height: CGFloat = 200
    ) {
        self.waveformData = waveformData
        self.scale = scale
        self.isHDR = isHDR
        self.height = height
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            headerView
            
            if let data = waveformData {
                waveformCanvas(data: data)
                    .frame(height: height)
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
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "waveform.path")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text("Waveform")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Button {
                showInfoPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfoPopover, arrowEdge: .top) {
                waveformInfoContent
            }
            
            Spacer()
            
            if let hoveredLevel = hoveredLevel {
                Text(formatLevel(hoveredLevel))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignSystem.Colors.Chart.primary)
                    .monospacedDigit()
            }
            
            scaleLabel
        }
    }
    
    private var waveformInfoContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Waveform Scope")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("X-Axis")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Horizontal position in the frame, from left to right edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Y-Axis")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, DesignSystem.Padding.xs)
                Text("Brightness levels. 0% is black, 100% is peak white. Values above 100 IRE indicate super-whites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Usage")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, DesignSystem.Padding.xs)
                Text("Check exposure and broadcast-safe limits. Clipping appears as flat lines at top or bottom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignSystem.Padding.lg)
        .frame(width: 280, alignment: .leading)
    }
    
    private var scaleLabel: some View {
        Text(scale.displayName)
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            .padding(.horizontal, DesignSystem.Padding.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
            )
    }
    
    private var emptyStateView: some View {
        VStack {
            Image(systemName: "waveform.path")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.5))
            Text("No waveform data")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
    
    private func waveformCanvas(data: WaveformData) -> some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawWaveform(context: context, size: size, data: data)
            }
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
            .overlay(
                graticuleOverlay(size: geometry.size)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateHover(at: value.location, in: geometry.size, data: data)
                    }
                    .onEnded { _ in
                        hoveredColumn = nil
                        hoveredLevel = nil
                    }
            )
        }
    }
    
    private func drawWaveform(context: GraphicsContext, size: CGSize, data: WaveformData) {
        let columnCount = data.columns.count
        let levelCount = data.columns.first?.count ?? 256
        
        guard columnCount > 0 && levelCount > 0 else { return }
        
        let columnWidth = size.width / CGFloat(columnCount)
        
        // Draw each column
        for (colIndex, column) in data.columns.enumerated() {
            let x = CGFloat(colIndex) * columnWidth
            
            for (levelIndex, intensity) in column.enumerated() {
                guard intensity > 0.001 else { continue }
                
                // Y position (0 at bottom, max at top)
                let normalizedY = 1.0 - (CGFloat(levelIndex) / CGFloat(levelCount - 1))
                let y = normalizedY * size.height
                
                // Color based on intensity (green phosphor look)
                let alpha = min(1.0, intensity * 3)  // Amplify for visibility
                let color = Color.green.opacity(alpha)
                
                // Draw a small rect for each active point
                let rect = CGRect(
                    x: x,
                    y: y - 1,
                    width: columnWidth + 1,  // Slight overlap to avoid gaps
                    height: 2
                )
                
                context.fill(Path(rect), with: .color(color))
            }
        }
        
        // Draw hover indicator
        if let col = hoveredColumn {
            let x = CGFloat(col) * columnWidth
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
        }
    }
    
    private func graticuleOverlay(size: CGSize) -> some View {
        Canvas { context, size in
            // Draw horizontal reference lines
            let referenceLines: [(level: Double, label: String)] = referenceLineValues()
            
            for ref in referenceLines {
                let y = (1.0 - ref.level) * size.height
                
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                
                context.stroke(path, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                
                // Draw label
                let text = Text(ref.label)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.5))
                
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: 4, y: y - 6),
                    anchor: .leading
                )
            }
        }
        .allowsHitTesting(false)
    }
    
    private func referenceLineValues() -> [(level: Double, label: String)] {
        switch scale {
        case .percentage:
            return [
                (1.0, "100%"),
                (0.75, "75%"),
                (0.5, "50%"),
                (0.25, "25%"),
                (0.0, "0%")
            ]
        case .ire:
            return [
                (1.0, "100 IRE"),
                (0.75, "75 IRE"),
                (0.5, "50 IRE"),
                (0.25, "25 IRE"),
                (0.0, "0 IRE")
            ]
        case .nits:
            if isHDR {
                return [
                    (1.0, "10000"),
                    (0.5, "5000"),
                    (0.1, "1000"),
                    (0.02, "200"),
                    (0.0, "0")
                ]
            } else {
                return [
                    (1.0, "100"),
                    (0.75, "75"),
                    (0.5, "50"),
                    (0.25, "25"),
                    (0.0, "0")
                ]
            }
        case .logNits:
            return [
                (1.0, "4.0"),
                (0.75, "3.0"),
                (0.5, "2.0"),
                (0.25, "1.0"),
                (0.0, "0.0")
            ]
        }
    }
    
    private func updateHover(at location: CGPoint, in size: CGSize, data: WaveformData) {
        let columnCount = data.columns.count
        guard columnCount > 0 else { return }
        
        let column = Int(location.x / size.width * CGFloat(columnCount))
        hoveredColumn = max(0, min(column, columnCount - 1))
        
        // Calculate level from Y position
        let normalizedY = 1.0 - (location.y / size.height)
        hoveredLevel = max(0, min(1, normalizedY))
    }
    
    private func formatLevel(_ level: Double) -> String {
        switch scale {
        case .percentage:
            return String(format: "%.0f%%", level * 100)
        case .ire:
            return String(format: "%.0f IRE", level * 100)
        case .nits:
            let nits = isHDR ? level * 10000 : level * 100
            return String(format: "%.0f nits", nits)
        case .logNits:
            return String(format: "%.2f", level * 4)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        WaveformScopeView(
            waveformData: nil,
            scale: .percentage,
            isHDR: false,
            height: 200
        )
    }
    .padding()
    .frame(width: 400, height: 300)
}
