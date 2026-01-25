import SwiftUI
import AppKit
import FramePeekCore

extension Notification.Name {
    static let menuOpenFile = Notification.Name("menuOpenFile")
    static let menuOpenRecentFile = Notification.Name("menuOpenRecentFile")
}

struct OpenRecentCommands: Commands {
    @ObservedObject private var fileHistory = FileHistoryManager.shared

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("Open Recent") {
                if fileHistory.validFiles.isEmpty {
                    Text("No Recent Files")
                        .disabled(true)
                } else {
                    ForEach(fileHistory.validFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            NotificationCenter.default.post(name: .menuOpenRecentFile, object: url)
                        }
                    }
                }
            }
        }
    }
}

@main
struct FramePeekApp: App {
    @StateObject private var appViewModel = FramePeekViewModel()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    init() {
        // Disable native macOS window tabbing application-wide
        NSWindow.allowsAutomaticWindowTabbing = false
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

            CommandGroup(after: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .menuOpenFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            OpenRecentCommands()

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
