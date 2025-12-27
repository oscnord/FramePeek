//
//  TabBarView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

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
        
        // Remove tabs that no longer exist
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
        
        // Add or update tabs
        for (index, tab) in manager.tabs.enumerated() {
            let existingItem = tabView.tabViewItems.first { $0.identifier as? UUID == tab.id }
            
            if let item = existingItem {
                // Update existing tab
                item.label = tab.displayName
            } else {
                // Create new tab
                let item = NSTabViewItem(identifier: tab.id)
                item.label = tab.displayName
                item.view = NSView() // Empty view - content is handled by SwiftUI
                
                // Add close button
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
                
                // Store tab ID in coordinator's dictionary
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
        
        // Update close button visibility
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
                            isProcessing: tab.viewModel.isAnalyzing || tab.viewModel.isExtractingKeyframes || tab.viewModel.isGeneratingThumbnails,
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
            
            // Add new tab button
            Button {
                tabManager.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "New Tab"))
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct NativeStyleTabButton: View {
    let tab: TabItem
    let isSelected: Bool
    var isProcessing: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var breathingOpacity: Double = 1.0
    
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
                        // Selected tab - pill shape with native button appearance
                        Capsule()
                            .fill(Color(NSColor.controlAccentColor).opacity(0.15))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color(NSColor.controlAccentColor).opacity(0.3),
                                        lineWidth: 0.5
                                    )
                            )
                    } else if isHovered {
                        // Hovered tab - subtle pill shape
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color(NSColor.separatorColor).opacity(0.5),
                                        lineWidth: 0.5
                                    )
                            )
                    } else {
                        // Unselected tab - very subtle background
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
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
            .opacity(isProcessing ? breathingOpacity : 1.0)
            .overlay(
                // Subtle breathing glow effect when processing
                Group {
                    if isProcessing {
                        Capsule()
                            .strokeBorder(
                                Color(NSColor.controlAccentColor).opacity(0.2 + (1.0 - breathingOpacity) * 0.3),
                                lineWidth: 1.5
                            )
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
        .onChange(of: isProcessing) { processing in
            if processing {
                // Start breathing animation - subtle pulse between 0.85 and 1.0
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    breathingOpacity = 0.85
                }
            } else {
                // Stop breathing animation
                withAnimation(.easeInOut(duration: 0.3)) {
                    breathingOpacity = 1.0
                }
            }
        }
        .onAppear {
            if isProcessing {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    breathingOpacity = 0.85
                }
            }
        }
    }
}

#Preview {
    TabBarView(tabManager: TabManager())
        .frame(width: 800)
}

