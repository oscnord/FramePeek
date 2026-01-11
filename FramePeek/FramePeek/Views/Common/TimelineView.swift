import SwiftUI
import AppKit

struct TimelineView: View {
    let duration: Double
    @Binding var visibleTimeRange: ClosedRange<Double>?
    var frameRate: Double? = nil
    var currentPlaybackTime: Double? = nil

    @State var isDraggingRange = false
    @State var dragStartRange: ClosedRange<Double>?
    @State var dragStartLocation: CGFloat?
    @State var selectionDragStart: CGFloat?
    @State var isResizingLeft = false
    @State var isResizingRight = false
    @State var dragStartX: CGFloat?
    @State var isHoveringResetButton = false
    
    /// Normalized visible time range - converts full duration ranges to nil
    private var normalizedVisibleTimeRange: ClosedRange<Double>? {
        guard let range = visibleTimeRange else { return nil }
        return isActuallyZoomed(range) ? range : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header with controls
            HStack(spacing: DesignSystem.Spacing.sm) {
                if let range = normalizedVisibleTimeRange {
                    let startTime = formatTimeForDisplay(range.lowerBound)
                    let endTime = formatTimeForDisplay(range.upperBound)
                    HStack(spacing: 3) {
                        Text(startTime)
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                        Text("–")
                            .font(.system(size: 8))
                            .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                        Text(endTime)
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            visibleTimeRange = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Reset")
                                .font(.system(size: 8, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isHoveringResetButton ? .white : DesignSystem.Colors.Chart.primary)
                    .padding(.horizontal, DesignSystem.Padding.sm)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                            .fill(isHoveringResetButton ? DesignSystem.Colors.Chart.primary : DesignSystem.Colors.Chart.primary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                            .strokeBorder(isHoveringResetButton ? DesignSystem.Colors.Chart.primary.opacity(0.3) : DesignSystem.Colors.Chart.primary.opacity(0.25), lineWidth: DesignSystem.Borders.thin)
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
                }
            }
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.top, DesignSystem.Padding.sm)
            .frame(minHeight: 20)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Minimal line background
                    Rectangle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 2)

                    TimelineLabelsView(
                        duration: duration,
                        visibleTimeRange: normalizedVisibleTimeRange,
                        geometry: geo,
                        formatTime: formatTimeShort,
                        calculateLabelStep: calculateLabelStep
                    )
                    
                    TimelineTicksView(
                        duration: duration,
                        visibleTimeRange: visibleTimeRange,
                        geometry: geo,
                        calculateLabelStep: calculateLabelStep
                    )
                    
                    // Playback position indicator
                    if let playbackTime = currentPlaybackTime {
                        let x: CGFloat = {
                            if let range = normalizedVisibleTimeRange {
                                let visibleDuration = range.upperBound - range.lowerBound
                                let ratio = (playbackTime - range.lowerBound) / visibleDuration
                                return CGFloat(ratio) * (geo.size.width - 20) + 10
                            } else {
                                return CGFloat(playbackTime / duration) * (geo.size.width - 20) + 10
                            }
                        }()
                        
                        if x >= 10 && x <= geo.size.width - 10 {
                            Rectangle()
                                .fill(.blue.opacity(0.9))
                                .frame(width: 3, height: geo.size.height + 4)
                                .position(x: x, y: geo.size.height / 2)
                        }
                    }
                    
                    Rectangle()
                        .fill(DesignSystem.Colors.Semantic.secondary.opacity(0.3))
                        .frame(width: DesignSystem.Borders.thin)
                        .frame(height: geo.size.height)
                        .position(x: geo.size.width - 10 - DesignSystem.Padding.sm, y: geo.size.height / 2)
                    
                    Text(formatTime(duration))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.7))
                        .fixedSize()
                        .position(x: geo.size.width - 10 - DesignSystem.Padding.sm, y: geo.size.height + 6)
                    
