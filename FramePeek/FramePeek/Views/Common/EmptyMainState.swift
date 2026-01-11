import SwiftUI

struct EmptyMainState: View {
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl2) {
            Spacer()
            
            // Main icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .blue.opacity(0.15),
                                .blue.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .blue,
                                .blue.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            
            // Title
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("Welcome to FramePeek")
                    .font(.system(size: DesignSystem.Typography.title2, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Inspect and analyze your video files")
                    .font(.system(size: DesignSystem.Typography.callout))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)
            
            // Instructions
            VStack(spacing: DesignSystem.Spacing.lg) {
                InstructionRow(
                    icon: "folder",
                    title: "Open a File",
                    description: "Click Open in the toolbar or press ⌘O"
                )
                
                InstructionRow(
                    icon: "arrow.down.doc",
                    title: "Drag and Drop",
                    description: "Drop a video file anywhere in this window"
                )
                
                InstructionRow(
                    icon: "plus.square.on.square",
                    title: "Multiple Tabs",
                    description: "Create new tabs to compare different files"
                )
            }
            .padding(.horizontal, DesignSystem.Padding.xxl)
            .opacity(contentOpacity)
            .offset(y: contentOffset)
            
            // Supported formats hint
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Supported formats")
                    .font(.system(size: DesignSystem.Typography.caption2))
                    .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    FormatBadge("MP4")
                    FormatBadge("MOV")
                    FormatBadge("AVI")
                    FormatBadge("MPEG")
                    FormatBadge("+ more")
                }
            }
            .padding(.top, DesignSystem.Padding.lg)
            .opacity(contentOpacity)
            .offset(y: contentOffset)
            
            Spacer()
        }
        .frame(maxWidth: 600)
        .padding(DesignSystem.Padding.xxl)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
                contentOpacity = 1.0
                contentOffset = 0
            }
        }
    }
}

private struct InstructionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.blue.opacity(0.1))
                }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: DesignSystem.Typography.footnote))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
            
            Spacer()
        }
        .padding(DesignSystem.Padding.lg)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .strokeBorder(.separator.opacity(0.2), lineWidth: DesignSystem.Borders.thin)
                )
        }
    }
}

private struct FormatBadge: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: DesignSystem.Typography.caption, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            .padding(.horizontal, DesignSystem.Padding.md)
            .padding(.vertical, DesignSystem.Padding.xs)
            .background {
                Capsule()
                    .fill(DesignSystem.Materials.ultraThin)
                    .overlay(
                        Capsule()
                            .strokeBorder(.separator.opacity(0.3), lineWidth: DesignSystem.Borders.thin)
                    )
            }
    }
}

#Preview {
    EmptyMainState()
        .frame(width: 800, height: 600)
}

