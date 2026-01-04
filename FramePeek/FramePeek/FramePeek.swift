import SwiftUI
import UniformTypeIdentifiers

struct FramePeek: View {
    @EnvironmentObject var appViewModel: FramePeekViewModel
    @StateObject private var tabManager = TabManager()

    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 380

    private let inspectorMin: Double = 280
    private let inspectorMax: Double = 520
    
    @State private var showTabChoiceDialog: Bool = false
    @State private var tabChoiceURL: URL?
    @State private var isProcessing: Bool = false
    @State private var showSamplingDialog: Bool = false
    
    private var currentViewModel: FramePeekViewModel? {
        tabManager.currentViewModel
    }
    
    private var shouldShowSettingsDialog: Bool {
        UserDefaults.standard.object(forKey: "showSettingsOnFileLoad") as? Bool ?? true
    }

    var body: some View {
        contentWithObservers
            .sheet(isPresented: $showSamplingDialog) {
                samplingSheet
            }
            .sheet(isPresented: $showTabChoiceDialog) {
                tabChoiceSheet
            }
            .sheet(isPresented: $appViewModel.showAboutView) {
                AboutView()
            }
            .sheet(isPresented: $appViewModel.showSettingsView) {
                SettingsView()
            }
    }
    
    private var contentWithObservers: some View {
        contentWithDialogObservers
            .background {
                // Hidden view that observes all tabs' viewModels for extendedInfo changes
                ForEach(tabManager.tabs) { tab in
                    TabNameObserver(tab: tab, tabManager: tabManager)
                        .hidden()
                }
            }
    }
    
    private var contentWithFileObservers: some View {
        contentWithProcessingObservers
            .onChange(of: tabManager.tabs) {
                // Update tab names for all tabs when tabs array changes
                DispatchQueue.main.async {
                    updateAllTabNames()
                }
            }
            .onChange(of: currentViewModel?.extendedInfo?.fileName) {
                DispatchQueue.main.async {
                    handleExtendedInfoChange()
                }
            }
            .onChange(of: currentViewModel?.pendingURL) {
                DispatchQueue.main.async {
                    handlePendingURLChange()
                }
            }
    }
    
    private var contentWithDialogObservers: some View {
        contentWithFileObservers
            .onChange(of: currentViewModel?.showTabChoiceDialog) {
                DispatchQueue.main.async {
                    handleTabChoiceDialogChange()
                }
            }
            .onChange(of: currentViewModel?.pendingURLForTabChoice) {
                DispatchQueue.main.async {
                    handlePendingURLForTabChoiceChange()
                }
            }
            .onChange(of: currentViewModel?.shouldOpenInNewTab) {
                DispatchQueue.main.async {
                    handleShouldOpenInNewTabChange()
                }
            }
            .onChange(of: currentViewModel?.showSamplingDialog) {
                DispatchQueue.main.async {
                    // Sync local state with view model state
                    showSamplingDialog = currentViewModel?.showSamplingDialog ?? false
                }
            }
    }
    
