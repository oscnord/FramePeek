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
    @State private var hoveredID: KeyframeThumbnail.ID? = nil
    
    var body: some View {
        strip
        // ✅ Preview drawn above the strip (and not clipped by the strip's clipShape)
            .overlayPreferenceValue(ThumbAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let id = hoveredID,
                       let anchor = anchors[id],
                       let thumb = thumbs.first(where: { $0.id == id }) {
                        
                        let rect = proxy[anchor]
                        
                        HoverPreview(image: thumb.image, time: thumb.time)
                            .position(
                                x: clamp(rect.midX, min: 120, max: proxy.size.width - 120),
                                y: rect.minY - 72
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
                            hoveredID = isHovering ? t.id : (hoveredID == t.id ? nil : hoveredID)
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
    
    // You can tweak these
    private let maxContentWidth: CGFloat = 240   // width of the image area
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
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let imgSize = contentSize
        
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: imgSize.width, height: imgSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("\(time, specifier: "%.2f") s")
                    .monospacedDigit()
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
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
