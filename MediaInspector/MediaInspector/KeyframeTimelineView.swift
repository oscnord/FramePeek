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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator.opacity(0.25), lineWidth: 1)
                    )

                // ticks
                Canvas { ctx, size in
                    guard duration > 0 else { return }

                    var normalPath = Path()
                    var highlightedPath = Path()
                    let h = 50.0
                    let tickTop: CGFloat = 3
                    let tickBottom: CGFloat = h - 3

                    for k in keyframes {
                        let x = CGFloat(k.time / duration) * size.width
                        
                        // Check if this keyframe is the hovered one (within small tolerance)
                        let isHighlighted = hoveredKeyframeTime.map { abs($0 - k.time) < 0.001 } ?? false
                        
                        if isHighlighted {
                            highlightedPath.move(to: CGPoint(x: x, y: tickTop))
                            highlightedPath.addLine(to: CGPoint(x: x, y: tickBottom))
                        } else {
                            normalPath.move(to: CGPoint(x: x, y: tickTop))
                            normalPath.addLine(to: CGPoint(x: x, y: tickBottom))
                        }
                    }

                    ctx.stroke(normalPath, with: .color(.secondary.opacity(0.55)), lineWidth: 1)
                    ctx.stroke(highlightedPath, with: .color(.accentColor), lineWidth: 3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(height: 26)
        .accessibilityLabel("Keyframe timeline")
    }
}
