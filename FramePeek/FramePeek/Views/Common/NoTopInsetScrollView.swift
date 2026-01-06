import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct NoTopInsetScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        
        // Remove top content inset
        scrollView.contentView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.documentView = hostingView

        // Add width constraint to match scroll view's content view width
        // This ensures the SwiftUI content knows its available width for proper text wrapping
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        
        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
        }
        
        // Ensure content insets remain zero
        nsView.contentView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        nsView.contentView.automaticallyAdjustsContentInsets = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var hostingView: NSHostingView<Content>?
        var scrollView: NSScrollView?
    }
}

