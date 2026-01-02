import SwiftUI
import UniformTypeIdentifiers

struct FramePeek: View {
    @EnvironmentObject var appViewModel: FramePeekViewModel
    @StateObject private var tabManager = TabManager()

    @AppStorage("showInspector") private var showInspector: Bool = false
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
        contentWithProcessingObservers
            .onChange(of: currentViewModel?.extendedInfo?.fileName) {
                handleExtendedInfoChange()
            }
            .onChange(of: currentViewModel?.pendingURL) {
                handlePendingURLChange()
            }
            .onChange(of: currentViewModel?.showTabChoiceDialog) {
                handleTabChoiceDialogChange()
            }
            .onChange(of: currentViewModel?.pendingURLForTabChoice) {
                handlePendingURLForTabChoiceChange()
            }
            .onChange(of: currentViewModel?.shouldOpenInNewTab) {
                handleShouldOpenInNewTabChange()
            }
            .onChange(of: currentViewModel?.showSamplingDialog) { newValue in
                // Sync local state with view model state
                showSamplingDialog = newValue ?? false
            }
    }
    
    private var contentWithProcessingObservers: some View {
        mainContent
            .toolbar { toolbarContent }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showInspector)
            .animation(.spring(response: 0.7, dampingFraction: 0.8), value: isProcessing)
            .onChange(of: currentViewModel?.isAnalyzing) {
                updateProcessingState()
            }
            .onChange(of: currentViewModel?.isExtractingKeyframes) {
                updateProcessingState()
            }
            .onChange(of: currentViewModel?.isGeneratingThumbnails) {
                updateProcessingState()
            }
            .onChange(of: tabManager.selectedTabId) {
                updateProcessingState()
            }
            .onAppear {
                updateProcessingState()
            }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Tab bar
            TabBarView(tabManager: tabManager)
            
            // Main content
            if let viewModel = currentViewModel {
                HStack(spacing: 0) {
                    BitrateChartView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop(providers:))

                    if showInspector {
                        InspectorColumn(
                            width: CGFloat(inspectorWidth),
                            onClose: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    showInspector = false
                                }
                            }
                        ) {
                            InfoInspectorView(viewModel: viewModel)
                        }
                        .frame(width: CGFloat(inspectorWidth))
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.96, anchor: .trailing)),
                                removal: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.98, anchor: .trailing))
                            )
                        )
                        .overlay(alignment: .leading) {
                            // Optional: resize handle (feels like pro apps)
                            ResizeHandle(
                                minWidth: inspectorMin,
                                maxWidth: inspectorMax,
                                width: $inspectorWidth
                            )
                            .offset(x: -4) // sits just on top of divider
                        }
                    }
                }
            } else {
                // Empty state when no tabs
                Text("No tabs available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Spacer()
        }
        
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
        
        ToolbarItem(placement: .confirmationAction) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showInspector.toggle()
                }
            } label: {
                Label(showInspector ? "Hide Inspector" : "Show Inspector",
                      systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
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
    
    private func handleExtendedInfoChange() {
        // Auto-show inspector when a video is loaded
        if currentViewModel?.extendedInfo != nil && !showInspector {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showInspector = true
            }
        }
        
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

#Preview {
    FramePeek()
        .environmentObject(FramePeekViewModel())
}
