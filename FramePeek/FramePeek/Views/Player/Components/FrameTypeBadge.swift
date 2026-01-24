import SwiftUI

/// A compact badge showing the current frame type (I, P, B)
struct FrameTypeBadge: View {
    let frameType: FrameType

    var body: some View {
        Text(frameType.rawValue)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(textColor)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(backgroundColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(backgroundColor.opacity(0.5), lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        switch frameType {
        case .i:
            return .blue  // I-frames (keyframes) - blue
        case .p:
            return .green  // P-frames (predicted) - green
        case .b:
            return .orange  // B-frames (bidirectional) - orange
        case .unknown:
            return .gray
        }
    }

    private var textColor: Color {
        switch frameType {
        case .i:
            return .blue
        case .p:
            return .green
        case .b:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}

/// Extended badge showing frame type with label
struct FrameTypeBadgeExtended: View {
    let frameType: FrameType
    let showLabel: Bool

    init(frameType: FrameType, showLabel: Bool = true) {
        self.frameType = frameType
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            FrameTypeBadge(frameType: frameType)

            if showLabel {
                Text(frameTypeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var frameTypeLabel: String {
        switch frameType {
        case .i:
            return String(localized: "Keyframe")
        case .p:
            return String(localized: "Predicted")
        case .b:
            return String(localized: "Bidirectional")
        case .unknown:
            return String(localized: "Unknown")
        }
    }
}
