//
//  MediaInspectorApp.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import SwiftUI

@main
struct MediaInspectorApp: App {
    @StateObject private var appViewModel = MediaInspectorViewModel()
    
    var body: some Scene {
        WindowGroup {
            MediaInspector()
                .environmentObject(appViewModel)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 850, height: 650)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MediaInspector") {
                    appViewModel.showAboutView = true
                }
            }
        }
    }
}
