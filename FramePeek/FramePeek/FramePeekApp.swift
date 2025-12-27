//
//  FramePeekApp.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-02-15.
//

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
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 850, height: 650)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FramePeek") {
                    appViewModel.showAboutView = true
                }
            }
            
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Settings…") {
                    appViewModel.showSettingsView = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
