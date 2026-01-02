
import SwiftUI

struct CopiedBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

#Preview {
    CopiedBanner(text: "Copied all text")
}
