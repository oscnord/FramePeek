//
//  SectionDivider.swift
//  FramePeek
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }
}

#Preview {
    SectionDivider()
}
