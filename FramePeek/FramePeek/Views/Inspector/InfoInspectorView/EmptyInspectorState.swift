//
//  EmptyInspectorState.swift
//  FramePeek
//

import SwiftUI

struct EmptyInspectorState: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            
            Text("No Video Loaded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Drop a video file or click Open")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyInspectorState()
}
