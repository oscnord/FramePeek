import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    
    // Choose between native NSTabView or enhanced custom style
    // Set to true to use native NSTabView (more native appearance, but less flexible)
    // Set to false to use enhanced custom style (more flexible, close buttons work better)
    private let useNativeNSTabView = false
    
    var body: some View {
        if useNativeNSTabView {
            NativeTabBarView(tabManager: tabManager)
                .frame(height: 28)
        } else {
            EnhancedTabBarView(tabManager: tabManager)
        }
    }
}

// MARK: - Native macOS Tab View using NSTabView

struct NativeTabBarView: NSViewRepresentable {
    @ObservedObject var tabManager: TabManager
    
    func makeNSView(context: Context) -> NSTabView {
        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.tabViewBorderType = .none
        tabView.controlSize = .regular
        tabView.delegate = context.coordinator
        
        context.coordinator.tabView = tabView
        context.coordinator.tabManager = tabManager
        
        // Initial setup
        self.updateTabs(tabView: tabView, coordinator: context.coordinator)
        
        // Observe tab manager changes
        let coordinator = context.coordinator
        tabManager.objectWillChange.sink { [weak tabManager, weak tabView] _ in
            DispatchQueue.main.async {
                if let tabManager = tabManager,
                   let tabView = tabView {
                    self.updateTabs(tabView: tabView, coordinator: coordinator, tabManager: tabManager)
                }
            }
        }.store(in: &context.coordinator.cancellables)
        
        return tabView
    }
    
    func updateNSView(_ nsView: NSTabView, context: Context) {
        context.coordinator.tabManager = tabManager
        self.updateTabs(tabView: nsView, coordinator: context.coordinator)
    }
    
    private func updateTabs(tabView: NSTabView, coordinator: Coordinator, tabManager: TabManager? = nil) {
        guard let manager = tabManager ?? coordinator.tabManager else { return }
        
        let currentTabIds = Set(manager.tabs.map { $0.id })
        let tabsToRemove = tabView.tabViewItems.filter { item in
            guard let tabId = item.identifier as? UUID else { return true }
            return !currentTabIds.contains(tabId)
        }
        for item in tabsToRemove {
            // Clean up button mappings
            if let view = item.view {
                for subview in view.subviews {
                    if let button = subview as? NSButton,
                       let identifier = button.identifier {
                        coordinator.tabIdForButton.removeValue(forKey: identifier)
                    }
                }
            }
            tabView.removeTabViewItem(item)
        }
        
        for (index, tab) in manager.tabs.enumerated() {
            let existingItem = tabView.tabViewItems.first { $0.identifier as? UUID == tab.id }
            
            if let item = existingItem {
                item.label = tab.displayName
            } else {
                let item = NSTabViewItem(identifier: tab.id)
                item.label = tab.displayName
                item.view = NSView()
                
                let closeButton = NSButton()
                closeButton.title = ""
                if let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) {
                    closeButton.image = closeImage
                }
                closeButton.imagePosition = .imageOnly
                closeButton.bezelStyle = .texturedRounded
                closeButton.isBordered = false
                closeButton.controlSize = .mini
                closeButton.target = coordinator
                closeButton.action = #selector(Coordinator.closeTab(_:))
                let buttonIdentifier = NSUserInterfaceItemIdentifier("close-\(tab.id.uuidString)")
                closeButton.identifier = buttonIdentifier
                
                coordinator.tabIdForButton[buttonIdentifier] = tab.id
                
                // Position close button in tab
                item.view?.addSubview(closeButton)
                closeButton.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    closeButton.trailingAnchor.constraint(equalTo: item.view!.trailingAnchor, constant: -8),
                    closeButton.centerYAnchor.constraint(equalTo: item.view!.centerYAnchor),
                    closeButton.widthAnchor.constraint(equalToConstant: 16),
                    closeButton.heightAnchor.constraint(equalToConstant: 16)
                ])
                
