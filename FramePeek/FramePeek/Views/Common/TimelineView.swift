import SwiftUI
import AppKit

struct TimelineView: View {
    let duration: Double
    @Binding var visibleTimeRange: ClosedRange<Double>?

    @State var isDraggingRange = false
    @State var dragStartRange: ClosedRange<Double>?
    @State var dragStartLocation: CGFloat?
    @State var selectionDragStart: CGFloat?
    @State var isResizingLeft = false
    @State var isResizingRight = false
    @State var dragStartX: CGFloat?
    @State var isHoveringResetButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm3) {
            HStack(spacing: DesignSystem.Spacing.sm3) {
                Image(systemName: "timeline.selection")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Timeline")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                
                if visibleTimeRange == nil {
                    Text("(Drag to zoom)")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.7))
                }
                
                Spacer()
                
                if let range = visibleTimeRange {
                    let startTime = formatTimeForDisplay(range.lowerBound)
                    let endTime = formatTimeForDisplay(range.upperBound)
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(startTime)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Text("–")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                        Text(endTime)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            visibleTimeRange = nil
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text("Reset Timeline")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isHoveringResetButton ? DesignSystem.Colors.Chart.primary : DesignSystem.Colors.Semantic.secondary.opacity(0.8))
                    .padding(.horizontal, DesignSystem.Padding.sm2)
                    .padding(.vertical, DesignSystem.Padding.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                            .fill(isHoveringResetButton ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                            .strokeBorder(isHoveringResetButton ? DesignSystem.Colors.Chart.primary.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: DesignSystem.Borders.thin)
                    )
                    .help(String(localized: "Reset Timeline"))
                    .onHover { hovering in
                        isHoveringResetButton = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                } else {
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                }
            }
            .padding(.horizontal, DesignSystem.Padding.sm)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.08),
                                    Color.black.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                                .strokeBorder(.separator.opacity(0.2), lineWidth: DesignSystem.Borders.thin)
                        )

                    // Time markers - always show full timeline
                    Canvas { ctx, size in
                        guard duration > 0 else { return }
                        
                        var path = Path()
                        let tickTop: CGFloat = 4
                        let tickBottom: CGFloat = size.height - 4
                        
                        // Always use full duration for tick marks
                        let numMarkers = 10
                        let timeStep = duration / Double(numMarkers)
                        let totalWidth = size.width - 20
                        
                        // Draw tick marks for full timeline
                        for i in 0...numMarkers {
                            let time = Double(i) * timeStep
                            let x = CGFloat(time / duration) * totalWidth + 10
                            
                            path.move(to: CGPoint(x: x, y: tickTop))
                            path.addLine(to: CGPoint(x: x, y: tickBottom))
                        }
                        
                        ctx.stroke(path, with: .color(DesignSystem.Colors.Semantic.secondary.opacity(0.3)), lineWidth: DesignSystem.Borders.thin)
                    }
                    
                    // Time labels overlay - always show full timeline labels
                    TimelineLabelsView(
                        duration: duration,
                        visibleTimeRange: nil, // Always show full timeline labels
                        geometry: geo,
                        formatTime: formatTimeShort,
                        calculateLabelStep: calculateLabelStep
                    )
                    
                    if let range = visibleTimeRange {
                        let startX = CGFloat(range.lowerBound / duration) * (geo.size.width - 20) + 10
                        let endX = CGFloat(range.upperBound / duration) * (geo.size.width - 20) + 10
                        let width = max(endX - startX, 20)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            DesignSystem.Colors.Chart.primary.opacity(0.25),
                                            DesignSystem.Colors.Chart.primary.opacity(0.15)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                        .strokeBorder(DesignSystem.Colors.Chart.primary.opacity(0.8), lineWidth: DesignSystem.Borders.thick)
                                )
                            
                            if width > 80 {
                                HStack {
                                    Text(formatTimeShort(range.lowerBound))
                                        .font(.system(size: DesignSystem.Typography.caption, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, DesignSystem.Padding.sm2)
                                        .padding(.vertical, DesignSystem.Padding.xs)
                                        .background(
                                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                                .fill(DesignSystem.Colors.Chart.primary.opacity(0.95))
                                        )
                                    
                                    Spacer()
                                    
                                    Text(formatTimeShort(range.upperBound))
                                        .font(.system(size: DesignSystem.Typography.caption, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, DesignSystem.Padding.sm2)
                                        .padding(.vertical, DesignSystem.Padding.xs)
                                        .background(
                                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                                .fill(DesignSystem.Colors.Chart.primary.opacity(0.95))
                                        )
                                }
                                .padding(.horizontal, DesignSystem.Padding.sm)
                            }
                        }
                        .frame(width: width, height: geo.size.height)
                        .position(x: startX + width / 2, y: geo.size.height / 2)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                        
                        Rectangle()
                            .fill(DesignSystem.Colors.Chart.primary)
                            .frame(width: 8, height: geo.size.height + 4)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 2, height: geo.size.height - 4)
                            )
                            .position(x: startX, y: geo.size.height / 2)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false)
                            .onHover { hovering in
                                if hovering && !isResizingRight && !isDraggingRange {
                                    NSCursor.resizeLeftRight.push()
                                } else if !hovering && !isResizingLeft && !isResizingRight && !isDraggingRange {
                                    NSCursor.pop()
                                }
                            }
                        
                        Rectangle()
                            .fill(DesignSystem.Colors.Chart.primary)
                            .frame(width: 8, height: geo.size.height + 4)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 2, height: geo.size.height - 4)
                            )
                            .position(x: endX, y: geo.size.height / 2)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false)
                            .onHover { hovering in
                                if hovering && !isResizingLeft && !isDraggingRange {
                                    NSCursor.resizeLeftRight.push()
                                } else if !hovering && !isResizingLeft && !isResizingRight && !isDraggingRange {
                                    NSCursor.pop()
                                }
                            }
                    }
                    
                    // Transparent overlay to capture mouse events immediately - must be last in ZStack
                    TimelineMouseTracker(
                        duration: duration,
                        visibleTimeRange: $visibleTimeRange,
                        isDraggingRange: $isDraggingRange,
                        dragStartRange: $dragStartRange,
                        dragStartLocation: $dragStartLocation,
                        selectionDragStart: $selectionDragStart,
                        isResizingLeft: $isResizingLeft,
                        isResizingRight: $isResizingRight,
                        dragStartX: $dragStartX,
                        geometry: geo
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(true)
                }
            }
            .frame(height: 36)
        }
        .padding(.vertical, DesignSystem.Padding.md)
        .padding(.horizontal, DesignSystem.Padding.md3)
        .background(DesignSystem.Materials.thin, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: DesignSystem.Borders.thin)
        )
        .accessibilityLabel("Timeline zoom control")
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1f s", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", minutes, secs)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
    }
    
    /// Formats time for display in timeline header (always shows minutes:seconds format for consistency)
    private func formatTimeForDisplay(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "0:%02.0f", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", minutes, secs)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
    }
    
    private func formatTimeShort(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", minutes, secs)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
    }
    
    /// Calculates an appropriate time step for labels based on the visible duration
    /// Returns nice round numbers (1s, 5s, 10s, 30s, 1m, 5m, etc.)
    private func calculateLabelStep(for duration: Double) -> Double {
        guard duration > 0 else { return 1.0 }
        
        // Target: 5-10 labels
        let targetLabels = 7.0
        let rawStep = duration / targetLabels
        
        // Find the nearest "nice" step value
        if rawStep < 0.1 {
            return 0.1
        } else if rawStep < 0.5 {
            return 0.5
        } else if rawStep < 1.0 {
            return 1.0
        } else if rawStep < 5.0 {
            return 5.0
        } else if rawStep < 10.0 {
            return 10.0
        } else if rawStep < 30.0 {
            return 30.0
        } else if rawStep < 60.0 {
            return 60.0
        } else if rawStep < 300.0 {
            return 300.0  // 5 minutes
        } else if rawStep < 600.0 {
            return 600.0  // 10 minutes
        } else if rawStep < 1800.0 {
            return 1800.0  // 30 minutes
        } else if rawStep < 3600.0 {
            return 3600.0  // 1 hour
        } else {
            return 3600.0 * ceil(rawStep / 3600.0)  // Multiple hours
        }
    }
}

