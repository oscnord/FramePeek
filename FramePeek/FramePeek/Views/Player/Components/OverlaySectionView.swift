import SwiftUI

/// A collapsible section container for the statistics overlay
struct OverlaySectionView<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    content()
                }
                .padding(.leading, DesignSystem.Spacing.xl)
                .padding(.top, DesignSystem.Spacing.xs)
            }
        }
    }
}

/// A non-collapsible section header (for always-visible content)
struct OverlaySectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

/// A single row in the overlay with icon and value
struct OverlayRow: View {
    let icon: String?
    let label: String?
    let value: String

    init(icon: String? = nil, label: String? = nil, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }

            if let label = label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }
}

/// A compact row showing multiple values separated by bullets
struct OverlayCompactRow: View {
    let values: [String]

    var body: some View {
        Text(values.joined(separator: " · "))
            .font(.caption)
            .monospacedDigit()
    }
}

/// A row with a badge (for HDR, VFR, etc.)
struct OverlayBadgeRow: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }
}
