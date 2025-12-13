//
//  KeyframeThumbnailStrip.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//

import SwiftUI
import AppKit

// MARK: - Anchor Preference for tracking thumb positions

private struct ThumbAnchorKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct KeyframeThumbnailStrip: View {
    let thumbs: [KeyframeThumbnail]
    let totalKeyframes: Int  // Total keyframes in the video (may be more than thumbs.count)
    @Binding var hoveredKeyframeTime: Double?
    @State private var hoveredThumb: KeyframeThumbnail? = nil
    @State private var hoveredIndex: Int? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with hover info
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Keyframe Thumbnails")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Show hover info in header area - fixed height to prevent jumping
                Group {
                    if let thumb = hoveredThumb, let index = hoveredIndex {
                        HStack(spacing: 8) {
                            Text("\(index + 1)/\(thumbs.count)")
                                .fontWeight(.medium)
                            Text(formatTime(thumb.time))
                                .monospacedDigit()
                            if let gopInterval = gopInterval(for: index) {
                                Text("GOP: \(gopInterval, specifier: "%.2f")s")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .background(.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        if totalKeyframes > thumbs.count {
                            Text("\(thumbs.count) of \(totalKeyframes) keyframes")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("\(thumbs.count) keyframes")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 20, alignment: .center)  // Fixed height prevents jumping
            }
            .padding(.horizontal, 4)
            
            strip
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: 1)
        )
    }
    
    private func formatTime(_ time: Double) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millis = Int((time - Double(totalSeconds)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, millis)
    }
    
    private func gopInterval(for index: Int) -> Double? {
        guard index > 0 else { return nil }
        return thumbs[index].time - thumbs[index - 1].time
    }
    
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(Array(thumbs.enumerated()), id: \.element.id) { index, t in
                    ThumbCell(
                        image: t.image,
                        isHovered: hoveredIndex == index
                    )
                    .anchorPreference(key: ThumbAnchorKey.self, value: .bounds) { anchor in
                        [index: anchor]
                    }
                    .onHover { isHovering in
                        if isHovering {
                            hoveredThumb = t
                            hoveredIndex = index
                            hoveredKeyframeTime = t.time
                        } else if hoveredIndex == index {
                            hoveredThumb = nil
                            hoveredIndex = nil
                            hoveredKeyframeTime = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.06),
                            Color.black.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.15), lineWidth: 1)
        )
        // Enlarged thumbnail overlay using anchor preferences
        .overlayPreferenceValue(ThumbAnchorKey.self) { anchors in
            GeometryReader { geo in
                if let index = hoveredIndex,
                   index < thumbs.count,
                   let anchor = anchors[index] {
                    let rect = geo[anchor]
                    let centerX = rect.midX
                    let centerY = rect.midY
                    
                    // Clamp position to keep enlarged view within bounds
                    let enlargedWidth: CGFloat = 112
                    let minX = enlargedWidth / 2 + 4
                    let maxX = geo.size.width - enlargedWidth / 2 - 4
                    let clampedX = min(max(centerX, minX), maxX)
                    
                    EnlargedThumbView(image: thumbs[index].image)
                        .position(x: clampedX, y: centerY)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Enlarged thumbnail overlay

private struct EnlargedThumbView: View {
    let image: NSImage
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 112, height: 72)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Color.orange, lineWidth: 2.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}

// MARK: - Thumb cell

private struct ThumbCell: View {
    let image: NSImage
    let isHovered: Bool
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 36)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isHovered ? Color.orange : Color.white.opacity(0.1),
                    lineWidth: isHovered ? 2 : 1
                )
            )
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .contentShape(shape)
    }
}