extension TimelineView {
    /// Unified drag handler that determines the action based on where the drag starts
    func handleUnifiedDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        guard duration > 0 else { return }
        
        let startX = value.startLocation.x
        let totalWidth = geometry.size.width - 20
        
        if isResizingLeft {
            guard let range = dragStartRange, let originalX = dragStartX else { return }
            handleLeftResize(value: value, geometry: geometry, currentRange: range, startX: originalX)
            return
        }
        
        if isResizingRight {
            guard let range = dragStartRange, let originalX = dragStartX else { return }
            handleRightResize(value: value, geometry: geometry, currentRange: range, endX: originalX)
            return
        }
        
        if isDraggingRange {
            handleDrag(value: value, geometry: geometry)
            return
        }
        
        if let range = visibleTimeRange {
            let windowStartX = CGFloat(range.lowerBound / duration) * totalWidth + 10
            let windowEndX = CGFloat(range.upperBound / duration) * totalWidth + 10
            let handleWidth: CGFloat = 8
            let handleTolerance: CGFloat = 6
            
            if startX >= windowStartX - handleTolerance && startX <= windowStartX + handleTolerance {
                isResizingLeft = true
                dragStartRange = range
                dragStartX = windowStartX
                handleLeftResize(value: value, geometry: geometry, currentRange: range, startX: windowStartX)
                return
            }
            
            if startX >= windowEndX - handleTolerance && startX <= windowEndX + handleTolerance {
                isResizingRight = true
                dragStartRange = range
                dragStartX = windowEndX
                handleRightResize(value: value, geometry: geometry, currentRange: range, endX: windowEndX)
                return
            }
            
            if startX >= windowStartX + handleTolerance && startX <= windowEndX - handleTolerance {
                isDraggingRange = true
                dragStartRange = range
                dragStartLocation = startX
                handleDrag(value: value, geometry: geometry)
                return
            }
        }
        
