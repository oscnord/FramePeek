import SwiftUI
import FramePeekCore

struct SidebarTabBarView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var showServerTab: Bool

    @AppStorage("sidebarTabBarWidth") private var sidebarWidth: Double = 200
    @State private var isNewTabButtonHovered: Bool = false
    @StateObject private var serverManager = ServerManager.shared

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Tabs list using ScrollView with custom selection styling
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(tabManager.tabs) { tab in
                        SidebarTabButton(
                            tab: tab,
                            tabManager: tabManager,
                            isSelected: !showServerTab && tab.id == tabManager.selectedTabId,
                            onSelect: {
                                Task { @MainActor in
                                    withAnimation(.none) {
                                        showServerTab = false
                                        tabManager.switchToTab(id: tab.id)
                                    }
                                }
                            },
                            onClose: {
                                Task { @MainActor in
                                    tabManager.removeTab(id: tab.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.md)
            }
            
            Divider()
                .padding(.horizontal, DesignSystem.Padding.md)
            
            // Server tab button
            ServerSidebarButton(
                isSelected: showServerTab,
                isRunning: serverManager.isRunning,
                activeJobCount: serverManager.jobQueue.activeJobs.count,
                onSelect: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showServerTab = true
                    }
                }
            )
            .padding(.horizontal, DesignSystem.Padding.md)
        }
        .padding(.bottom, DesignSystem.Padding.md)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Server Sidebar Button

struct ServerSidebarButton: View {
    let isSelected: Bool
    let isRunning: Bool
    let activeJobCount: Int
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Server icon with status indicator
                ZStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                    
                    // Status dot
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .offset(x: 8, y: -6)
                }
                
                Text("Server")
                    .font(.system(size: 12))
                
                Spacer()
                
                // Active job count badge
                if activeJobCount > 0 {
                    Text("\(activeJobCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct SidebarTabButton: View {
    let tab: TabItem
    let tabManager: TabManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @ObservedObject private var viewModel: FramePeekViewModel
    @State private var isHovered: Bool = false

    init(tab: TabItem, tabManager: TabManager, isSelected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.tab = tab
        self.tabManager = tabManager
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
        self._viewModel = ObservedObject(wrappedValue: tab.viewModel)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // File name
                Text(tab.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer(minLength: DesignSystem.Spacing.sm)

                // Processing indicator - only show for main analysis, not background keyframe/thumbnail generation
                // This ensures the spinner disappears when the main file loading is complete
                if viewModel.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .layoutPriority(-1)
                }

                // Close button
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
            .padding(.vertical, DesignSystem.Padding.sm2)
            .padding(.horizontal, DesignSystem.Padding.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isSelected ? Color.primary.opacity(0.15) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onClose) {
                Label("Close", systemImage: "xmark")
            }

            Divider()

            if tabManager.tabs.count > 1 {
                Button(
                    role: .destructive,
                    action: {
                        Task { @MainActor in
                            tabManager.closeOtherTabs(keeping: tab.id)
                        }
                    },
                    label: {
                        Label("Close Other Tabs", systemImage: "xmark.circle")
                    }
                )

                // Only show "Close Tabs to the Right" if there are tabs after this one
                if let currentIndex = tabManager.getTabIndex(id: tab.id),
                   currentIndex < tabManager.tabs.count - 1 {
                    Button(
                        role: .destructive,
                        action: {
                            Task { @MainActor in
                                tabManager.closeTabsToTheRight(of: tab.id)
                            }
                        },
                        label: {
                            Label("Close Tabs to the Right", systemImage: "arrow.right.circle")
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    SidebarTabBarView(tabManager: TabManager(), showServerTab: .constant(false))
        .frame(height: 600)
}
