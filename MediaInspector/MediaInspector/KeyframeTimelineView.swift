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
                }
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
}