        if selectionDragStart == nil {
            selectionDragStart = startX
        }
        handleNewSelectionDrag(value: value, geometry: geometry)
    }
    
    func handleDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        guard duration > 0, let startRange = dragStartRange, let startLoc = dragStartLocation else { return }
        
        let totalWidth = geometry.size.width - 20
        let deltaX = value.location.x - startLoc
        let timeDelta = (Double(deltaX) / Double(totalWidth)) * duration
        
        let newStart = max(0, min(duration, startRange.lowerBound + timeDelta))
        let newEnd = max(0, min(duration, startRange.upperBound + timeDelta))
        
        let windowSize = startRange.upperBound - startRange.lowerBound
        
        if newStart == 0 {
            visibleTimeRange = 0...windowSize
        } else if newEnd == duration {
            visibleTimeRange = (duration - windowSize)...duration
        } else {
            visibleTimeRange = newStart...newEnd
        }
    }
    
    func handleNewSelectionDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        guard duration > 0, let startLoc = selectionDragStart else { return }
        
        let totalWidth = geometry.size.width - 20
        let x = value.location.x - 10
        let time = max(0, min(duration, (Double(x) / Double(totalWidth)) * duration))
        
        let startX = startLoc - 10
        let startTime = max(0, min(duration, (Double(startX) / Double(totalWidth)) * duration))
        
        let minTime = min(startTime, time)
        let maxTime = max(startTime, time)
        
        let timeRange = maxTime - minTime
        let minZoomSize: Double = self.duration * 0.01
        if timeRange > minZoomSize { // Minimum zoom size
            visibleTimeRange = minTime...maxTime
        }
    }
    
    func handleLeftResize(value: DragGesture.Value, geometry: GeometryProxy, currentRange: ClosedRange<Double>, startX: CGFloat) {
        guard duration > 0 else { return }
        
        let totalWidth = geometry.size.width - 20
        let newX = startX + value.translation.width
        let newStartTime = max(0.0, min(duration, (Double(newX - 10) / Double(totalWidth)) * duration))
        
        let minZoomSize = duration * 0.01
        let maxEnd = currentRange.upperBound
        let clampedStart = max(0.0, min(maxEnd - minZoomSize, newStartTime))
        
        visibleTimeRange = clampedStart...maxEnd
    }
    
    func handleRightResize(value: DragGesture.Value, geometry: GeometryProxy, currentRange: ClosedRange<Double>, endX: CGFloat) {
        guard duration > 0 else { return }
        
        let totalWidth = geometry.size.width - 20
        let newX = endX + value.translation.width
        let newEndTime = max(0.0, min(duration, (Double(newX - 10) / Double(totalWidth)) * duration))
        
        let minZoomSize = duration * 0.01
        let minStart = currentRange.lowerBound
        let clampedEnd = min(duration, max(minStart + minZoomSize, newEndTime))
        
        visibleTimeRange = minStart...clampedEnd
    }
}

