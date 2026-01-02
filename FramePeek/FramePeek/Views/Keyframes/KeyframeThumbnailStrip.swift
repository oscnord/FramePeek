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
    let totalKeyframes: Int
    @Binding var hoveredKeyframeTime: Double?
    var visibleTimeRange: ClosedRange<Double>? = nil
    @State private var hoveredThumb: KeyframeThumbnail? = nil
    @State private var hoveredIndex: Int? = nil
    
    private var filteredThumbs: [KeyframeThumbnail] {
        guard let range = visibleTimeRange else { return thumbs }
        return thumbs.filter { range.contains($0.time) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm3) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.Chart.keyframe)
                Text("Thumbnails")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .padding(.vertical, DesignSystem.Padding.md)
                
                Spacer()
                
                Group {
                    if let thumb = hoveredThumb, let index = hoveredIndex {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Text("\(index + 1)/\(filteredThumbs.count)")
                                .fontWeight(.medium)
                            Text(formatTime(thumb.time))
                                .monospacedDigit()
                            if let gopInterval = gopInterval(for: index) {
                                Text("GOP: \(gopInterval, specifier: "%.2f")s")
                                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            }
                        }
                        .font(.caption2)
                        .padding(.horizontal, DesignSystem.Padding.md)
                        .background(DesignSystem.Colors.Chart.keyframe.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Padding.sm2, style: .continuous))
                    } else {
                        if visibleTimeRange != nil {
                            Text("\(filteredThumbs.count) of \(thumbs.count) keyframes (zoomed)")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                        } else if totalKeyframes > thumbs.count {
                            Text("\(thumbs.count) of \(totalKeyframes) keyframes")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                        } else {
                            Text("\(thumbs.count) keyframes")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                        }
                    }
                }
                .frame(height: 20, alignment: .center)
            }
            .padding(.horizontal, DesignSystem.Padding.sm)
            strip
        }
        .padding(.horizontal, DesignSystem.Padding.md3)
        .background(DesignSystem.Materials.thin, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(.separator.opacity(0.25), lineWidth: DesignSystem.Borders.thin)
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
        guard index > 0, index < filteredThumbs.count else { return nil }
        return filteredThumbs[index].time - filteredThumbs[index - 1].time
    }
    
    private var strip: some View {
        DraggableScrollView(showsIndicators: false) {
            LazyHStack(spacing: DesignSystem.Spacing.sm3) {
                ForEach(Array(filteredThumbs.enumerated()), id: \.element.id) { index, t in
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
            .padding(.horizontal, DesignSystem.Padding.md3)
            .padding(.vertical, DesignSystem.Padding.sm)
        }
        .frame(height: 50)
        .overlayPreferenceValue(ThumbAnchorKey.self) { anchors in
            GeometryReader { geo in
                if let index = hoveredIndex,
                   index < filteredThumbs.count,
                   let anchor = anchors[index] {
                    let rect = geo[anchor]
                    let centerX = rect.midX
                    let centerY = rect.midY
                    
                    let enlargedWidth: CGFloat = 112
                    let minX = enlargedWidth / 2 + 4
                    let maxX = geo.size.width - enlargedWidth / 2 - 4
                    let clampedX = min(max(centerX, minX), maxX)
                    
                    EnlargedThumbView(image: filteredThumbs[index].image)
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
        let shape = RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
        
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 112, height: 72)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(DesignSystem.Colors.Chart.keyframe, lineWidth: 2.5)
            )
            .shadow(color: .black.opacity(0.5), radius: DesignSystem.Spacing.md2, y: 4)
    }
}

// MARK: - Draggable Scroll View

private struct DraggableScrollView<Content: View>: NSViewRepresentable {
    let showsIndicators: Bool
    let content: Content
    
    init(showsIndicators: Bool, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = showsIndicators
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        scrollView.documentView = hostingView
        
        scrollView.allowsMagnification = false
        
        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView
        
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.allowedTouchTypes = .direct
        scrollView.addGestureRecognizer(panGesture)
        
        if let documentView = scrollView.documentView {
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
            ])
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.hasHorizontalScroller = showsIndicators
        
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
        }
    }
    
    class Coordinator: NSObject {
        var hostingView: NSHostingView<Content>?
        var scrollView: NSScrollView?
        var lastScrollOrigin: NSPoint = .zero
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            
            switch gesture.state {
            case .began:
                lastScrollOrigin = scrollView.contentView.bounds.origin
            case .changed:
                let translation = gesture.translation(in: scrollView)
                var newOrigin = lastScrollOrigin
                newOrigin.x -= translation.x
                
                let documentWidth = scrollView.documentView?.frame.width ?? 0
                let visibleWidth = scrollView.contentView.bounds.width
                let maxX = max(0, documentWidth - visibleWidth)
                newOrigin.x = max(0, min(newOrigin.x, maxX))
                
                scrollView.contentView.scroll(to: newOrigin)
            default:
                break
            }
        }
    }
}

// MARK: - Thumb cell

private struct ThumbCell: View {
    let image: NSImage
    let isHovered: Bool
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignSystem.Padding.md, style: .continuous)
        
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 36)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isHovered ? DesignSystem.Colors.Chart.keyframe : DesignSystem.Colors.Semantic.primary.opacity(0.15),
                    lineWidth: isHovered ? DesignSystem.Borders.thick : DesignSystem.Borders.thin
                )
            )
            .shadow(color: .black.opacity(0.15), radius: DesignSystem.Spacing.xs, y: 1)
            .contentShape(shape)
    }
}
