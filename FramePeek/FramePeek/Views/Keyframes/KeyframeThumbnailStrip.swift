import SwiftUI
import AppKit


struct KeyframeThumbnailStrip: View {
    let thumbs: [KeyframeThumbnail]
    let totalKeyframes: Int
    @Binding var hoveredKeyframeTime: Double?
    var visibleTimeRange: ClosedRange<Double>? = nil
    var frameRate: Double? = nil
    @State private var hoveredThumb: KeyframeThumbnail? = nil
    @State private var hoveredIndex: Int? = nil
    
    private var filteredThumbs: [KeyframeThumbnail] {
        guard let range = visibleTimeRange else { return thumbs }
        return thumbs.filter { range.contains($0.time) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
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
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .padding(.horizontal, DesignSystem.Padding.md)
                        .padding(.vertical, DesignSystem.Padding.xs)
                        .background(DesignSystem.Colors.Chart.keyframe.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous))
                    } else {
                        if visibleTimeRange != nil {
                            Text("\(filteredThumbs.count) of \(thumbs.count) keyframes")
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
                .frame(height: 24, alignment: .leading)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.top, DesignSystem.Padding.sm)
            strip
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        formatTimeForChart(time, frameRate: frameRate)
    }
    
    private func gopInterval(for index: Int) -> Double? {
        guard index > 0, index < filteredThumbs.count else { return nil }
        return filteredThumbs[index].time - filteredThumbs[index - 1].time
    }
    
    @State private var canScrollLeft = false
    @State private var canScrollRight = false
    
    private var strip: some View {
        ScrollableThumbnailView(
            thumbs: filteredThumbs,
            hoveredIndex: $hoveredIndex,
            hoveredThumb: $hoveredThumb,
            hoveredKeyframeTime: $hoveredKeyframeTime,
            canScrollLeft: $canScrollLeft,
            canScrollRight: $canScrollRight
        )
        .frame(height: 80)
        .clipShape(Rectangle())
        .overlay(alignment: .leading) {
            // Left scroll indicator
            if canScrollLeft {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.6))
                        .padding(.leading, 6)
                    Spacer()
                }
                .frame(width: 24)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            // Right scroll indicator
            if canScrollRight {
                HStack(spacing: 0) {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary.opacity(0.6))
                        .padding(.trailing, 6)
                }
                .frame(width: 24)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Scrollable Thumbnail View

private struct ScrollableThumbnailView: View {
    let thumbs: [KeyframeThumbnail]
    @Binding var hoveredIndex: Int?
    @Binding var hoveredThumb: KeyframeThumbnail?
    @Binding var hoveredKeyframeTime: Double?
    @Binding var canScrollLeft: Bool
    @Binding var canScrollRight: Bool
    @State private var hoverUpdateTask: Task<Void, Never>? = nil
    @State private var isScrolling = false
    
