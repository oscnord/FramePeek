//
//  KeyframeTimelineView.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//


import SwiftUI

struct KeyframeTimelineView: View {
    let keyframes: [KeyframeMarker]
    let duration: Double
    var hoveredKeyframeTime: Double? = nil
    @Binding var visibleTimeRange: ClosedRange<Double>?

    @State private var isDraggingRange = false
    @State private var dragStartRange: ClosedRange<Double>?
    @State private var dragStartLocation: CGFloat?
    @State private var selectionDragStart: CGFloat? // Separate state for selection drag

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "film")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Keyframe Distribution")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                if visibleTimeRange == nil {
                    Text("(Drag to zoom)")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                
                Spacer()
                
                Text("\(keyframes.count) keyframes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

                    // Ticks
                    Canvas { ctx, size in
                        guard duration > 0 else { return }

                        var normalPath = Path()
                        var highlightedPath = Path()
                        let tickTop: CGFloat = 4
                        let tickBottom: CGFloat = size.height - 4

                        for k in keyframes {
                            let x = CGFloat(k.time / duration) * (size.width - 20) + 10
                            
                            let isHighlighted = hoveredKeyframeTime.map { abs($0 - k.time) < 0.001 } ?? false
                            
                            if isHighlighted {
                                highlightedPath.move(to: CGPoint(x: x, y: tickTop - 2))
                                highlightedPath.addLine(to: CGPoint(x: x, y: tickBottom + 2))
                            } else {
                                normalPath.move(to: CGPoint(x: x, y: tickTop))
                                normalPath.addLine(to: CGPoint(x: x, y: tickBottom))
                            }
                        }

                        // Draw normal ticks with gradient-like effect
                        ctx.stroke(normalPath, with: .color(.orange.opacity(0.5)), lineWidth: 1.5)
                        
                        // Draw highlighted tick
                        if hoveredKeyframeTime != nil {
                            ctx.stroke(highlightedPath, with: .color(.orange), lineWidth: 3)
                        }
                    }
                    
                    // Zoom Window Overlay
                    if let range = visibleTimeRange {
                        let startX = CGFloat(range.lowerBound / duration) * (geo.size.width - 20) + 10
                        let endX = CGFloat(range.upperBound / duration) * (geo.size.width - 20) + 10
                        let width = max(endX - startX, 10) // Minimum width handle
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: 1)
                                )
                            
                            // Drag handles
                            HStack {
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.5))
                                    .frame(width: 4)
                                Spacer()
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.5))
                                    .frame(width: 4)
                            }
                        }
                        .frame(width: width, height: geo.size.height)
                        .position(x: startX + width / 2, y: geo.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleDrag(value: value, geometry: geo)
                                }
                                .onEnded { _ in
                                    isDraggingRange = false
                                    dragStartRange = nil
                                    dragStartLocation = nil
                                }
                        )
                        // Double tap to reset zoom
                        .onTapGesture(count: 2) {
                            visibleTimeRange = nil
                        }
                    }
                }
                .gesture(
                    // Click to set zoom window or drag to create new one
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if visibleTimeRange == nil || !isDraggingRange {
                                handleNewSelectionDrag(value: value, geometry: geo)
                            }
                        }
                        .onEnded { _ in
                            selectionDragStart = nil
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
        .accessibilityLabel("Keyframe timeline with \(keyframes.count) keyframes")
    }
    
    private func handleDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        guard duration > 0 else { return }
        
        if !isDraggingRange {
            isDraggingRange = true
            dragStartRange = visibleTimeRange
            dragStartLocation = value.startLocation.x
        }
        
        guard let startRange = dragStartRange, let startLoc = dragStartLocation else { return }
        
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
    
    private func handleNewSelectionDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        guard duration > 0 else { return }
        
        if selectionDragStart == nil {
            selectionDragStart = value.startLocation.x
        }
        
        guard let startLoc = selectionDragStart else { return }
        
        let totalWidth = geometry.size.width - 20
        let x = value.location.x - 10
        let time = max(0, min(duration, (Double(x) / Double(totalWidth)) * duration))
        
        // Dragging to create new selection
        let startX = startLoc - 10
        let startTime = max(0, min(duration, (Double(startX) / Double(totalWidth)) * duration))
        
        let minTime = min(startTime, time)
        let maxTime = max(startTime, time)
        
        if maxTime - minTime > duration * 0.01 { // Minimum zoom size
            visibleTimeRange = minTime...maxTime
        }
    }
}
