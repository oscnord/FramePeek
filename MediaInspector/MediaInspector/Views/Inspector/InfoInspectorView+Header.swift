//
//  InfoInspectorView+Header.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

extension InfoInspectorView {
    // MARK: - Header / Actions

    func header(info: ExtendedVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.fileName)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(info.resolution) • \(info.codec)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func actionBar(info: ExtendedVideoInfo) -> some View {
        HStack(spacing: 8) {
            Button {
                copyAll(info: info)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    let allExpanded = fileExpanded && videoExpanded && colorExpanded && audioExpanded && analysisExpanded
                    if allExpanded {
                        collapseAll()
                    } else {
                        expandAll()
                    }
                }
            } label: {
                let allExpanded = fileExpanded && videoExpanded && colorExpanded && audioExpanded && analysisExpanded
                Label(allExpanded ? "Collapse" : "Expand", 
                      systemImage: allExpanded ? "chevron.up.2" : "chevron.down.2")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
    }
    
    func expandAll() {
        fileExpanded = true
        metadataExpanded = true
        videoExpanded = true
        colorExpanded = true
        audioExpanded = true
        analysisExpanded = true
    }
    
    func collapseAll() {
        fileExpanded = false
        metadataExpanded = false
        videoExpanded = false
        colorExpanded = false
        audioExpanded = false
        analysisExpanded = false
    }
}
