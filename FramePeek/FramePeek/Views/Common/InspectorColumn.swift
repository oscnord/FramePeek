//
//  InspectorColumn.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

struct InspectorColumn<Content: View>: View {
    let width: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Inspector")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .background(.background)
    }
}

