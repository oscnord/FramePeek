import SwiftUI

struct OptionBadge: View {
    let name: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .bold()
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(.rect(cornerRadius: DesignSystem.CornerRadius.small))
    }
}
