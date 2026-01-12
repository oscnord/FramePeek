import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text(title)
                .font(.system(size: DesignSystem.Typography.headline, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.Semantic.primary)
            
            content
                .padding(.leading, DesignSystem.Padding.sm)
        }
    }
}

