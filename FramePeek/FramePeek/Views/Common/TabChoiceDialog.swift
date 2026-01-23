import SwiftUI

struct TabChoiceDialog: View {
    let fileName: String
    let onChooseCurrentTab: () -> Void
    let onChooseNewTab: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl2) {
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("A file is already open")
                    .font(.system(size: DesignSystem.Typography.callout, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.Semantic.primary)

                Text("Open \"\(fileName)\" in:")
                    .font(.system(size: DesignSystem.Typography.subheadline))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: DesignSystem.Spacing.md2) {
                Button {
                    onChooseCurrentTab()
                } label: {
                    VStack(spacing: DesignSystem.Spacing.sm3) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: DesignSystem.Typography.title3))
                        Text("Current Tab")
                            .font(.system(size: DesignSystem.Typography.footnote, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Padding.lg3)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onChooseNewTab()
                } label: {
                    VStack(spacing: DesignSystem.Spacing.sm3) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: DesignSystem.Typography.title3))
                        Text("New Tab")
                            .font(.system(size: DesignSystem.Typography.footnote, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Padding.lg3)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DesignSystem.Padding.xl3)
        .frame(width: 360)
    }
}

#Preview {
    TabChoiceDialog(
        fileName: "example-video-file.mp4",
        onChooseCurrentTab: {},
        onChooseNewTab: {},
        onCancel: {}
    )
}
