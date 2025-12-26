//
//  KeyframeTimelineView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-09.
//

import SwiftUI

struct KeyframeTimelineView: View {
    let keyframes: [KeyframeMarker]
    let duration: Double
    var hoveredKeyframeTime: Double? = nil
    @Binding var visibleTimeRange: ClosedRange<Double>?
    var maxKeyframes: Int? = nil  // Optional limit to match chart resolution

    @State var isDraggingRange = false
    @State var dragStartRange: ClosedRange<Double>?
    @State var dragStartLocation: CGFloat?
    @State var selectionDragStart: CGFloat? // Separate state for selection drag
    
    /// Downsampled keyframes to match chart resolution
    /// Evenly distributes keyframes across the video duration
    private var displayKeyframes: [KeyframeMarker] {
        guard let maxKeyframes = maxKeyframes, keyframes.count > maxKeyframes else {
            return keyframes
        }
        
        let sortedKeyframes = keyframes.sorted { $0.time < $1.time }
        guard !sortedKeyframes.isEmpty, duration > 0 else { return keyframes }
        
        var selected: [KeyframeMarker] = []
        selected.reserveCapacity(maxKeyframes)
        
        let interval = duration / Double(maxKeyframes - 1)
        var keyframeIndex = 0
        
        // For each target time, find the nearest keyframe
        for i in 0..<maxKeyframes {
            let targetTime = Double(i) * interval
            
            // Find the keyframe closest to targetTime
            // Since keyframes are sorted, we can advance through them efficiently
            var bestKeyframe: KeyframeMarker?
            var bestDistance = Double.greatestFiniteMagnitude
            
            // Start from where we left off and search forward
            while keyframeIndex < sortedKeyframes.count {
                let keyframe = sortedKeyframes[keyframeIndex]
                let distance = abs(keyframe.time - targetTime)
                
                if distance < bestDistance {
                    bestDistance = distance
                    bestKeyframe = keyframe
                } else {
                    // Distance is increasing, we've passed the best match
                    // Check if previous keyframe was better
                    if keyframeIndex > 0 {
                        let prevKeyframe = sortedKeyframes[keyframeIndex - 1]
                        let prevDistance = abs(prevKeyframe.time - targetTime)
                        if prevDistance < bestDistance {
                            bestKeyframe = prevKeyframe
                            bestDistance = prevDistance
                            keyframeIndex -= 1  // Back up one
                        }
                    }
                    break
                }
                keyframeIndex += 1
            }
            
            // If we reached the end, use the last keyframe
            if bestKeyframe == nil && !sortedKeyframes.isEmpty {
                bestKeyframe = sortedKeyframes.last
            }
            
            if let nearest = bestKeyframe {
                // Avoid duplicates
                if selected.isEmpty || abs(selected.last!.time - nearest.time) > 0.001 {
                    selected.append(nearest)
                }
            }
        }
        
        // Ensure first and last keyframes are included
        if let first = sortedKeyframes.first, !selected.contains(where: { abs($0.time - first.time) < 0.001 }) {
            selected.insert(first, at: 0)
        }
        if let last = sortedKeyframes.last, !selected.contains(where: { abs($0.time - last.time) < 0.001 }) {
            selected.append(last)
        }
        
        // Always include the nearest keyframe to the hovered time if it exists
        // This ensures hover highlighting works even when downsampling
        // Note: thumbnails are generated from evenly distributed times, not keyframe times,
        // so we need to find the nearest keyframe to the hovered thumbnail time
        if let hoveredTime = hoveredKeyframeTime {
            // Find the nearest keyframe to the hovered time
            if let nearestHoveredKeyframe = sortedKeyframes.min(by: { 
                abs($0.time - hoveredTime) < abs($1.time - hoveredTime) 
            }) {
                // Use a tolerance of 0.1 seconds to match the display logic
                if abs(nearestHoveredKeyframe.time - hoveredTime) < 0.1 {
                    if !selected.contains(where: { abs($0.time - nearestHoveredKeyframe.time) < 0.1 }) {
                        selected.append(nearestHoveredKeyframe)
                    }
                }
            }
        }
        
        return selected.sorted { $0.time < $1.time }
    }

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
                
                if let maxKeyframes = maxKeyframes, keyframes.count > maxKeyframes {
                    Text("\(displayKeyframes.count) of \(keyframes.count) keyframes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(keyframes.count) keyframes")
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

                    // Ticks
                    Canvas { ctx, size in
                        guard duration > 0 else { return }

                        var normalPath = Path()
                        var highlightedPath = Path()
                        let tickTop: CGFloat = 4
                        let tickBottom: CGFloat = size.height - 4

                        // Find the nearest keyframe to the hovered time (if any)
                        let nearestHoveredKeyframe: KeyframeMarker? = {
                            guard let hoveredTime = hoveredKeyframeTime else { return nil }
                            // Find the nearest keyframe to the hovered time
                            return keyframes.min(by: { abs($0.time - hoveredTime) < abs($1.time - hoveredTime) })
                        }()
                        
                        for k in displayKeyframes {
                            let x = CGFloat(k.time / duration) * (size.width - 20) + 10
                            
                            // Check if this keyframe is the nearest to the hovered time
                            let isHighlighted: Bool = {
                                guard let hoveredTime = hoveredKeyframeTime,
                                      let nearest = nearestHoveredKeyframe else { return false }
                                // Use a more lenient tolerance for matching (0.1 seconds)
                                // since thumbnails might not be at exact keyframe times
                                return abs(k.time - nearest.time) < 0.1
                            }()
                            
                            if isHighlighted {
                                highlightedPath.move(to: CGPoint(x: x, y: tickTop - 2))
                                highlightedPath.addLine(to: CGPoint(x: x, y: tickBottom + 2))
                            } else {
                                normalPath.move(to: CGPoint(x: x, y: tickTop))
                                normalPath.addLine(to: CGPoint(x: x, y: tickBottom))
                            }
                        }
                        
                        // Also draw the nearest keyframe to hovered time if it's not in displayKeyframes
                        if let hoveredTime = hoveredKeyframeTime,
                           let nearest = nearestHoveredKeyframe {
                            let isInDisplay = displayKeyframes.contains { abs($0.time - nearest.time) < 0.1 }
                            if !isInDisplay {
                                let x = CGFloat(nearest.time / duration) * (size.width - 20) + 10
                                highlightedPath.move(to: CGPoint(x: x, y: tickTop - 2))
                                highlightedPath.addLine(to: CGPoint(x: x, y: tickBottom + 2))
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
                            withAnimation {
                                visibleTimeRange = nil
                            }
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
        .accessibilityLabel("Keyframe timeline with \(displayKeyframes.count) of \(keyframes.count) keyframes")
    }
}

