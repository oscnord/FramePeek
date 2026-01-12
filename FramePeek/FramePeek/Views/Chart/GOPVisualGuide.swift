import SwiftUI

struct GOPVisualGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // GOP explanation
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 24, height: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Each block = 1 GOP")
                            .font(.caption2)
                            .fontWeight(.medium)
                        Text("Width = duration, Height = frame count")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // I-frame marker
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Blue dot = I-frame (GOP start)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Pattern colors
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(.green, lineWidth: 2)
                        .frame(width: 16, height: 12)
                    Text("Green = Fixed pattern")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(.orange, lineWidth: 2)
                        .frame(width: 16, height: 12)
                    Text("Orange = Variable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(.red, lineWidth: 2)
                        .frame(width: 16, height: 12)
                    Text("Red = Irregular")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Padding.sm)
            .padding(.vertical, DesignSystem.Padding.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                    .fill(DesignSystem.Materials.ultraThin)
            )
        }
    }
}

