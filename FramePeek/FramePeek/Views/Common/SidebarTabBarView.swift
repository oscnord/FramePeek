import SwiftUI

struct SidebarTabBarView: View {
    @ObservedObject var tabManager: TabManager
    
    @AppStorage("sidebarTabBarWidth") private var sidebarWidth: Double = 200
    @State private var isNewTabButtonHovered: Bool = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Tabs list using native List with sidebar style
            List(selection: Binding<UUID?>(
                get: { tabManager.selectedTabId },
                set: { newValue in
                    if let newValue = newValue {
                        DispatchQueue.main.async {
                            tabManager.switchToTab(id: newValue)
                        }
                    }
                }
            )) {
                ForEach(tabManager.tabs) { tab in
                    SidebarTabButton(
                        tab: tab,
                        isSelected: tab.id == tabManager.selectedTabId,
                        onSelect: {
                            DispatchQueue.main.async {
                                tabManager.switchToTab(id: tab.id)
                            }
                        },
                        onClose: {
                            DispatchQueue.main.async {
                                tabManager.removeTab(id: tab.id)
                            }
                        }
                    )
                    .tag(tab.id as UUID?)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .listRowInsets(EdgeInsets(
                top: 4,
                leading: DesignSystem.Padding.md,
                bottom: 4,
                trailing: DesignSystem.Padding.md
            ))
        }
        .padding(.bottom, DesignSystem.Padding.md)
        .frame(maxHeight: .infinity)
    }
}

struct SidebarTabButton: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @ObservedObject private var viewModel: FramePeekViewModel
    @State private var isHovered: Bool = false
    
    init(tab: TabItem, isSelected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.tab = tab
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
        self._viewModel = ObservedObject(wrappedValue: tab.viewModel)
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // File name
            Text(tab.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12))

            
            Spacer(minLength: DesignSystem.Spacing.sm)
            
            // Processing indicator - only show for main analysis, not background keyframe/thumbnail generation
            // This ensures the spinner disappears when the main file loading is complete
            if viewModel.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                    .layoutPriority(-1)
            }
            
            // Close button - always reserve space to prevent layout shifts
            Group {
                if isHovered || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    // Invisible spacer to maintain consistent layout
                    Color.clear
                        .frame(width: 16, height: 16)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    SidebarTabBarView(tabManager: TabManager())
        .frame(height: 600)
}

