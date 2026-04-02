import SwiftUI

// MARK: - Legend Preset

/// Predefined legend configurations for common chart types
enum LegendPreset {
    case gopDuration
    case frameTypes
    case custom(items: [LegendItem])
    
    var items: [LegendItem] {
        switch self {
        case .gopDuration:
            return [
                LegendItem(color: Color(red: 0.3, green: 0.7, blue: 0.4), label: String(localized: "Consistent")),
                LegendItem(color: Color(red: 0.4, green: 0.6, blue: 0.8), label: String(localized: "Slightly Long")),
                LegendItem(color: Color(red: 0.9, green: 0.7, blue: 0.3), label: String(localized: "Slightly Short")),
                LegendItem(color: Color(red: 0.3, green: 0.5, blue: 0.9), label: String(localized: "Long")),
                LegendItem(color: Color(red: 0.9, green: 0.5, blue: 0.3), label: String(localized: "Short"))
            ]
        case .frameTypes:
            return [
                LegendItem(color: DesignSystem.Colors.FrameType.i, label: "I"),
                LegendItem(color: DesignSystem.Colors.FrameType.p, label: "P"),
                LegendItem(color: DesignSystem.Colors.FrameType.b, label: "B")
            ]
        case .custom(let items):
            return items
        }
    }
    
    var title: String? {
        switch self {
        case .gopDuration:
            return String(localized: "Duration")
        case .frameTypes:
            return String(localized: "Frame Types")
        case .custom:
            return nil
        }
    }
}

// MARK: - Legend Item

struct LegendItem: Identifiable {
    let id = UUID()
    let color: Color
    let label: String
    var description: String?
}

// MARK: - Color Legend View

/// A reusable horizontal color legend component
struct ColorLegendView: View {
    let preset: LegendPreset
    var showTitle: Bool = true
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: compact ? DesignSystem.Spacing.sm : DesignSystem.Spacing.lg) {
            if showTitle, let title = preset.title {
                Text(title + ":")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(preset.items) { item in
                legendItemView(item)
            }
            
            if !compact {
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private func legendItemView(_ item: LegendItem) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(item.color)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
            
            Text(item.label)
                .font(compact ? .system(size: 9) : .caption2)
                .fontWeight(.medium)
        }
        .help(item.description ?? item.label)
    }
}

// MARK: - Convenience Initializers

extension ColorLegendView {
    /// Creates a GOP duration legend
    static var gopDuration: ColorLegendView {
        ColorLegendView(preset: .gopDuration)
    }
    
    /// Creates a frame types legend
    static var frameTypes: ColorLegendView {
        ColorLegendView(preset: .frameTypes)
    }
    
    /// Creates a compact GOP duration legend
    static var gopDurationCompact: ColorLegendView {
        ColorLegendView(preset: .gopDuration, showTitle: false, compact: true)
    }
    
    /// Creates a compact frame types legend
    static var frameTypesCompact: ColorLegendView {
        ColorLegendView(preset: .frameTypes, showTitle: false, compact: true)
    }
}

// MARK: - Vertical Legend Variant

/// A vertical legend layout for use in sidebars or panels
struct VerticalColorLegendView: View {
    let preset: LegendPreset
    var showTitle: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if showTitle, let title = preset.title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(preset.items) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    
                    Text(item.label)
                        .font(.caption2)
                    
                    if let description = item.description {
                        Text("– \(description)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("GOP Duration Legend") {
    VStack(spacing: 20) {
        ColorLegendView.gopDuration
        ColorLegendView.gopDurationCompact
        VerticalColorLegendView(preset: .gopDuration)
    }
    .padding()
}

#Preview("Frame Types Legend") {
    VStack(spacing: 20) {
        ColorLegendView.frameTypes
        ColorLegendView.frameTypesCompact
        VerticalColorLegendView(preset: .frameTypes)
    }
    .padding()
}
