//
//  KeyframeTimelineDragHandling.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//

import SwiftUI

extension KeyframeTimelineView {
    func handleDrag(value: DragGesture.Value, geometry: GeometryProxy) {
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
    
    func handleNewSelectionDrag(value: DragGesture.Value, geometry: GeometryProxy) {
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
        
        let timeRange = maxTime - minTime
        let minZoomSize: Double = self.duration * 0.01
        if timeRange > minZoomSize { // Minimum zoom size
            visibleTimeRange = minTime...maxTime
        }
    }
}

