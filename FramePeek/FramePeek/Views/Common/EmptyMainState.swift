import SwiftUI

struct EmptyMainState: View {
    @StateObject private var fileHistory = FileHistoryManager.shared
    let onFileSelected: (URL) -> Void
    let onOpenFile: () -> Void

    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

    private var recentFiles: [URL] {
        fileHistory.validFiles
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            // Title
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("FramePeek")
                    .font(.system(size: DesignSystem.Typography.title2, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Inspect and analyze your video files")
                    .font(.system(size: DesignSystem.Typography.callout))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)

                // Supported file types badges
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(supportedFileTypes, id: \.self) { fileType in
                        FileTypeBadge(fileType: fileType)
                    }
                }
                .padding(.top, DesignSystem.Padding.sm)
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)

            // Recent files box
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent Files")
                        .font(.system(size: DesignSystem.Typography.footnote, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .padding(.horizontal, DesignSystem.Padding.md)
                        .padding(.top, DesignSystem.Padding.md)
                        .padding(.bottom, DesignSystem.Padding.sm)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(recentFiles, id: \.self) { url in
                                RecentFileRow(url: url, onSelect: { onFileSelected(url) })
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .fill(DesignSystem.Materials.thin)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                                .strokeBorder(.separator, lineWidth: DesignSystem.Borders.thin)
                        )
                }
                .frame(width: 400)
                .opacity(contentOpacity)
                .offset(y: contentOffset)
            }

            Button(action: onOpenFile) {
                Text(String(localized: "Open File…"))
                    .font(.system(size: DesignSystem.Typography.callout, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .offset(y: contentOffset)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                contentOpacity = 1.0
                contentOffset = 0
            }
        }
    }
}

private let supportedFileTypes = ["MP4", "MOV", "AVI", "MPEG", "M4V"]

private struct FileTypeBadge: View {
    let fileType: String

    var body: some View {
        Text(fileType)
            .font(.system(size: DesignSystem.Typography.caption2, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            .padding(.horizontal, DesignSystem.Padding.sm)
            .padding(.vertical, DesignSystem.Padding.xs)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Materials.ultraThin)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.separator.opacity(0.5), lineWidth: DesignSystem.Borders.thin)
                    )
            }
    }
}

private struct RecentFileRow: View {
    let url: URL
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.system(size: DesignSystem.Typography.footnote, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: DesignSystem.Typography.caption2))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Padding.md)
            .padding(.vertical, DesignSystem.Padding.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    EmptyMainState(onFileSelected: { _ in }, onOpenFile: {})
        .frame(width: 800, height: 600)
}
