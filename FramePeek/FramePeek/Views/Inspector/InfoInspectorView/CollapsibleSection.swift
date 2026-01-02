
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
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.leading, 4)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.top, 8)
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