// MARK: - Mouse Event Tracker

private struct TimelineMouseTracker: NSViewRepresentable {
    let duration: Double
    @Binding var visibleTimeRange: ClosedRange<Double>?
    @Binding var isDraggingRange: Bool
    @Binding var dragStartRange: ClosedRange<Double>?
    @Binding var dragStartLocation: CGFloat?
    @Binding var selectionDragStart: CGFloat?
    @Binding var isResizingLeft: Bool
    @Binding var isResizingRight: Bool
    @Binding var dragStartX: CGFloat?
    let geometry: GeometryProxy
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = TimelineTrackingView()
        context.coordinator.view = view
        view.duration = duration
        view.visibleTimeRange = Binding(
            get: { visibleTimeRange },
            set: { visibleTimeRange = $0 }
        )
        view.isDraggingRange = Binding(
            get: { isDraggingRange },
            set: { isDraggingRange = $0 }
        )
        view.dragStartRange = Binding(
            get: { dragStartRange },
            set: { dragStartRange = $0 }
        )
        view.dragStartLocation = Binding(
            get: { dragStartLocation },
            set: { dragStartLocation = $0 }
        )
        view.selectionDragStart = Binding(
            get: { selectionDragStart },
            set: { selectionDragStart = $0 }
        )
        view.isResizingLeft = Binding(
            get: { isResizingLeft },
            set: { isResizingLeft = $0 }
        )
        view.isResizingRight = Binding(
            get: { isResizingRight },
            set: { isResizingRight = $0 }
        )
        view.dragStartX = Binding(
            get: { dragStartX },
            set: { dragStartX = $0 }
        )
        view.geometry = geometry
        view.setup()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? TimelineTrackingView else { return }
        view.duration = duration
        view.geometry = geometry
    }
    
    class Coordinator {
        var view: TimelineTrackingView?
    }
}

private class TimelineTrackingView: NSView {
    var duration: Double = 0
    var visibleTimeRange: Binding<ClosedRange<Double>?>?
    var isDraggingRange: Binding<Bool>?
    var dragStartRange: Binding<ClosedRange<Double>?>?
    var dragStartLocation: Binding<CGFloat?>?
    var selectionDragStart: Binding<CGFloat?>?
    var isResizingLeft: Binding<Bool>?
    var isResizingRight: Binding<Bool>?
    var dragStartX: Binding<CGFloat?>?
    var geometry: GeometryProxy?
    
    private var mouseDownLocation: CGPoint?
    private var isDragging = false
    private var lastClickTime: Date?
    private var lastClickLocation: CGPoint?
    
    func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let location = convert(event.locationInWindow, from: nil)
        mouseDownLocation = location
        isDragging = false
        
        // Initialize drag state immediately
        if let geo = geometry, duration > 0 {
            initializeDragState(at: location, geometry: geo)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard let startLocation = mouseDownLocation else { return }
        isDragging = true
        
        let currentLocation = convert(event.locationInWindow, from: nil)
        let translation = CGSize(
            width: currentLocation.x - startLocation.x,
            height: currentLocation.y - startLocation.y
        )
        
        if let geo = geometry {
            handleDrag(location: currentLocation, startLocation: startLocation, translation: translation, geometry: geo)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let location = convert(event.locationInWindow, from: nil)
        
        // Check for double-tap
        if !isDragging, let lastTime = lastClickTime, let lastLoc = lastClickLocation {
            let timeSinceLastClick = Date().timeIntervalSince(lastTime)
            let distance = sqrt(pow(location.x - lastLoc.x, 2) + pow(location.y - lastLoc.y, 2))
            
            if timeSinceLastClick < 0.5 && distance < 5 {
                // Double-tap detected - reset zoom
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    visibleTimeRange?.wrappedValue = nil
                }
                lastClickTime = nil
                lastClickLocation = nil
                mouseDownLocation = nil
                return
            }
        }
        
        lastClickTime = Date()
        lastClickLocation = location
        mouseDownLocation = nil
        isDragging = false
        
        // Reset drag state
        isDraggingRange?.wrappedValue = false
        isResizingLeft?.wrappedValue = false
        isResizingRight?.wrappedValue = false
        dragStartRange?.wrappedValue = nil
        dragStartLocation?.wrappedValue = nil
        selectionDragStart?.wrappedValue = nil
        dragStartX?.wrappedValue = nil
        NSCursor.pop()
    }
    