    var body: some View {
        ScrollableThumbnailContainer(
            canScrollLeft: $canScrollLeft,
            canScrollRight: $canScrollRight,
            isScrolling: $isScrolling
        ) {
            LazyHStack(spacing: DesignSystem.Spacing.sm3) {
                ForEach(Array(thumbs.enumerated()), id: \.element.id) { index, thumb in
                    ThumbCell(
                        image: thumb.image,
                        isHovered: !isScrolling && hoveredIndex == index
                    )
                    .onHover { isHovering in
                        // Skip hover updates while scrolling
                        guard !isScrolling else { return }
                        
                        // Cancel any pending update
                        hoverUpdateTask?.cancel()
                        
                        if isHovering {
                            // Throttle hover updates to reduce lag
                            hoverUpdateTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                                if !Task.isCancelled && !isScrolling {
                                    hoveredThumb = thumb
                                    hoveredIndex = index
                                    hoveredKeyframeTime = thumb.time
                                }
                            }
                        } else if hoveredIndex == index {
                            // Immediate clear on unhover
                            hoveredThumb = nil
                            hoveredIndex = nil
                            hoveredKeyframeTime = nil
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.vertical, DesignSystem.Padding.sm)
        }
    }
}

// MARK: - Draggable Scroll View

private struct ScrollableThumbnailContainer<Content: View>: NSViewRepresentable {
    @Binding var canScrollLeft: Bool
    @Binding var canScrollRight: Bool
    @Binding var isScrolling: Bool
    let content: Content
    
    init(canScrollLeft: Binding<Bool>, canScrollRight: Binding<Bool>, isScrolling: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._canScrollLeft = canScrollLeft
        self._canScrollRight = canScrollRight
        self._isScrolling = isScrolling
        self.content = content()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(canScrollLeft: $canScrollLeft, canScrollRight: $canScrollRight)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
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
        context.coordinator.isScrolling = $isScrolling
        
        // Set up scroll tracking
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.updateScrollState),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
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
        
        // Initial update
        DispatchQueue.main.async {
            context.coordinator.updateScrollState()
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
        }
        context.coordinator.updateScrollState()
    }
    
    class Coordinator: NSObject {
        var hostingView: NSHostingView<Content>?
        var scrollView: NSScrollView?
        var lastScrollOrigin: NSPoint = .zero
        var scrollTimer: Timer?
        var isScrolling: Binding<Bool>?
        @Binding var canScrollLeft: Bool
        @Binding var canScrollRight: Bool
        
        init(canScrollLeft: Binding<Bool>, canScrollRight: Binding<Bool>) {
            self._canScrollLeft = canScrollLeft
            self._canScrollRight = canScrollRight
        }
        
        private var lastUpdateTime: Date = Date()
        private let updateInterval: TimeInterval = 0.05 // Throttle to 20fps for scroll updates
        
        @objc func updateScrollState() {
            let now = Date()
            guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
            lastUpdateTime = now
            
            guard let scrollView = scrollView else { return }
            
            let documentWidth = scrollView.documentView?.frame.width ?? 0
            let visibleWidth = scrollView.contentView.bounds.width
            let scrollX = scrollView.contentView.bounds.origin.x
            let maxScrollX = max(0, documentWidth - visibleWidth)
            
            let newCanScrollLeft = scrollX > 0.1
            let newCanScrollRight = scrollX < maxScrollX - 0.1
            
            // Only update if changed to avoid unnecessary redraws
            if canScrollLeft != newCanScrollLeft || canScrollRight != newCanScrollRight {
                DispatchQueue.main.async {
                    self.canScrollLeft = newCanScrollLeft
                    self.canScrollRight = newCanScrollRight
                }
            }
        }
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            
            switch gesture.state {
            case .began:
                lastScrollOrigin = scrollView.contentView.bounds.origin
                DispatchQueue.main.async {
                    self.isScrolling?.wrappedValue = true
                }
                // Cancel any scroll timer
                scrollTimer?.invalidate()
            case .changed:
                let translation = gesture.translation(in: scrollView)
                var newOrigin = lastScrollOrigin
                newOrigin.x -= translation.x
                
                let documentWidth = scrollView.documentView?.frame.width ?? 0
                let visibleWidth = scrollView.contentView.bounds.width
                let maxX = max(0, documentWidth - visibleWidth)
                newOrigin.x = max(0, min(newOrigin.x, maxX))
                
                scrollView.contentView.scroll(to: newOrigin)
                updateScrollState()
                
                // Reset scroll timer
                scrollTimer?.invalidate()
                scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.isScrolling?.wrappedValue = false
                    }
                }
            case .ended, .cancelled:
                scrollTimer?.invalidate()
                scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.isScrolling?.wrappedValue = false
                    }
                }
            default:
                break
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

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
        let shape = RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
        
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 60)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isHovered ? DesignSystem.Colors.Chart.keyframe.opacity(0.8) : Color.clear,
                    lineWidth: isHovered ? 2.5 : 0
                )
            )
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            .contentShape(shape)
    }
}
