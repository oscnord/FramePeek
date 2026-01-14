import SwiftUI

struct UnanalyzableFileView: View {
    let fileName: String
    let hasVideoTrack: Bool
    let hasValidDuration: Bool
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Unable to Analyze File")
                        .font(.system(size: DesignSystem.Typography.title3, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(fileName)
                        .font(.system(size: DesignSystem.Typography.body))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    explanationText
                    
                    if !hasVideoTrack {
                        reasonCard(
                            icon: "video.slash",
                            title: "No Video Track",
                            description: "This file doesn't contain a video track. FramePeek can only analyze video files with video tracks."
                        )
                    }
                    
                    if !hasValidDuration {
                        reasonCard(
                            icon: "clock.badge.xmark",
                            title: "Invalid Duration",
                            description: "The file's duration could not be determined or is invalid. This prevents frame-by-frame analysis."
                        )
                    }
                    
                    if hasVideoTrack && hasValidDuration {
                        reasonCard(
                            icon: "questionmark.circle",
                            title: "Analysis Failed",
                            description: "The file structure could not be read for bitrate analysis. This may be due to an unsupported format or corrupted file."
                        )
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, DesignSystem.Padding.lg)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var explanationText: some View {
        Text("This file was loaded, but FramePeek cannot extract bitrate or frame analysis data from it. The file may be missing required video information or use an unsupported format.")
            .font(.system(size: DesignSystem.Typography.callout))
            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignSystem.Padding.md)
    }
    
    private func reasonCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: DesignSystem.Typography.footnote))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
            
            Spacer()
        }
        .padding(DesignSystem.Padding.md)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                )
        }
    }
}

#Preview {
    UnanalyzableFileView(
        fileName: "example.mp4",
        hasVideoTrack: false,
        hasValidDuration: true
    )
    .frame(width: 800, height: 600)
}

