import SwiftUI
import AppKit
import FramePeekCore

extension Notification.Name {
    static let menuOpenFile = Notification.Name("menuOpenFile")
    static let menuOpenRecentFile = Notification.Name("menuOpenRecentFile")
    static let menuShowWelcome = Notification.Name("menuShowWelcome")
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
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentSize)
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
            
            CommandGroup(replacing: .help) {
                Button("Welcome to FramePeek") {
                    NotificationCenter.default.post(name: .menuShowWelcome, object: nil)
                }
            }
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
