import SwiftUI

@main
struct FramePeekApp: App {
    @StateObject private var appViewModel = FramePeekViewModel()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
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
                Button("Settings") {
                    appViewModel.showSettingsView = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
        
        WindowGroup(id: "settings") {
            SettingsView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .animation(.easeInOut(duration: 0.3), value: appearanceMode)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 700, height: 600)
    }
}

