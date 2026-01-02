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
    
    func isPointInZoomWindow(_ point: CGPoint, range: ClosedRange<Double>, geometry: GeometryProxy) -> Bool {
        guard duration > 0 else { return false }
        
        let startX = CGFloat(range.lowerBound / duration) * (geometry.size.width - 20) + 10
        let endX = CGFloat(range.upperBound / duration) * (geometry.size.width - 20) + 10
        let width = max(endX - startX, 10)
        
        let windowLeft = startX - 2
        let windowRight = endX + 2
        
        return point.x >= windowLeft && point.x <= windowRight
    }
}

