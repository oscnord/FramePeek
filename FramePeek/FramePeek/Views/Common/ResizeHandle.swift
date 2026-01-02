import SwiftUI
import AppKit

struct ResizeHandle: View {
    let minWidth: Double
    let maxWidth: Double
    @Binding var width: Double

    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startWidth == nil { startWidth = width }
                        let base = startWidth ?? width
                        let proposed = base - Double(value.translation.width)
                        width = min(max(proposed, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        startWidth = nil
                    }
            )
            .help(String(localized: "Drag to resize"))
    }
}