    private func initializeDragState(at location: CGPoint, geometry: GeometryProxy) {
        guard duration > 0 else { return }
        
        let startX = location.x
        let totalWidth = geometry.size.width - 20
        
        if let range = visibleTimeRange?.wrappedValue {
            let windowStartX = CGFloat(range.lowerBound / duration) * totalWidth + 10
            let windowEndX = CGFloat(range.upperBound / duration) * totalWidth + 10
            let handleTolerance: CGFloat = 6
            
            if startX >= windowStartX - handleTolerance && startX <= windowStartX + handleTolerance {
                isResizingLeft?.wrappedValue = true
                dragStartRange?.wrappedValue = range
                dragStartX?.wrappedValue = windowStartX
                return
            }
            
            if startX >= windowEndX - handleTolerance && startX <= windowEndX + handleTolerance {
                isResizingRight?.wrappedValue = true
                dragStartRange?.wrappedValue = range
                dragStartX?.wrappedValue = windowEndX
                return
            }
            
            if startX >= windowStartX + handleTolerance && startX <= windowEndX - handleTolerance {
                isDraggingRange?.wrappedValue = true
                dragStartRange?.wrappedValue = range
                dragStartLocation?.wrappedValue = startX
                return
            }
        }
        
        // New selection
        selectionDragStart?.wrappedValue = startX
    }
    
    private func handleDrag(location: CGPoint, startLocation: CGPoint, translation: CGSize, geometry: GeometryProxy) {
        guard duration > 0 else { return }
        
        if isResizingLeft?.wrappedValue == true {
            guard let range = dragStartRange?.wrappedValue, let originalX = dragStartX?.wrappedValue else { return }
            handleLeftResize(translation: translation, geometry: geometry, currentRange: range, startX: originalX)
            return
        }
        
        if isResizingRight?.wrappedValue == true {
            guard let range = dragStartRange?.wrappedValue, let originalX = dragStartX?.wrappedValue else { return }
            handleRightResize(translation: translation, geometry: geometry, currentRange: range, endX: originalX)
            return
        }
        
        if isDraggingRange?.wrappedValue == true {
            handleRangeDrag(location: location, geometry: geometry)
            return
        }
        
        // New selection drag
        handleNewSelectionDrag(location: location, geometry: geometry)
    }
    
    private func handleRangeDrag(location: CGPoint, geometry: GeometryProxy) {
        guard duration > 0,
              let startRange = dragStartRange?.wrappedValue,
              let startLoc = dragStartLocation?.wrappedValue else { return }
        
        let totalWidth = geometry.size.width - 20
        let deltaX = location.x - startLoc
        let timeDelta = (Double(deltaX) / Double(totalWidth)) * duration
        
        let newStart = max(0, min(duration, startRange.lowerBound + timeDelta))
        let newEnd = max(0, min(duration, startRange.upperBound + timeDelta))
        
        let windowSize = startRange.upperBound - startRange.lowerBound
        
        if newStart == 0 {
            visibleTimeRange?.wrappedValue = 0...windowSize
        } else if newEnd == duration {
            visibleTimeRange?.wrappedValue = (duration - windowSize)...duration
        } else {
            visibleTimeRange?.wrappedValue = newStart...newEnd
        }
    }
    
