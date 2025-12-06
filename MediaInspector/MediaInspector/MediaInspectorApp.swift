//
//  MediaInspectorApp.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import SwiftUI

@main
struct MediaInspectorApp: App {
    var body: some Scene {
        WindowGroup {
            MediaInspector()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 850, height: 650)
    }
}