                tabView.insertTabViewItem(item, at: index)
            }
        }
        
        // Select the current tab
        if let selectedId = manager.selectedTabId,
           let selectedItem = tabView.tabViewItems.first(where: { $0.identifier as? UUID == selectedId }),
           tabView.selectedTabViewItem != selectedItem {
            coordinator.isUpdatingProgrammatically = true
            tabView.selectTabViewItem(selectedItem)
            coordinator.isUpdatingProgrammatically = false
        }
        
        updateCloseButtons(tabView: tabView, selectedId: manager.selectedTabId)
    }
    
    private func updateCloseButtons(tabView: NSTabView, selectedId: UUID?) {
        for item in tabView.tabViewItems {
            let isSelected = (item.identifier as? UUID) == selectedId
            if let view = item.view {
                for subview in view.subviews {
                    if let button = subview as? NSButton,
                       let identifier = button.identifier?.rawValue,
                       identifier.hasPrefix("close-") {
                        // Show close button on selected tab or all tabs (adjust as needed)
                        button.isHidden = !isSelected
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSTabViewDelegate {
        weak var tabView: NSTabView?
        var tabManager: TabManager!
        var cancellables = Set<AnyCancellable>()
        var isUpdatingProgrammatically = false
        var tabIdForButton: [NSUserInterfaceItemIdentifier: UUID] = [:]
        
        @objc func closeTab(_ sender: NSButton) {
            guard let identifier = sender.identifier,
                  let tabId = tabIdForButton[identifier] else { return }
            Task { @MainActor in
                tabManager.removeTab(id: tabId)
            }
        }
        
        func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            // Ignore delegate callbacks when we're programmatically updating
            guard !isUpdatingProgrammatically else { return }
            guard let tabId = tabViewItem?.identifier as? UUID else { return }
            Task { @MainActor in
                tabManager.switchToTab(id: tabId)
            }
        }
    }
}


// MARK: - Alternative: Enhanced Custom Tab View (Native-style appearance)

struct EnhancedTabBarView: View {
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabManager.tabs) { tab in
                        NativeStyleTabButton(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTabId,
                            onSelect: {
                                tabManager.switchToTab(id: tab.id)
                            },
                            onClose: {
                                tabManager.removeTab(id: tab.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Apple Intelligence Style Glow Effect

private struct IntelligenceGlowView<S: InsettableShape>: View {
    let shape: S
    let isProcessing: Bool
    @State private var trimOffset: Double = 0
    @State private var animationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let lineWidths: [CGFloat] = [1.5, 3, 4.5]
    private let blurs: [CGFloat] = [0, 3, 6]
    private let animationDuration: TimeInterval = 6.0
    private let segmentLength: Double = 0.15 // Smaller segment for pill shape
    private let updateInterval: TimeInterval = 0.016 // ~60fps
    
    var body: some View {
        let accentColor = Color(NSColor.controlAccentColor)
        let gradient = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: accentColor.opacity(0.0), location: 0.0),
                .init(color: accentColor.opacity(0.3), location: 0.3),
                .init(color: accentColor.opacity(0.5), location: 0.5),
                .init(color: accentColor.opacity(0.3), location: 0.7),
                .init(color: accentColor.opacity(0.0), location: 1.0)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        
        ZStack {
            // Base subtle border
            shape
                .strokeBorder(accentColor.opacity(0.1), lineWidth: 1.5)
            
            // Animated glow segment that travels around
            ForEach(0..<lineWidths.count, id: \.self) { i in
                // Use modulo that always returns positive value in [0, 1)
                let mod1 = { (value: Double) -> Double in
                    let result = value.truncatingRemainder(dividingBy: 1.0)
                    return result < 0 ? result + 1.0 : result
                }
                let from = mod1(trimOffset)
                let to = mod1(trimOffset + segmentLength)
                
                Group {
                    if from < to {
                        // Normal case: segment doesn't wrap around
                        shape
                            .trim(from: from, to: to)
                            .stroke(
                                gradient,
                                style: StrokeStyle(lineWidth: lineWidths[i], lineCap: .round)
                            )
                            .blur(radius: blurs[i])
                    } else {
                        // Wrap-around case: split into two segments
                        ZStack {
                            // First segment: from to 1.0
                            shape
                                .trim(from: from, to: 1.0)
                                .stroke(
                                    gradient,
                                    style: StrokeStyle(lineWidth: lineWidths[i], lineCap: .round)
                                )
                                .blur(radius: blurs[i])
                            // Second segment: 0.0 to to
                            shape
                                .trim(from: 0.0, to: to)
                                .stroke(
                                    gradient,
                                    style: StrokeStyle(lineWidth: lineWidths[i], lineCap: .round)
                                )
                                .blur(radius: blurs[i])
                        }
                    }
                }
            }
        }
        .animation(.linear(duration: updateInterval), value: trimOffset)
        .onChange(of: isProcessing) { oldValue, newValue in
            // Cancel any existing animation
            animationTask?.cancel()
            animationTask = nil
            
                    if newValue && !reduceMotion {
                // Start continuous animation that increments continuously
                animationTask = Task { @MainActor in
                    let startTime = Date()
                    while !Task.isCancelled && isProcessing {
                        let elapsed = Date().timeIntervalSince(startTime)
                        // Continuously increment trimOffset, wrapping around at 1.0
                        let value = (elapsed / animationDuration).truncatingRemainder(dividingBy: 1.0)
                        trimOffset = value < 0 ? value + 1.0 : value
                        try? await Task.sleep(for: .seconds(updateInterval))
                    }
                }
            } else {
                // Stop animation and reset immediately (no animation to prevent lingering glow)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    trimOffset = 0
                }
            }
        }
        .onAppear {
            if isProcessing && !reduceMotion {
                animationTask = Task { @MainActor in
                    let startTime = Date()
                    while !Task.isCancelled && isProcessing {
                        let elapsed = Date().timeIntervalSince(startTime)
                        // Continuously increment trimOffset, wrapping around at 1.0
                        let value = (elapsed / animationDuration).truncatingRemainder(dividingBy: 1.0)
                        trimOffset = value < 0 ? value + 1.0 : value
                        try? await Task.sleep(for: .seconds(updateInterval))
                    }
                }
            }
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                trimOffset = 0
            }
        }
    }
}

struct NativeStyleTabButton: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @ObservedObject private var viewModel: FramePeekViewModel
    @State private var isHovered: Bool = false
    @State private var gradientStops: [Gradient.Stop] = []
    
    private var isProcessing: Bool {
        viewModel.isAnalyzing || viewModel.isExtractingKeyframes || viewModel.isGeneratingThumbnails
    }
    
    init(tab: TabItem, isSelected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.tab = tab
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
        self._viewModel = ObservedObject(wrappedValue: tab.viewModel)
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(tab.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? 
                            Color(NSColor.controlTextColor) : 
                            Color(NSColor.secondaryLabelColor)
                    )
                
                // Close button - native macOS style
                if isHovered || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(
                                isSelected ? 
                                    Color(NSColor.secondaryLabelColor) : 
                                    Color(NSColor.tertiaryLabelColor)
                            )
                            .frame(width: 12, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minWidth: 80, maxWidth: 200)
            .background(
                Group {
                    if isSelected {
                        // Selected tab - pill shape with liquid glass and tinted accent color
                        Capsule()
                            .fill(Color(NSColor.controlAccentColor).opacity(0.15))
                            .liquidGlassBackground(in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color(NSColor.controlAccentColor).opacity(0.3),
                                        lineWidth: 0.5
                                    )
                            )
                    } else if isHovered {
                        // Hovered tab - liquid glass with subtle tint
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .liquidGlassBackground(in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color(NSColor.separatorColor).opacity(0.5),
                                        lineWidth: 0.5
                                    )
                            )
                    } else {
                        // Unselected tab - liquid glass with very subtle tint
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .liquidGlassBackground(in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color(NSColor.separatorColor).opacity(0.7),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                }
            )
            .overlay(
                // Apple Intelligence-style glow effect when processing
                IntelligenceGlowView(shape: Capsule(), isProcessing: isProcessing)
                    .opacity(isProcessing ? 1.0 : 0.0)
                    .allowsHitTesting(false)
            )
            .background(
                // Subtle background glow when processing
                Group {
                    if isProcessing {
                        Capsule()
                            .fill(Color(NSColor.controlAccentColor).opacity(0.05))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    TabBarView(tabManager: TabManager())
        .frame(width: 800)
}

