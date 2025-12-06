//
//  MediaInspector.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
import Charts

struct MediaInspector: View {
    @StateObject private var viewModel = MediaInspectorViewModel()

    var body: some View {
        HSplitView {
            BitrateChartView(viewModel: viewModel)
                .frame(minWidth: 400)

            InfoInspectorView(viewModel: viewModel)
                .frame(minWidth: 260, idealWidth: 320)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.pickFile()
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

// Preview
#Preview {
    MediaInspector()
}
