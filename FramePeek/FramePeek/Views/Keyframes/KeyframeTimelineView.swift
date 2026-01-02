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
    
    // Cache for sorted keyframes and display keyframes to avoid recomputation
    @State private var cachedSortedKeyframes: [KeyframeMarker]? = nil
    @State private var cachedDisplayKeyframes: [KeyframeMarker]? = nil
    @State private var cachedMaxKeyframes: Int? = nil
    @State private var cachedKeyframesCount: Int = 0
    @State private var cachedHoveredTime: Double? = nil
    @State private var cachedNearestHoveredKeyframe: KeyframeMarker? = nil
    
    /// Downsampled keyframes to match chart resolution
    /// Evenly distributes keyframes across the video duration
    /// Optimized with caching and O(n) downsampling algorithm
    private var displayKeyframes: [KeyframeMarker] {
        // Check if we can use cached result
        let currentKeyframesCount = keyframes.count
        let needsRecompute = cachedDisplayKeyframes == nil ||
            cachedKeyframesCount != currentKeyframesCount ||
            cachedMaxKeyframes != maxKeyframes ||
            cachedHoveredTime != hoveredKeyframeTime
        
        if !needsRecompute, let cached = cachedDisplayKeyframes {
            return cached
        }
        
        guard let maxKeyframes = maxKeyframes, keyframes.count > maxKeyframes else {
            // Cache the result
            cachedSortedKeyframes = keyframes
            cachedDisplayKeyframes = keyframes
            cachedMaxKeyframes = maxKeyframes
            cachedKeyframesCount = currentKeyframesCount
            cachedHoveredTime = hoveredKeyframeTime
            return keyframes
        }
        
        // Get or compute sorted keyframes
        let sortedKeyframes: [KeyframeMarker]
        if let cached = cachedSortedKeyframes, cached.count == keyframes.count {
            sortedKeyframes = cached
        } else {
            sortedKeyframes = keyframes.sorted { $0.time < $1.time }
            cachedSortedKeyframes = sortedKeyframes
        }
        
        guard !sortedKeyframes.isEmpty, duration > 0 else {
            cachedDisplayKeyframes = keyframes
            cachedMaxKeyframes = maxKeyframes
            cachedKeyframesCount = currentKeyframesCount
            cachedHoveredTime = hoveredKeyframeTime
            return keyframes
        }
        
        // Optimized O(n) downsampling: single pass through sorted keyframes
        var selected: [KeyframeMarker] = []
        selected.reserveCapacity(maxKeyframes + 2) // +2 for first, last, and hovered
        
        let interval = duration / Double(maxKeyframes - 1)
        var keyframeIndex = 0
        
        // Single pass: for each target time, find nearest keyframe
        for i in 0..<maxKeyframes {
            let targetTime = Double(i) * interval
            
            // Advance keyframeIndex to find the closest keyframe to targetTime
            // Since both are sorted, we can do this in a single pass
            while keyframeIndex < sortedKeyframes.count - 1 {
                let current = sortedKeyframes[keyframeIndex]
                let next = sortedKeyframes[keyframeIndex + 1]
                
                // If next keyframe is closer, advance
                if abs(next.time - targetTime) < abs(current.time - targetTime) {
                    keyframeIndex += 1
                } else {
                    break
                }
            }
            
            let nearest = sortedKeyframes[keyframeIndex]
            
            // Avoid duplicates (check against last added)
            if selected.isEmpty || abs(selected.last!.time - nearest.time) > 0.001 {
                selected.append(nearest)
            }
        }
        
        // Ensure first and last keyframes are included
        if let first = sortedKeyframes.first, 
           selected.isEmpty || abs(selected.first!.time - first.time) > 0.001 {
            selected.insert(first, at: 0)
        }
        if let last = sortedKeyframes.last,
           selected.isEmpty || abs(selected.last!.time - last.time) > 0.001 {
            selected.append(last)
        }
        
        // Find and include nearest hovered keyframe if needed
        if let hoveredTime = hoveredKeyframeTime {
            // Use cached nearest hovered keyframe if available
            let nearestHoveredKeyframe: KeyframeMarker?
            if let cached = cachedNearestHoveredKeyframe, 
               abs(cached.time - hoveredTime) < 0.1 {
                nearestHoveredKeyframe = cached
            } else {
                // Binary search for nearest keyframe (O(log n))
                nearestHoveredKeyframe = findNearestKeyframe(to: hoveredTime, in: sortedKeyframes)
                cachedNearestHoveredKeyframe = nearestHoveredKeyframe
            }
            
            if let nearest = nearestHoveredKeyframe,
               abs(nearest.time - hoveredTime) < 0.1,
               !selected.contains(where: { abs($0.time - nearest.time) < 0.1 }) {
                selected.append(nearest)
            }
        }
        
        // Sort final result (should be mostly sorted already)
        let result = selected.sorted { $0.time < $1.time }
        
        // Update cache
        cachedDisplayKeyframes = result
        cachedMaxKeyframes = maxKeyframes
        cachedKeyframesCount = currentKeyframesCount
        cachedHoveredTime = hoveredKeyframeTime
        
        return result
    }
    
    /// Binary search to find nearest keyframe to a given time (O(log n))
    private func findNearestKeyframe(to time: Double, in sortedKeyframes: [KeyframeMarker]) -> KeyframeMarker? {
        guard !sortedKeyframes.isEmpty else { return nil }
        
        // Binary search for insertion point
        var left = 0
        var right = sortedKeyframes.count - 1
        
        while left < right {
            let mid = (left + right) / 2
            if sortedKeyframes[mid].time < time {
                left = mid + 1
            } else {
                right = mid
            }
        }
        
        // Check left and left-1 to find nearest
        var nearest = sortedKeyframes[left]
        var minDistance = abs(nearest.time - time)
        
        if left > 0 {
            let prev = sortedKeyframes[left - 1]
            let prevDistance = abs(prev.time - time)
            if prevDistance < minDistance {
                nearest = prev
                minDistance = prevDistance
            }
        }
        
        if left < sortedKeyframes.count - 1 {
            let next = sortedKeyframes[left + 1]
            let nextDistance = abs(next.time - time)
            if nextDistance < minDistance {
                nearest = next
            }
        }
        
        return nearest
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

                        // Use cached nearest hovered keyframe (computed in displayKeyframes)
                        let nearestHoveredKeyframe = cachedNearestHoveredKeyframe
                        
                        for k in displayKeyframes {
                            let x = CGFloat(k.time / duration) * (size.width - 20) + 10
                            
                            // Check if this keyframe is the nearest to the hovered time
                            let isHighlighted: Bool = {
                                guard let nearest = nearestHoveredKeyframe else { return false }
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
                        if let nearest = nearestHoveredKeyframe {
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
                        .highPriorityGesture(
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
                            // Don't handle if drag started within zoom window bounds
                            if let range = visibleTimeRange, isPointInZoomWindow(value.startLocation, range: range, geometry: geo) {
                                return
                            }
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
        .onChange(of: keyframes.count) { _ in
            // Invalidate cache when keyframes change
            cachedSortedKeyframes = nil
            cachedDisplayKeyframes = nil
            cachedNearestHoveredKeyframe = nil
        }
        .onChange(of: maxKeyframes) { _ in
            // Invalidate cache when maxKeyframes changes
            cachedDisplayKeyframes = nil
        }
    }
}

