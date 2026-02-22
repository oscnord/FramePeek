import SwiftUI

struct EmptyMainState: View {
    @State private var fileHistory = FileHistoryManager.shared
    let onFileSelected: (URL) -> Void
    let onOpenFile: () -> Void
    var isDropTargeted: Bool = false

    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

    private var recentFiles: [URL] {
        fileHistory.validFiles
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            // Main content area
            VStack(spacing: DesignSystem.Spacing.lg3) {
                // Drop zone indicator
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : DesignSystem.Colors.Semantic.tertiary)
                    
                    Text("Drop video file here")
                        .font(.system(size: DesignSystem.Typography.body))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : DesignSystem.Colors.Semantic.secondary)
                }
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
                
                // Divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 200, height: 1)
                
                // Open File button
                Button(action: onOpenFile) {
                    Text(String(localized: "Open File…"))
                        .font(.system(size: DesignSystem.Typography.callout, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                
                // Supported file types
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Array(supportedFileTypes.enumerated()), id: \.element) { index, fileType in
                        FileTypeBadge(fileType: fileType)
                        
                        if index < supportedFileTypes.count - 1 {
                            Text("·")
                                .foregroundStyle(DesignSystem.Colors.Semantic.quaternary)
                        }
                    }
                }
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)

            // Recent files section
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Recent Files")
                        .font(.system(size: DesignSystem.Typography.footnote, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .padding(.leading, DesignSystem.Padding.xs)

                    VStack(spacing: 0) {
                        ForEach(Array(recentFiles.enumerated()), id: \.element) { index, url in
                            RecentFileRow(url: url, onSelect: { onFileSelected(url) })
                            
                            if index < recentFiles.count - 1 {
                                Divider()
                                    .padding(.leading, DesignSystem.Padding.md)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
                }
                .frame(width: 450)
                .opacity(contentOpacity)
                .offset(y: contentOffset)
            }
            
            // Keyboard shortcuts
            ShortcutsView()
                .opacity(contentOpacity)
                .offset(y: contentOffset)
                .padding(.top, DesignSystem.Padding.sm)

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
            .font(.system(size: DesignSystem.Typography.caption, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
    }
}

private struct RecentFileRow: View {
    let url: URL
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(size: DesignSystem.Typography.subheadline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: DesignSystem.Typography.caption2))
                        .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.Semantic.quaternary)
            }
            .padding(.horizontal, DesignSystem.Padding.md)
            .padding(.vertical, DesignSystem.Padding.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                    .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.5) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Keyboard Shortcuts

private struct ShortcutsView: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xl) {
            ShortcutItem(keys: ["⌘", "O"], label: "Open")
            ShortcutItem(keys: ["⌘", "T"], label: "New Tab")
            ShortcutItem(keys: ["⌘", "I"], label: "Inspector")
        }
    }
}

private struct ShortcutItem: View {
    let keys: [String]
    let label: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: 1) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: DesignSystem.Typography.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                                )
                        }
                }
            }
            
            Text(label)
                .font(.system(size: DesignSystem.Typography.caption))
                .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
        }
    }
}

#Preview {
    EmptyMainState(onFileSelected: { _ in }, onOpenFile: {})
        .frame(width: 800, height: 600)
}
