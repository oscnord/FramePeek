import SwiftUI

struct WelcomeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var headerOpacity: Double = 0
    @State private var cardOpacities: [Double] = Array(repeating: 0, count: 6)
    @State private var buttonOpacity: Double = 0
    
    private let cardHeight: CGFloat = 100
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl2) {
            // Header
            VStack(spacing: DesignSystem.Spacing.md) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                
                Text("Welcome to FramePeek")
                    .font(.system(size: DesignSystem.Typography.title2, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Video and audio inspection tools")
                    .font(.system(size: DesignSystem.Typography.callout))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
            }
            .opacity(headerOpacity)
            
            // Feature Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DesignSystem.Spacing.lg),
                GridItem(.flexible(), spacing: DesignSystem.Spacing.lg)
            ], spacing: DesignSystem.Spacing.lg) {
                ForEach(Array(welcomeFeatures.enumerated()), id: \.element.id) { index, feature in
                    FeatureCard(feature: feature)
                        .frame(height: cardHeight)
                        .opacity(cardOpacities[index])
                }
            }
            .padding(.horizontal, DesignSystem.Padding.xl)
            
            // Get Started Button
            Button(action: { dismiss() }) {
                Text(String(localized: "Get Started"))
                    .font(.system(size: DesignSystem.Typography.callout, weight: .semibold))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .opacity(buttonOpacity)
        }
        .padding(.top, DesignSystem.Padding.xxl)
        .padding(.bottom, DesignSystem.Padding.xl2)
        .padding(.horizontal, DesignSystem.Padding.lg)
        .frame(width: 600)
        .onAppear {
            animateEntrance()
        }
    }
    
    private func animateEntrance() {
        // Header fades in first
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            headerOpacity = 1.0
        }
        
        // Cards fade in with stagger
        for index in 0..<welcomeFeatures.count {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1 + Double(index) * 0.05)) {
                cardOpacities[index] = 1.0
            }
        }
        
        // Button fades in last
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5)) {
            buttonOpacity = 1.0
        }
    }
}

// MARK: - Feature Data Model

private struct WelcomeFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

private let welcomeFeatures: [WelcomeFeature] = [
    WelcomeFeature(
        icon: "chart.xyaxis.line",
        title: "Bitrate Analysis",
        description: "Visualize frame-by-frame bitrate with interactive charts and hover inspection."
    ),
    WelcomeFeature(
        icon: "film.stack",
        title: "GOP Structure",
        description: "Analyze I/P/B frame patterns to understand encoding and optimize for streaming."
    ),
    WelcomeFeature(
        icon: "waveform.path.ecg",
        title: "A/V Sync Analysis",
        description: "Detect audio/video timing drift and duration mismatches with millisecond precision."
    ),
    WelcomeFeature(
        icon: "scope",
        title: "Color Scopes",
        description: "Vectorscope, RGB histogram, and waveform scope for color analysis."
    ),
    WelcomeFeature(
        icon: "square.3.layers.3d",
        title: "Container Inspector",
        description: "Explore the internal atom/box structure of MP4 and MOV files."
    ),
    WelcomeFeature(
        icon: "server.rack",
        title: "REST API",
        description: "Automate analysis with a built-in HTTP server and webhook callbacks."
    )
]

// MARK: - Feature Card

private struct FeatureCard: View {
    let feature: WelcomeFeature
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            Image(systemName: feature.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(feature.title)
                    .font(.system(size: DesignSystem.Typography.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(feature.description)
                    .font(.system(size: DesignSystem.Typography.footnote))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .lineLimit(3)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DesignSystem.Padding.lg)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: DesignSystem.Borders.thin)
                )
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeSheetView()
}
