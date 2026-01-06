import SwiftUI
import UniformTypeIdentifiers

struct FramePeek: View {
    @EnvironmentObject var appViewModel: FramePeekViewModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var tabManager = TabManager()

    private let inspectorMin: Double = 280
    private let inspectorMax: Double = 520
    
    @State private var showTabChoiceDialog: Bool = false
    @State private var tabChoiceURL: URL?
    @State private var isProcessing: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isInspectorVisible: Bool = true
    
    private var currentViewModel: FramePeekViewModel? {
        tabManager.currentViewModel
    }
    

    var body: some View {
        contentWithObservers
            .sheet(isPresented: $showTabChoiceDialog) {
                tabChoiceSheet
            }
            .sheet(isPresented: $appViewModel.showAboutView) {
                AboutView()
            }
            .onChange(of: appViewModel.showSettingsView) { oldValue, newValue in
                if newValue {
                    openWindow(id: "settings")
                    // Reload settings for all tabs when settings window opens
                    for tab in tabManager.tabs {
                        tab.viewModel.loadSettingsFromUserDefaults()
                    }
                    // Reset the flag so it can be triggered again
                    appViewModel.showSettingsView = false
                }
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
            .onChange(of: currentViewModel?.isGeneratingThumbnails) {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
            .onChange(of: tabManager.selectedTabId) {
                DispatchQueue.main.async {
                    updateProcessingState()
                    // Update player window if it's open
                    if let currentViewModel = currentViewModel {
                        PlayerViewModelManager.shared.setActiveViewModel(currentViewModel)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    updateProcessingState()
                }
            }
    }
    
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarTabBarView(tabManager: tabManager)
                .toolbar { newTabToolbarContent }
                .navigationSplitViewColumnWidth(min: 200, ideal: 200)
        } detail: {
            // Main content area
            Group {
                if let viewModel = currentViewModel {
                    BitrateChartView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop(providers:))
                        .id(tabManager.selectedTabId) // Force view recreation on tab switch to isolate state
                } else {
                    // Empty state when no tabs
                    Text("No tabs available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .inspector(isPresented: $isInspectorVisible) {
                if let viewModel = currentViewModel {
                    InfoInspectorView(viewModel: viewModel)
                        .id(tabManager.selectedTabId) // Force view recreation on tab switch to isolate state
                } else {
                    EmptyInspectorState()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .confirmationAction) {
            Button {
                appViewModel.showSettingsView = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: [.command])
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button {
                // Check for untitled tab first, then open file picker
                if let untitledTab = tabManager.findUntitledTab() {
                    tabManager.switchToTab(id: untitledTab.id)
                }
                currentViewModel?.pickFile()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Spacer()
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button {
                withAnimation {
                    isInspectorVisible.toggle()
                }
            } label: {
                Label(isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                      systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command])
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var newTabToolbarContent: some ToolbarContent {
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
        
        // First check if there's an untitled tab we can use
        if let untitledTab = tabManager.findUntitledTab() {
            // Switch to the untitled tab and load the file there
            tabManager.switchToTab(id: untitledTab.id)
            if let viewModel = tabManager.currentViewModel {
                tabManager.updateTabDisplayName(id: untitledTab.id, name: url.lastPathComponent)
                viewModel.pendingURL = url
                viewModel.confirmSamplingAndLoad()
            }
        } else {
            // No untitled tab, create new tab and load file there
            tabManager.addTab()
            if let newViewModel = tabManager.currentViewModel,
               let newTabId = tabManager.selectedTabId {
                // Update tab name immediately
                tabManager.updateTabDisplayName(id: newTabId, name: url.lastPathComponent)
                newViewModel.pendingURL = url
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
        
        // First check if there's an untitled tab we can use
        if let untitledTab = tabManager.findUntitledTab() {
            // Switch to the untitled tab and load the file there
            tabManager.switchToTab(id: untitledTab.id)
            if let viewModel = tabManager.currentViewModel {
                tabManager.updateTabDisplayName(id: untitledTab.id, name: url.lastPathComponent)
                viewModel.pendingURL = url
                viewModel.confirmSamplingAndLoad()
            }
        } else {
            // No untitled tab, create new tab and load file there
            tabManager.addTab()
            if let newViewModel = tabManager.currentViewModel,
               let newTabId = tabManager.selectedTabId {
                // Update tab name immediately
                tabManager.updateTabDisplayName(id: newTabId, name: url.lastPathComponent)
                newViewModel.pendingURL = url
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
        guard let provider = providers.first else { return false }
        
        // Process immediately on main thread for responsiveness
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            
            // All UI updates must happen on MainActor
            Task { @MainActor in
                openFileInAppropriateTab(url: url)
            }
        }
        return true
    }
    
    /// Opens a file in the appropriate tab - checks for untitled tabs first
    private func openFileInAppropriateTab(url: URL) {
        // First, check if there's an untitled tab we can use
        if let untitledTab = tabManager.findUntitledTab() {
            // Switch to the untitled tab and load the file there
            tabManager.switchToTab(id: untitledTab.id)
            if let viewModel = tabManager.currentViewModel {
                tabManager.updateTabDisplayName(id: untitledTab.id, name: url.lastPathComponent)
                viewModel.handleIncomingFile(url: url)
                
                // Immediately sync the URL to local state if dialog is shown
                if viewModel.showTabChoiceDialog, let pendingURL = viewModel.pendingURLForTabChoice {
                    tabChoiceURL = pendingURL
                    showTabChoiceDialog = true
                }
            }
        } else if let viewModel = currentViewModel {
            // No untitled tab, use current tab
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
    
    private func updateProcessingState() {
        guard let viewModel = currentViewModel else {
            isProcessing = false
            return
        }
        isProcessing = viewModel.isAnalyzing || viewModel.isGeneratingThumbnails
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

