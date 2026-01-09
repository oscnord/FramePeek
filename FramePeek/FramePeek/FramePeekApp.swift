import SwiftUI
import AppKit

@main
struct FramePeekApp: App {
    @StateObject private var appViewModel = FramePeekViewModel()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    init() {
        // Disable native macOS window tabbing application-wide
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Initialize purchase manager and file count tracker
        _ = PurchaseManager.shared
        _ = FileCountTracker.shared
    }
    
    var body: some Scene {
        WindowGroup {
            FramePeek()
                .environmentObject(appViewModel)
                .preferredColorScheme(appearanceMode.colorScheme)
                .animation(.easeInOut(duration: 0.3), value: appearanceMode)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 850, height: 650)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FramePeek") {
                    appViewModel.showAboutView = true
                }
            }
            
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Settings...") {
                    appViewModel.showSettingsView = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            
            InspectorCommands()
            SidebarCommands()
        }
        
        WindowGroup(id: "settings") {
            SettingsView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .animation(.easeInOut(duration: 0.3), value: appearanceMode)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 700, height: 600)
        
        WindowGroup(id: "videoPlayer") {
            VideoPlayerView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .animation(.easeInOut(duration: 0.3), value: appearanceMode)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
    }
}

