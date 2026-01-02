//
//  TimelineView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-09.
//

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "timeline.selection")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Timeline")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                if visibleTimeRange == nil {
                    Text("(Drag to zoom)")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                
                Spacer()
                
                if let range = visibleTimeRange {
                    let startTime = formatTime(range.lowerBound)
                    let endTime = formatTime(range.upperBound)
                    Text("\(startTime) - \(endTime)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            
            // Timeline
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.separator.opacity(0.2), lineWidth: 1)
                        )

                    // Time markers
                    Canvas { ctx, size in
                        guard duration > 0 else { return }
                        
                        var path = Path()
                        var zoomedPath = Path()
                        let tickTop: CGFloat = 4
                        let tickBottom: CGFloat = size.height - 4
                        
                        // Draw time markers at regular intervals
                        let numMarkers = 10
                        for i in 0...numMarkers {
                            let time = Double(i) * duration / Double(numMarkers)
                            let x = CGFloat(time / duration) * (size.width - 20) + 10
                            
                            // Highlight markers within zoom range
                            if let range = visibleTimeRange, range.contains(time) {
                                zoomedPath.move(to: CGPoint(x: x, y: tickTop - 1))
                                zoomedPath.addLine(to: CGPoint(x: x, y: tickBottom + 1))
                            } else {
                                path.move(to: CGPoint(x: x, y: tickTop))
                                path.addLine(to: CGPoint(x: x, y: tickBottom))
                            }
                        }
                        
                        // Draw normal markers
                        ctx.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                        // Draw highlighted markers in zoom range
                        ctx.stroke(zoomedPath, with: .color(.accentColor.opacity(0.6)), lineWidth: 1.5)
                    }
                    
                    // Zoom Window Overlay
                    if let range = visibleTimeRange {
                        let startX = CGFloat(range.lowerBound / duration) * (geo.size.width - 20) + 10
                        let endX = CGFloat(range.upperBound / duration) * (geo.size.width - 20) + 10
                        let width = max(endX - startX, 20) // Minimum width for handles
                        
                        // Main zoom window
                        ZStack {
                            // Background with gradient for better visibility
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.25),
                                            Color.accentColor.opacity(0.15)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                                )
                            
                            // Time labels on edges (only show if zoom window is wide enough)
                            if width > 80 {
                                HStack {
                                    // Start time label
                                    Text(formatTimeShort(range.lowerBound))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.95))
                                        )
                                    
                                    Spacer()
                                    
                                    // End time label
                                    Text(formatTimeShort(range.upperBound))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.95))
                                        )
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .frame(width: width, height: geo.size.height)
                        .position(x: startX + width / 2, y: geo.size.height / 2)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false) // Let the unified gesture handle it
                        
                        // Left resize handle
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: geo.size.height + 4)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 2, height: geo.size.height - 4)
                            )
                            .position(x: startX, y: geo.size.height / 2)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false) // Let the unified gesture handle it
                            .onHover { hovering in
                                if hovering && !isResizingRight && !isDraggingRange {
                                    NSCursor.resizeLeftRight.push()
                                } else if !hovering && !isResizingLeft && !isResizingRight && !isDraggingRange {
                                    NSCursor.pop()
                                }
                            }
                        
                        // Right resize handle
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: geo.size.height + 4)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 2, height: geo.size.height - 4)
                            )
                            .position(x: endX, y: geo.size.height / 2)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false) // Let the unified gesture handle it
                            .onHover { hovering in
                                if hovering && !isResizingLeft && !isDraggingRange {
                                    NSCursor.resizeLeftRight.push()
                                } else if !hovering && !isResizingLeft && !isResizingRight && !isDraggingRange {
                                    NSCursor.pop()
                                }
                            }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleUnifiedDrag(value: value, geometry: geo)
                        }
                        .onEnded { _ in
                            // Reset all drag states
                            isDraggingRange = false
                            isResizingLeft = false
                            isResizingRight = false
                            dragStartRange = nil
                            dragStartLocation = nil
                            selectionDragStart = nil
                            NSCursor.pop()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                visibleTimeRange = nil
                            }
                        }
                )
            }
            .frame(height: 20)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: 1)
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
}

extension TimelineView {
    /// Unified drag handler that determines the action based on where the drag starts
    func handleUnifiedDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        guard duration > 0 else { return }
        
        let startX = value.startLocation.x
        let totalWidth = geometry.size.width - 20
        
        // If already resizing or dragging, continue that action
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
        
        // Determine what we're interacting with based on start location (only on first drag)
        if let range = visibleTimeRange {
            let windowStartX = CGFloat(range.lowerBound / duration) * totalWidth + 10
            let windowEndX = CGFloat(range.upperBound / duration) * totalWidth + 10
            let handleWidth: CGFloat = 8
            let handleTolerance: CGFloat = 6 // Slightly larger tolerance for easier grabbing
            
            // Check if drag started on left resize handle
            if startX >= windowStartX - handleTolerance && startX <= windowStartX + handleTolerance {
                isResizingLeft = true
                dragStartRange = range
                dragStartX = windowStartX
                handleLeftResize(value: value, geometry: geometry, currentRange: range, startX: windowStartX)
                return
            }
            
            // Check if drag started on right resize handle
            if startX >= windowEndX - handleTolerance && startX <= windowEndX + handleTolerance {
                isResizingRight = true
                dragStartRange = range
                dragStartX = windowEndX
                handleRightResize(value: value, geometry: geometry, currentRange: range, endX: windowEndX)
                return
            }
            
            // Check if drag started within zoom window (but not on handles)
            if startX >= windowStartX + handleTolerance && startX <= windowEndX - handleTolerance {
                isDraggingRange = true
                dragStartRange = range
                dragStartLocation = startX
                handleDrag(value: value, geometry: geometry)
                return
            }
        }
        
        // Otherwise, create new selection
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
        
        // Clamp to duration while maintaining window size if possible
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
        
        // Dragging to create new selection
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
        // Calculate new position: original position + translation
        let newX = startX + value.translation.width
        // Convert to time (accounting for the 10px padding)
        let newStartTime = max(0.0, min(duration, (Double(newX - 10) / Double(totalWidth)) * duration))
        
        // Ensure minimum zoom size and bounds
        let minZoomSize = duration * 0.01
        let maxEnd = currentRange.upperBound
        let clampedStart = max(0.0, min(maxEnd - minZoomSize, newStartTime))
        
        visibleTimeRange = clampedStart...maxEnd
    }
    
    func handleRightResize(value: DragGesture.Value, geometry: GeometryProxy, currentRange: ClosedRange<Double>, endX: CGFloat) {
        guard duration > 0 else { return }
        
        let totalWidth = geometry.size.width - 20
        // Calculate new position: original position + translation
        let newX = endX + value.translation.width
        // Convert to time (accounting for the 10px padding)
        let newEndTime = max(0.0, min(duration, (Double(newX - 10) / Double(totalWidth)) * duration))
        
        // Ensure minimum zoom size and bounds
        let minZoomSize = duration * 0.01
        let minStart = currentRange.lowerBound
        let clampedEnd = min(duration, max(minStart + minZoomSize, newEndTime))
        
        visibleTimeRange = minStart...clampedEnd
    }
}