    private var contentWithProcessingObservers: some View {
        mainContent
            .toolbar { toolbarContent }
            .animation(.spring(response: 0.7, dampingFraction: 0.8), value: isProcessing)
            .onChange(of: currentViewModel?.isAnalyzing) {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
            .onChange(of: currentViewModel?.isExtractingKeyframes) {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
            .onChange(of: currentViewModel?.isGeneratingThumbnails) {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
            .onChange(of: tabManager.selectedTabId) {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
    }
    
    private var mainContent: some View {
        NavigationSplitView {
            SidebarTabBarView(tabManager: tabManager)
        } detail: {
            // Detail view with main content and inspector
            ZStack(alignment: .trailing) {
                // Main content area - rendered first so it's behind the inspector
                if let viewModel = currentViewModel {
                    BitrateChartView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.trailing, CGFloat(inspectorWidth))
                        .contentShape(Rectangle())
                        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop(providers:))
                        .id(tabManager.selectedTabId) // Force view recreation on tab switch to isolate state
                } else {
                    // Empty state when no tabs
                    Text("No tabs available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Inspector - rendered last so it appears on top (always visible)
                if let viewModel = currentViewModel {
                    InspectorColumn(
                        width: CGFloat(inspectorWidth)
                    ) {
                        InfoInspectorView(viewModel: viewModel)
                    }
                    .frame(maxHeight: .infinity, alignment: .trailing)
                    .overlay(alignment: .leading) {
                        // Optional: resize handle (feels like pro apps)
                        ResizeHandle(
                            minWidth: inspectorMin,
                            maxWidth: inspectorMax,
                            width: $inspectorWidth
                        )
                        .offset(x: -4) // sits just on top of divider
                    }
                    .id(tabManager.selectedTabId) // Force view recreation on tab switch to isolate state
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 200, ideal: 200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button {
                currentViewModel?.pickFile()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button {
                tabManager.addTab()
            } label: {
                Label("New Tab", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("t", modifiers: [.command])
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var samplingSheet: some View {
        if let viewModel = currentViewModel {
            SamplingSheet(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 300)
        }
    }
    
    @ViewBuilder
    private var tabChoiceSheet: some View {
        let url = tabChoiceURL ?? currentViewModel?.pendingURLForTabChoice
        
        if let url = url {
            TabChoiceDialog(
                fileName: url.lastPathComponent,
                onChooseCurrentTab: {
                    handleChooseCurrentTab(url: url)
                },
                onChooseNewTab: {
                    handleChooseNewTab(url: url)
                },
                onCancel: {
                    handleCancelTabChoice()
                }
            )
        }
    }
    
    private func updateAllTabNames() {
        // Update display names for all tabs based on their viewModels
        for tab in tabManager.tabs {
            if let fileName = tab.viewModel.extendedInfo?.fileName {
                tabManager.updateTabDisplayName(id: tab.id, name: fileName)
            } else if let pendingURL = tab.viewModel.pendingURL {
                tabManager.updateTabDisplayName(id: tab.id, name: pendingURL.lastPathComponent)
            }
        }
    }
    
    private func handleExtendedInfoChange() {
        // Update tab display name when file loads (this ensures it's correct even if it changed)
        if let fileName = currentViewModel?.extendedInfo?.fileName,
           let currentTabId = tabManager.selectedTabId {
            tabManager.updateTabDisplayName(id: currentTabId, name: fileName)
        }
    }
    
    private func handlePendingURLChange() {
        // Update tab name immediately when a file URL is set (before it loads)
        if let url = currentViewModel?.pendingURL,
           let currentTabId = tabManager.selectedTabId {
            tabManager.updateTabDisplayName(id: currentTabId, name: url.lastPathComponent)
        }
    }
    
    private func handleTabChoiceDialogChange() {
        // Sync local state with viewModel state for immediate reactivity
        let shouldShow = currentViewModel?.showTabChoiceDialog ?? false
        showTabChoiceDialog = shouldShow
        
        // Always sync the URL when dialog state changes
        if shouldShow, let url = currentViewModel?.pendingURLForTabChoice {
            tabChoiceURL = url
        } else if !shouldShow {
            // Clear URL when dialog is dismissed
            tabChoiceURL = nil
        }
    }
    
    private func handlePendingURLForTabChoiceChange() {
        // Update URL when it changes (in case it's set before showTabChoiceDialog)
        if let url = currentViewModel?.pendingURLForTabChoice {
            tabChoiceURL = url
        }
    }
    
    private func handleShouldOpenInNewTabChange() {
        // Handle automatic new tab creation when setting is "newTab"
        guard let url = currentViewModel?.shouldOpenInNewTab else { return }
        
        // Clear the signal first to prevent re-triggering
        currentViewModel?.shouldOpenInNewTab = nil
        
        // Create new tab and load file there
        tabManager.addTab()
        if let newViewModel = tabManager.currentViewModel,
           let newTabId = tabManager.selectedTabId {
            // Update tab name immediately
            tabManager.updateTabDisplayName(id: newTabId, name: url.lastPathComponent)
            newViewModel.pendingURL = url
            if shouldShowSettingsDialog {
                newViewModel.showSamplingDialog = true
            } else {
                newViewModel.confirmSamplingAndLoad()
            }
        }
    }
    
    private func handleChooseCurrentTab(url: URL) {
        // Update tab name immediately
        if let currentTabId = tabManager.selectedTabId {
            tabManager.updateTabDisplayName(id: currentTabId, name: url.lastPathComponent)
        }
        if let viewModel = currentViewModel {
            viewModel.handleTabChoice(action: .currentTab)
        }
        showTabChoiceDialog = false
        tabChoiceURL = nil
    }
    
    private func handleChooseNewTab(url: URL) {
        if let viewModel = currentViewModel {
            viewModel.cancelTabChoice()
        }
        // Create new tab and load file there
        tabManager.addTab()
        if let newViewModel = tabManager.currentViewModel,
           let newTabId = tabManager.selectedTabId {
            // Update tab name immediately
            tabManager.updateTabDisplayName(id: newTabId, name: url.lastPathComponent)
            newViewModel.pendingURL = url
            if shouldShowSettingsDialog {
                newViewModel.showSamplingDialog = true
            } else {
                newViewModel.confirmSamplingAndLoad()
            }
        }
        showTabChoiceDialog = false
        tabChoiceURL = nil
    }
    
    private func handleCancelTabChoice() {
        if let viewModel = currentViewModel {
            viewModel.cancelTabChoice()
        }
        showTabChoiceDialog = false
        tabChoiceURL = nil
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              let viewModel = currentViewModel else { return false }
        
        // Process immediately on main thread for responsiveness
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            
            // All UI updates must happen on MainActor
            Task { @MainActor in
                // Update tab name immediately for feedback
                if let currentTabId = tabManager.selectedTabId {
                    tabManager.updateTabDisplayName(id: currentTabId, name: url.lastPathComponent)
                }
                
                // Handle file - this will set showTabChoiceDialog if needed
                viewModel.handleIncomingFile(url: url)
                
                // Immediately sync the URL to local state if dialog is shown
                if viewModel.showTabChoiceDialog, let pendingURL = viewModel.pendingURLForTabChoice {
                    tabChoiceURL = pendingURL
                    showTabChoiceDialog = true
                }
            }
        }
        return true
    }
    
    private func updateProcessingState() {
        guard let viewModel = currentViewModel else {
            isProcessing = false
            return
        }
        isProcessing = viewModel.isAnalyzing || viewModel.isExtractingKeyframes || viewModel.isGeneratingThumbnails
    }
}

// Helper view to observe extendedInfo changes for each tab
private struct TabNameObserver: View {
    let tab: TabItem
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var viewModel: FramePeekViewModel
    
    init(tab: TabItem, tabManager: TabManager) {
        self.tab = tab
        self.tabManager = tabManager
        self._viewModel = ObservedObject(wrappedValue: tab.viewModel)
    }
    
    var body: some View {
        Color.clear
            .onChange(of: viewModel.extendedInfo?.fileName) {
                if let fileName = viewModel.extendedInfo?.fileName {
                    tabManager.updateTabDisplayName(id: tab.id, name: fileName)
                }
            }
            .onChange(of: viewModel.pendingURL) {
                if let url = viewModel.pendingURL {
                    tabManager.updateTabDisplayName(id: tab.id, name: url.lastPathComponent)
                }
            }
    }
}

#Preview {
    FramePeek()
        .environmentObject(FramePeekViewModel())
}
