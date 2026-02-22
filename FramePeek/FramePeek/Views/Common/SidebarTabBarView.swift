import SwiftUI
import FramePeekCore

// MARK: - Selection Type

enum SidebarSelection: Hashable {
    case tab(UUID)
    case server
}

// MARK: - Sidebar Tab Bar View

struct SidebarTabBarView: View {
    var tabManager: TabManager
    @Binding var showServerTab: Bool
    @State private var serverManager = ServerManager.shared

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding<SidebarSelection?>(
            get: {
                if showServerTab {
                    return .server
                } else if let tabId = tabManager.selectedTabId {
                    return .tab(tabId)
                }
                return nil
            },
            set: { newValue in
                // Defer state changes to avoid "Publishing changes from within view updates" warning
                Task { @MainActor in
                    switch newValue {
                    case .tab(let id):
                        showServerTab = false
                        tabManager.switchToTab(id: id)
                    case .server:
                        showServerTab = true
                    case .none:
                        break
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tabs list - scrollable
            List(selection: sidebarSelection) {
                ForEach(tabManager.tabs) { tab in
                    SidebarTabRow(
                        tab: tab,
                        tabManager: tabManager,
                        onClose: {
                            Task { @MainActor in
                                tabManager.removeTab(id: tab.id)
                            }
                        }
                    )
                    .tag(SidebarSelection.tab(tab.id))
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Server row - pinned at bottom
            ServerSidebarButton(
                isSelected: showServerTab,
                isRunning: serverManager.isRunning,
                activeJobCount: serverManager.jobQueue.activeJobs.count,
                onSelect: {
                    Task { @MainActor in
                        showServerTab = true
                    }
                }
            )
            .padding(.horizontal, DesignSystem.Padding.sm)
            .padding(.vertical, DesignSystem.Padding.sm)
        }
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
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))

                    // Status dot
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: -2)
                }

                Text("Server")

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
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
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

// MARK: - Sidebar Tab Row

struct SidebarTabRow: View {
    let tab: TabItem
    let tabManager: TabManager
    let onClose: () -> Void

    var viewModel: FramePeekViewModel

    init(tab: TabItem, tabManager: TabManager, onClose: @escaping () -> Void) {
        self.tab = tab
        self.tabManager = tabManager
        self.onClose = onClose
        self.viewModel = tab.viewModel
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // File name
            Text(tab.displayName)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: DesignSystem.Spacing.sm)

            // Processing indicator
            if viewModel.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
            }

            // Close button - always visible
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