    private func handleNewSelectionDrag(location: CGPoint, geometry: GeometryProxy) {
        guard duration > 0, let startLoc = selectionDragStart?.wrappedValue else { return }
        
        let totalWidth = geometry.size.width - 20
        let x = location.x - 10
        let time = max(0, min(duration, (Double(x) / Double(totalWidth)) * duration))
        
        let startX = startLoc - 10
        let startTime = max(0, min(duration, (Double(startX) / Double(totalWidth)) * duration))
        
        let minTime = min(startTime, time)
        let maxTime = max(startTime, time)
        
        let timeRange = maxTime - minTime
        let minZoomSize: Double = duration * 0.01
        if timeRange > minZoomSize {
            visibleTimeRange?.wrappedValue = minTime...maxTime
        }
    }
    
    private func handleLeftResize(translation: CGSize, geometry: GeometryProxy, currentRange: ClosedRange<Double>, startX: CGFloat) {
        guard duration > 0 else { return }
        
        let totalWidth = geometry.size.width - 20
        let newX = startX + translation.width
        let newStartTime = max(0.0, min(duration, (Double(newX - 10) / Double(totalWidth)) * duration))
        
        let minZoomSize = duration * 0.01
        let maxEnd = currentRange.upperBound
        let clampedStart = max(0.0, min(maxEnd - minZoomSize, newStartTime))
        
        visibleTimeRange?.wrappedValue = clampedStart...maxEnd
    }
    
    private func handleRightResize(translation: CGSize, geometry: GeometryProxy, currentRange: ClosedRange<Double>, endX: CGFloat) {
        guard duration > 0 else { return }
        
        let totalWidth = geometry.size.width - 20
        let newX = endX + translation.width
        let newEndTime = max(0.0, min(duration, (Double(newX - 10) / Double(totalWidth)) * duration))
        
        let minZoomSize = duration * 0.01
        let minStart = currentRange.lowerBound
        let clampedEnd = min(duration, max(minStart + minZoomSize, newEndTime))
        
        visibleTimeRange?.wrappedValue = minStart...clampedEnd
    }
}

// MARK: - Timeline Labels View

private struct TimelineLabelsView: View {
    let duration: Double
    let visibleTimeRange: ClosedRange<Double>?
    let geometry: GeometryProxy
    let formatTime: (Double) -> String
    let calculateLabelStep: (Double) -> Double
    
    private var visibleLabels: [(time: Double, x: CGFloat)] {
        guard duration > 0 else { return [] }
        
        let totalWidth = geometry.size.width - 20
        let minLabelSpacing: CGFloat = 45 // Minimum spacing between labels to avoid overlap
        
        // Always use a fixed step based on total duration - labels never change
        let labelStep = calculateLabelStep(duration)
        
        var labels: [(time: Double, x: CGFloat)] = []
        
        if let range = visibleTimeRange {
            // When zoomed, show only fixed-interval labels that fall within the visible range
            // The time values are completely static - they never change when dragging
            let visibleDuration = range.upperBound - range.lowerBound
            let startTime = range.lowerBound
            let endTime = range.upperBound
            
            // Find the first fixed label time that's >= start of visible range
            let firstLabelTime = ceil(startTime / labelStep) * labelStep
            
            var lastLabelX: CGFloat = -minLabelSpacing
            
            // Generate all labels at fixed intervals that fall within visible range
            var currentTime = firstLabelTime
            while currentTime <= endTime {
                // Calculate position within visible range
                let ratio = (currentTime - startTime) / visibleDuration
                let x = CGFloat(ratio) * totalWidth + 10
                
                // Only add if there's enough space from previous label
                if abs(x - lastLabelX) >= minLabelSpacing {
                    labels.append((time: currentTime, x: x))
                    lastLabelX = x
                }
                
                currentTime += labelStep
            }
        } else {
            // Not zoomed - show labels across full duration
            let startLabel = floor(0 / labelStep) * labelStep
            var lastLabelX: CGFloat = -minLabelSpacing
            
            for time in stride(from: startLabel, through: duration, by: labelStep) {
                let x = CGFloat(time / duration) * totalWidth + 10
                
                if abs(x - lastLabelX) >= minLabelSpacing {
                    labels.append((time: time, x: x))
                    lastLabelX = x
                }
            }
        }
        
        return labels
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(visibleLabels.enumerated()), id: \.offset) { _, label in
                Text(formatTime(label.time))
                    .font(.system(size: DesignSystem.Typography.caption, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.7))
                    .fixedSize()
                    .position(x: label.x, y: geometry.size.height + 12)
            }
        }
    }
}
