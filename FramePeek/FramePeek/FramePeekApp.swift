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
    
    var body: some Scene {
        WindowGroup {
            FramePeek()
                .environmentObject(appViewModel)
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
        }
    }
}
