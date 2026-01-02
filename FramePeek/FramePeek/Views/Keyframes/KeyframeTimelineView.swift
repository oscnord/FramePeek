import SwiftUI

struct KeyframeTimelineView: View {
    let keyframes: [KeyframeMarker]
    let duration: Double
    var hoveredKeyframeTime: Double? = nil
    @Binding var visibleTimeRange: ClosedRange<Double>?
    var maxKeyframes: Int? = nil

    @State var isDraggingRange = false
    @State var dragStartRange: ClosedRange<Double>?
    @State var dragStartLocation: CGFloat?
    @State var selectionDragStart: CGFloat?
    
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
        let currentKeyframesCount = keyframes.count
        let needsRecompute = cachedDisplayKeyframes == nil ||
            cachedKeyframesCount != currentKeyframesCount ||
            cachedMaxKeyframes != maxKeyframes ||
            cachedHoveredTime != hoveredKeyframeTime
        
        if !needsRecompute, let cached = cachedDisplayKeyframes {
            return cached
        }
        
        guard let maxKeyframes = maxKeyframes, keyframes.count > maxKeyframes else {
            cachedSortedKeyframes = keyframes
            cachedDisplayKeyframes = keyframes
            cachedMaxKeyframes = maxKeyframes
            cachedKeyframesCount = currentKeyframesCount
            cachedHoveredTime = hoveredKeyframeTime
            return keyframes
        }
        
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
        
        var selected: [KeyframeMarker] = []
        selected.reserveCapacity(maxKeyframes + 2) // +2 for first, last, and hovered
        
        let interval = duration / Double(maxKeyframes - 1)
        var keyframeIndex = 0
        
        for i in 0..<maxKeyframes {
            let targetTime = Double(i) * interval
            
            while keyframeIndex < sortedKeyframes.count - 1 {
                let current = sortedKeyframes[keyframeIndex]
                let next = sortedKeyframes[keyframeIndex + 1]
                
                if abs(next.time - targetTime) < abs(current.time - targetTime) {
                    keyframeIndex += 1
                } else {
                    break
                }
            }
            
            let nearest = sortedKeyframes[keyframeIndex]
            
            if selected.isEmpty || abs(selected.last!.time - nearest.time) > 0.001 {
                selected.append(nearest)
            }
        }
        
        if let first = sortedKeyframes.first, 
           selected.isEmpty || abs(selected.first!.time - first.time) > 0.001 {
            selected.insert(first, at: 0)
        }
        if let last = sortedKeyframes.last,
           selected.isEmpty || abs(selected.last!.time - last.time) > 0.001 {
            selected.append(last)
        }
        
        if let hoveredTime = hoveredKeyframeTime {
            let nearestHoveredKeyframe: KeyframeMarker?
            if let cached = cachedNearestHoveredKeyframe, 
               abs(cached.time - hoveredTime) < 0.1 {
                nearestHoveredKeyframe = cached
            } else {
                nearestHoveredKeyframe = findNearestKeyframe(to: hoveredTime, in: sortedKeyframes)
                cachedNearestHoveredKeyframe = nearestHoveredKeyframe
            }
            
            if let nearest = nearestHoveredKeyframe,
               abs(nearest.time - hoveredTime) < 0.1,
               !selected.contains(where: { abs($0.time - nearest.time) < 0.1 }) {
                selected.append(nearest)
            }
        }
        
        let result = selected.sorted { $0.time < $1.time }
        
        cachedDisplayKeyframes = result
        cachedMaxKeyframes = maxKeyframes
        cachedKeyframesCount = currentKeyframesCount
        cachedHoveredTime = hoveredKeyframeTime
        
        return result
    }
    
    /// Binary search to find nearest keyframe to a given time (O(log n))
    private func findNearestKeyframe(to time: Double, in sortedKeyframes: [KeyframeMarker]) -> KeyframeMarker? {
        guard !sortedKeyframes.isEmpty else { return nil }
        
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm3) {
            HStack(spacing: DesignSystem.Spacing.sm3) {
                Image(systemName: "film")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.Chart.keyframe)
                Text("Keyframe Distribution")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                
                if visibleTimeRange == nil {
                    Text("(Drag to zoom)")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.7))
                }
                
                Spacer()
                
                if let maxKeyframes = maxKeyframes, keyframes.count > maxKeyframes {
                    Text("\(displayKeyframes.count) of \(keyframes.count) keyframes")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                } else {
                    Text("\(keyframes.count) keyframes")
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

                    Canvas { ctx, size in
                        guard duration > 0 else { return }

                        var normalPath = Path()
                        var highlightedPath = Path()
                        let tickTop: CGFloat = 4
                        let tickBottom: CGFloat = size.height - 4

                        let nearestHoveredKeyframe = cachedNearestHoveredKeyframe
                        
                        for k in displayKeyframes {
                            let x = CGFloat(k.time / duration) * (size.width - 20) + 10
                            
                            let isHighlighted: Bool = {
                                guard let nearest = nearestHoveredKeyframe else { return false }
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
                        
                        if let nearest = nearestHoveredKeyframe {
                            let isInDisplay = displayKeyframes.contains { abs($0.time - nearest.time) < 0.1 }
                            if !isInDisplay {
                                let x = CGFloat(nearest.time / duration) * (size.width - 20) + 10
                                highlightedPath.move(to: CGPoint(x: x, y: tickTop - 2))
                                highlightedPath.addLine(to: CGPoint(x: x, y: tickBottom + 2))
                            }
                        }

                        ctx.stroke(normalPath, with: .color(DesignSystem.Colors.Chart.keyframe.opacity(0.5)), lineWidth: DesignSystem.Borders.medium)
                        
                        if hoveredKeyframeTime != nil {
                            ctx.stroke(highlightedPath, with: .color(DesignSystem.Colors.Chart.keyframe), lineWidth: DesignSystem.Borders.thick)
                        }
                    }
                    
                    if let range = visibleTimeRange {
                        let startX = CGFloat(range.lowerBound / duration) * (geo.size.width - 20) + 10
                        let endX = CGFloat(range.upperBound / duration) * (geo.size.width - 20) + 10
                        let width = max(endX - startX, 10) // Minimum width handle
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                .fill(DesignSystem.Colors.Chart.primary.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                        .stroke(DesignSystem.Colors.Chart.primary, lineWidth: DesignSystem.Borders.thin)
                                )
                            
                            HStack {
                                Rectangle()
                                    .fill(DesignSystem.Colors.Chart.primary.opacity(0.5))
                                    .frame(width: 4)
                                Spacer()
                                Rectangle()
                                    .fill(DesignSystem.Colors.Chart.primary.opacity(0.5))
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
                        .onTapGesture(count: 2) {
                            withAnimation {
                                visibleTimeRange = nil
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
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
        .padding(.vertical, DesignSystem.Padding.md)
        .padding(.horizontal, DesignSystem.Padding.md3)
        .background(DesignSystem.Materials.thin, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: DesignSystem.Borders.thin)
        )
        .accessibilityLabel("Keyframe timeline with \(displayKeyframes.count) of \(keyframes.count) keyframes")
        .onChange(of: keyframes.count) { _ in
            cachedSortedKeyframes = nil
            cachedDisplayKeyframes = nil
            cachedNearestHoveredKeyframe = nil
        }
        .onChange(of: maxKeyframes) { _ in
            cachedDisplayKeyframes = nil
        }
    }
}

