import SwiftUI

struct LoadingView: View {
    let message: String
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ProgressView()
                .controlSize(.small)

            Text(message)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            
            if let progress = progress {
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingView(message: "Analyzing...")
        LoadingView(message: "Analyzing...", progress: 0.45)
        LoadingView(message: "Loading...")
    }
    .padding()
}
