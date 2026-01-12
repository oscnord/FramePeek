import SwiftUI

struct LoadingView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .controlSize(.small)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingView(message: "Analyzing color…")
        LoadingView(message: "Analyzing sync…")
        LoadingView(message: "Loading…")
    }
    .padding()
}

