//
//  KeyframeThumbnailStrip.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-09.
//

import SwiftUI
import AppKit

struct KeyframeThumbnailStrip: View {
    let thumbs: [KeyframeThumbnail]
    @Binding var hoveredKeyframeTime: Double?
    @State private var hoveredID: KeyframeThumbnail.ID? = nil
    
    var body: some View {
        strip
        // ✅ Preview drawn above the strip (and not clipped by the strip's clipShape)
            .overlayPreferenceValue(ThumbAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let id = hoveredID,
                       let anchor = anchors[id],
                       let thumbIndex = thumbs.firstIndex(where: { $0.id == id }),
                       let thumb = thumbs.first(where: { $0.id == id }) {
                        
                        let rect = proxy[anchor]
                        let previousTime: Double? = thumbIndex > 0 ? thumbs[thumbIndex - 1].time : nil
                        
                        HoverPreview(
                            image: thumb.image,
                            time: thumb.time,
                            index: thumbIndex + 1,
                            total: thumbs.count,
                            previousKeyframeTime: previousTime
                        )
                        .position(
                            x: clamp(rect.midX, min: 140, max: proxy.size.width - 140),
                            y: rect.minY - 100
                        )
                        .allowsHitTesting(false)
                        .zIndex(999)
                    }
                }
            }
    }
    
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(thumbs) { t in
                    ThumbCell(image: t.image, time: t.time, isHovered: hoveredID == t.id)
                        .anchorPreference(key: ThumbAnchorKey.self, value: .bounds) { anchor in
                            [t.id: anchor]
                        }
                        .onHover { isHovering in
                            if isHovering {
                                hoveredID = t.id
                                hoveredKeyframeTime = t.time
                            } else if hoveredID == t.id {
                                hoveredID = nil
                                hoveredKeyframeTime = nil
                            }
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 56)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private func clamp(_ x: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(x, min), max)
    }
}

// MARK: - Thumb cell

private struct ThumbCell: View {
    let image: NSImage
    let time: Double
    let isHovered: Bool
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 60, height: 38)
            .padding(4)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.25), lineWidth: 1))
            .contentShape(shape)
    }
}

// MARK: - Hover preview

private struct HoverPreview: View {
    let image: NSImage
    let time: Double
    let index: Int
    let total: Int
    let previousKeyframeTime: Double?
    
    // You can tweak these
    private let maxContentWidth: CGFloat = 260   // width of the image area
    private let maxContentHeight: CGFloat = 160  // cap so super-tall images don't explode
    
    private var aspect: CGFloat {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return 16.0 / 9.0 }
        return s.width / s.height
    }
    
    private var contentSize: CGSize {
        // width is fixed; compute height from aspect ratio, clamp to maxContentHeight
        let w = maxContentWidth
        let h = min(maxContentHeight, w / aspect)
        return CGSize(width: w, height: h)
    }
    
    private var gopInterval: Double? {
        guard let prev = previousKeyframeTime else { return nil }
        return time - prev
    }
    
    private var formattedTimecode: String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let millis = Int((time - Double(totalSeconds)) * 1000)
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, seconds, millis)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
        }
    }
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let imgSize = contentSize
        
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail image
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: imgSize.width, height: imgSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // Info grid
            VStack(alignment: .leading, spacing: 6) {
                // Keyframe index
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.orange)
                    Text("Keyframe \(index) of \(total)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                
                Divider()
                
                // Timestamp row
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(formattedTimecode)
                        .monospacedDigit()
                        .font(.caption)
                    Text("(\(time, specifier: "%.3f")s)")
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                
                // GOP interval (if available)
                if let gop = gopInterval {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.and.right")
                            .foregroundStyle(.secondary)
                        Text("GOP: \(gop, specifier: "%.3f")s")
                            .monospacedDigit()
                            .font(.caption)
                        Text("(\(gop > 0 ? String(format: "%.1f", 1.0 / gop) : "–") KF/s)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(12)
        .fixedSize()
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator.opacity(0.25), lineWidth: 1))
        .shadow(radius: 14)
        .compositingGroup()
    }
}

// MARK: - PreferenceKey

private struct ThumbAnchorKey: PreferenceKey {
    static var defaultValue: [KeyframeThumbnail.ID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [KeyframeThumbnail.ID: Anchor<CGRect>],
                       nextValue: () -> [KeyframeThumbnail.ID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
