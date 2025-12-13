//
//  CollapsibleSection.swift
//  MediaInspector
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct CollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    var isLoading: Bool = false
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @State var isExpanded = true
    return CollapsibleSection(
        title: "Preview Section",
        systemImage: "doc.fill",
        isExpanded: $isExpanded
    ) {
        Text("Section content goes here")
            .font(.caption)
    }
}
