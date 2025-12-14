//
//  ViewHelpers.swift
//  MediaInspector
//

import SwiftUI

// MARK: - View Extension

extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