                    if let range = normalizedVisibleTimeRange {
                        let startX = CGFloat(range.lowerBound / duration) * (geo.size.width - 20) + 10
                        let endX = CGFloat(range.upperBound / duration) * (geo.size.width - 20) + 10
                        let width = max(endX - startX, 20)
                        
                        ZStack {
                            Rectangle()
                                .fill(DesignSystem.Colors.Chart.primary.opacity(0.2))
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(DesignSystem.Colors.Chart.primary.opacity(0.6), lineWidth: DesignSystem.Borders.medium)
                                )
                            
                            if width > 80 {
                                HStack {
                                    Text(formatTimeShort(range.lowerBound))
                                        .font(.system(size: 7, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                .fill(DesignSystem.Colors.Chart.primary.opacity(0.95))
                                        )
                                    
                                    Spacer()
                                    
                                    Text(formatTimeShort(range.upperBound))
                                        .font(.system(size: 7, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                .fill(DesignSystem.Colors.Chart.primary.opacity(0.95))
                                        )
                                }
                                .padding(.horizontal, 3)
                            }
                        }
                        .frame(width: width, height: geo.size.height)
                        .position(x: startX + width / 2, y: geo.size.height / 2)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                        
                        TimelineRangeHandle(
                            x: startX,
                            geometry: geo,
                            isResizingLeft: isResizingLeft,
                            isResizingRight: isResizingRight,
                            isDraggingRange: isDraggingRange,
                            isLeftHandle: true
                        )
                        
                        TimelineRangeHandle(
                            x: endX,
                            geometry: geo,
                            isResizingLeft: isResizingLeft,
                            isResizingRight: isResizingRight,
                            isDraggingRange: isDraggingRange,
                            isLeftHandle: false
                        )
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
            .frame(height: 16)
        }
        .accessibilityLabel("Timeline zoom control")
    }
    
    private func isActuallyZoomed(_ range: ClosedRange<Double>) -> Bool {
        // Check if the range is actually zoomed (not the full duration)
        // Use a percentage-based tolerance to handle videos of different lengths
        let rangeDuration = range.upperBound - range.lowerBound
        let tolerance = max(0.1, duration * 0.001) // At least 0.1s, or 0.1% of duration, whichever is larger
        
        // Consider it NOT zoomed (i.e., full duration) if:
        // 1. Range starts at or very close to 0
        // 2. Range ends at or very close to full duration
        // 3. Range duration is at least 99.9% of full duration
        let startsAtZero = range.lowerBound <= tolerance
        let endsAtDuration = range.upperBound >= duration - tolerance
        let coversFullDuration = rangeDuration >= duration - tolerance
        
        // Only consider it zoomed if it doesn't cover the full duration
        let isFullDuration = startsAtZero && endsAtDuration && coversFullDuration
        
        return !isFullDuration
    }
    
    private func formatTime(_ seconds: Double) -> String {
        formatTimeForChart(seconds, frameRate: frameRate)
    }
    
    /// Formats time for display in timeline header
    private func formatTimeForDisplay(_ seconds: Double) -> String {
        formatTimeForChart(seconds, frameRate: frameRate)
    }
    
    private func formatTimeShort(_ seconds: Double) -> String {
        formatTimeForChart(seconds, frameRate: frameRate)
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

// MARK: - Timeline Range Handle

private struct TimelineRangeHandle: View {
    let x: CGFloat
    let geometry: GeometryProxy
    let isResizingLeft: Bool
    let isResizingRight: Bool
    let isDraggingRange: Bool
    let isLeftHandle: Bool
    
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.Chart.secondary)
            .frame(width: 2, height: geometry.size.height + 4)
            .position(x: x, y: geometry.size.height / 2)
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous))
            .allowsHitTesting(false)
            .onHover { hovering in
                if hovering && shouldShowCursor {
                    NSCursor.resizeLeftRight.push()
                } else if !hovering && shouldPopCursor {
                    NSCursor.pop()
                }
            }
    }
    
    private var shouldShowCursor: Bool {
        if isLeftHandle {
            return !isResizingRight && !isDraggingRange
        } else {
            return !isResizingLeft && !isDraggingRange
        }
    }
    
    private var shouldPopCursor: Bool {
        return !isResizingLeft && !isResizingRight && !isDraggingRange
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
        let minLabelSpacing: CGFloat = 70 // Minimum spacing between labels to avoid overlap (increased for HH:MM:SS:FF format)
        
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
            let maxX = geometry.size.width - 35 // Right boundary accounting for label width
            while currentTime <= endTime {
                // Calculate position within visible range
                let ratio = (currentTime - startTime) / visibleDuration
                let x = CGFloat(ratio) * totalWidth + 35 // Start with more padding to prevent cutoff
                
                // Only add if it fits within bounds and has enough space from previous label
                if x >= 35 && x <= maxX && abs(x - lastLabelX) >= minLabelSpacing {
                    labels.append((time: currentTime, x: x))
                    lastLabelX = x
                }
                
                currentTime += labelStep
            }
        } else {
            let startLabel = floor(0 / labelStep) * labelStep
            var lastLabelX: CGFloat = -minLabelSpacing
            
            let labelWidthEstimate: CGFloat = 60
            let maxX = geometry.size.width - 35 - labelWidthEstimate - 10
            
            for time in stride(from: startLabel, to: duration, by: labelStep) {
                let x = CGFloat(time / duration) * totalWidth + 35
                
                if x >= 35 && x <= maxX && abs(x - lastLabelX) >= minLabelSpacing {
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
                let labelWidthEstimate: CGFloat = 60
                let minX = 35 + labelWidthEstimate / 2
                let maxX = geometry.size.width - 35 - labelWidthEstimate
                let clampedX = min(max(label.x, minX), maxX)
                
                if clampedX >= minX && clampedX <= maxX {
                    Text(formatTime(label.time))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.7))
                        .fixedSize()
                        .position(x: clampedX, y: geometry.size.height + 6)
                }
            }
        }
    }
}

