import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// A ProgressView wrapper that avoids constraint conflicts on macOS
/// Uses NSViewRepresentable to bypass SwiftUI's constraint system issues
struct SafeProgressView: NSViewRepresentable {
    var controlSize: ControlSize = .small
    
    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.controlSize = nsControlSize
        indicator.startAnimation(nil)
        return indicator
    }
    
    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        // No updates needed
    }
    
    private var nsControlSize: NSControl.ControlSize {
        switch controlSize {
        case .mini:
            return .mini
        case .small:
            return .small
        case .regular:
            return .regular
        case .large:
            return .large
        @unknown default:
            return .small
        }
    }
}

