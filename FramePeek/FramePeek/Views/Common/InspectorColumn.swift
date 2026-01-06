import SwiftUI

// Custom shape with rounded corners only on the trailing (right) side
struct TrailingRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        
        // Start from top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Line to top-right (before corner)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        // Top-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        // Line to bottom-right (before corner)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Line to bottom-left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Line back to top-left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        
        return path
    }
}

// Custom shape with rounded corners only on the leading (left) side
struct LeadingRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        
        // Start from top-left (before corner)
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        // Top-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        // Line to bottom-left (before corner)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Line to bottom-right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Line to top-right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Line back to top-left (before corner)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.closeSubpath()
        
        return path
    }
}

struct InspectorColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
    }
}

