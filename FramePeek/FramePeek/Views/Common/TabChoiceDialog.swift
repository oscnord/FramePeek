//
//  TabChoiceDialog.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

struct TabChoiceDialog: View {
    let fileName: String
    let onChooseCurrentTab: () -> Void
    let onChooseNewTab: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Open File")
                .font(.headline)
            
            Text("A file is already open in this tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(fileName)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            
            Text("Would you like to open this file in the current tab or a new tab?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button {
                    onChooseCurrentTab()
                } label: {
                    Label("Open in Current Tab", systemImage: "doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    onChooseNewTab()
                } label: {
                    Label("Open in New Tab", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    TabChoiceDialog(
        fileName: "example-video-file.mp4",
        onChooseCurrentTab: {},
        onChooseNewTab: {},
        onCancel: {}
    )
}