// MARK: - Timeline Ticks View

private struct TimelineTicksView: View {
    let duration: Double
    let visibleTimeRange: ClosedRange<Double>?
    let geometry: GeometryProxy
    let calculateLabelStep: (Double) -> Double
    
    private var tickPositions: [(x: CGFloat, isFirst: Bool, isLast: Bool)] {
        guard duration > 0 else { return [] }
        
        let totalWidth = geometry.size.width - 20
        let minLabelSpacing: CGFloat = 70
        let labelStep = calculateLabelStep(duration)
        let labelWidthEstimate: CGFloat = 60
        let minX = 35 + labelWidthEstimate / 2
        let maxX = geometry.size.width - 35 - labelWidthEstimate / 2
        
        var positions: [(x: CGFloat, isFirst: Bool, isLast: Bool)] = []
        
        if let range = visibleTimeRange {
            let visibleDuration = range.upperBound - range.lowerBound
            let startTime = range.lowerBound
            let endTime = range.upperBound
            let firstLabelTime = ceil(startTime / labelStep) * labelStep
            
            var lastLabelX: CGFloat = -minLabelSpacing
            var currentTime = firstLabelTime
            var labelTimes: [Double] = []
            
            while currentTime <= endTime {
                let ratio = (currentTime - startTime) / visibleDuration
                let x = CGFloat(ratio) * totalWidth + 35
                let clampedX = min(max(x, minX), maxX)
                
                if clampedX >= minX && clampedX <= maxX && abs(clampedX - lastLabelX) >= minLabelSpacing {
                    labelTimes.append(currentTime)
                    lastLabelX = clampedX
                }
                currentTime += labelStep
            }
            
            for (index, time) in labelTimes.enumerated() {
                let ratio = (time - startTime) / visibleDuration
                let x = CGFloat(ratio) * totalWidth + 35
                let clampedX = min(max(x, minX), maxX)
                let isFirst = index == 0
                let isLast = index == labelTimes.count - 1
                
                if isFirst {
                    positions.append((x: clampedX - labelWidthEstimate / 2, isFirst: true, isLast: false))
                } else if isLast {
                    positions.append((x: clampedX + labelWidthEstimate / 2, isFirst: false, isLast: true))
                } else {
                    positions.append((x: clampedX, isFirst: false, isLast: false))
                }
            }
        } else {
            let startLabel = floor(0 / labelStep) * labelStep
            var lastLabelX: CGFloat = -minLabelSpacing
            var labelTimes: [Double] = []
            
            for time in stride(from: startLabel, to: duration, by: labelStep) {
                let x = CGFloat(time / duration) * totalWidth + 35
                let clampedX = min(max(x, minX), maxX)
                
                if clampedX >= minX && clampedX <= maxX && abs(clampedX - lastLabelX) >= minLabelSpacing {
                    labelTimes.append(time)
                    lastLabelX = clampedX
                }
            }
            
            for (index, time) in labelTimes.enumerated() {
                let x = CGFloat(time / duration) * totalWidth + 35
                let clampedX = min(max(x, minX), maxX)
                let isFirst = index == 0
                let isLast = index == labelTimes.count - 1
                
                if isFirst {
                    positions.append((x: clampedX - labelWidthEstimate / 2, isFirst: true, isLast: false))
                } else if isLast {
                    positions.append((x: clampedX + labelWidthEstimate / 2, isFirst: false, isLast: true))
                } else {
                    positions.append((x: clampedX, isFirst: false, isLast: false))
                }
            }
        }
        
        return positions
    }
    
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let tickTop: CGFloat = 0
            let tickBottom: CGFloat = size.height
            
            for position in tickPositions {
                path.move(to: CGPoint(x: position.x, y: tickTop))
                path.addLine(to: CGPoint(x: position.x, y: tickBottom))
            }
            
            ctx.stroke(path, with: .color(DesignSystem.Colors.Semantic.secondary.opacity(0.3)), lineWidth: DesignSystem.Borders.thin)
        }
    }
}
