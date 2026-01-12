import SwiftUI

/// Centralized design system for FramePeek
/// Provides consistent design tokens including corner radius, spacing, colors, materials, and more
struct DesignSystem {
    // MARK: - Corner Radius
    
    /// macOS version-aware corner radius values
    /// Automatically adapts based on macOS version for optimal visual consistency
    struct CornerRadius {
        /// Small corner radius (3 for macOS 15.0+, ~2 for older versions)
        static var small: CGFloat {
            if #available(macOS 15.0, *) {
                return 3
            } else {
                return 2
            }
        }
        
        /// Medium corner radius (6 for macOS 15.0+, ~4-5 for older versions)
        static var medium: CGFloat {
            if #available(macOS 15.0, *) {
                return 6
            } else {
                return 4
            }
        }
        
        /// Large corner radius (10 for macOS 15.0+, ~7-8 for older versions)
        static var large: CGFloat {
            if #available(macOS 15.0, *) {
                return 10
            } else {
                return 7
            }
        }
        
        /// Extra large corner radius (14 for macOS 15.0+, ~10-11 for older versions)
        static var xlarge: CGFloat {
            if #available(macOS 15.0, *) {
                return 14
            } else {
                return 10
            }
        }
        
        // Specific values for common use cases
        static var extraSmall: CGFloat { 3 }
        static var card: CGFloat { 10 }
        static var panel: CGFloat { 12 }
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static var xs: CGFloat { 2 }
        static var xs2: CGFloat { 3 }
        static var sm: CGFloat { 4 }
        static var sm2: CGFloat { 5 }
        static var sm3: CGFloat { 6 }
        static var md: CGFloat { 8 }
        static var md2: CGFloat { 10 }
        static var lg: CGFloat { 12 }
        static var lg2: CGFloat { 14 }
        static var lg3: CGFloat { 16 }
        static var xl: CGFloat { 20 }
        static var xl2: CGFloat { 24 }
        static var xxl: CGFloat { 32 }
        static var xxl2: CGFloat { 40 }
    }
    
    // MARK: - Padding
    
    struct Padding {
        static var xs: CGFloat { 4 }
        static var sm: CGFloat { 5 }
        static var sm2: CGFloat { 6 }
        static var md: CGFloat { 8 }
        static var md2: CGFloat { 9 }
        static var md3: CGFloat { 10 }
        static var lg: CGFloat { 12 }
        static var lg2: CGFloat { 14 }
        static var lg3: CGFloat { 16 }
        static var xl: CGFloat { 20 }
        static var xl2: CGFloat { 24 }
        static var xl3: CGFloat { 28 }
        static var xxl: CGFloat { 32 }
        static var xxl2: CGFloat { 40 }
    }
    
    // MARK: - Typography
    
    struct Typography {
        static var caption: CGFloat { 9 }
        static var caption2: CGFloat { 10 }
        static var footnote: CGFloat { 12 }
        static var subheadline: CGFloat { 13 }
        static var body: CGFloat { 14 }
        static var callout: CGFloat { 15 }
        static var headline: CGFloat { 16 }
        static var title3: CGFloat { 20 }
        static var title2: CGFloat { 24 }
        static var title1: CGFloat { 28 }
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        static var small: CGFloat { 6 }
    }
    
    // MARK: - Borders
    
    struct Borders {
        static var thin: CGFloat { 1 }
        static var medium: CGFloat { 1.5 }
        static var thick: CGFloat { 2 }
    }
    
    // MARK: - Colors
    
    struct Colors {
        // MARK: Chart Colors
        
        struct Chart {
            /// Main chart line/area color (accentColor)
            static var primary: Color { .blue }

            static var secondary: Color { Color(red: 0.0, green: 0.4, blue: 0.9) }
            
            /// Primary color when analyzing (with reduced opacity)
            static var primaryAnalyzing: Color { .blue.opacity(0.7) }
            
            /// Primary color area gradient top (when analyzing)
            static var primaryAreaTopAnalyzing: Color { .blue.opacity(0.5) }
            
            /// Primary color area gradient bottom (when analyzing)
            static var primaryAreaBottomAnalyzing: Color { .blue.opacity(0.1) }
            
            /// Primary color area gradient top (normal)
            static var primaryAreaTop: Color { .blue.opacity(0.7) }
            
            /// Primary color area gradient bottom (normal)
            static var primaryAreaBottom: Color { .blue.opacity(0.15) }
            
            /// Keyframe marker color
            static var keyframe: Color { .orange }
            
            /// Keyframe marker color with opacity
            static var keyframeOpacity: Color { .orange.opacity(0.8) }
            
            /// Average line color
            static var average: Color { .orange }
            
            /// Average line color with opacity
            static var averageOpacity: Color { .orange.opacity(0.7) }
            
            /// Grid line color
            static var grid: Color { .blue.opacity(0.18) }
            
            /// Grid line color (Y-axis)
            static var gridY: Color { .blue.opacity(0.20) }
            
            /// Axis tick color
            static var axisTick: Color { .blue.opacity(0.35) }
            
            /// Axis label color
            static var axisLabel: Color { .secondary }
            
            /// Chart background color
            static var background: Color { .black.opacity(0.06) }
            
            /// Hovered sample line color
            static var hoveredLine: Color { Color.primary.opacity(0.7) }
        }
        
        // MARK: Semantic Colors
        
        struct Semantic {
            static var primary: Color { Color.primary }
            static var secondary: Color { Color.secondary }
            static var tertiary: Color { Color(NSColor.tertiaryLabelColor) }
            static var quaternary: Color { Color(NSColor.quaternaryLabelColor) }
        }
        
        // MARK: Status Colors
        
        struct Status {
            static var success: Color { .green }
            static var warning: Color { .orange }
            static var error: Color { .red }
        }
    }
    
    // MARK: - Materials
    
    struct Materials {
        static var ultraThin: Material { .ultraThinMaterial }
        
        static var thin: Material { .thinMaterial }
        
        static var regular: Material { .regularMaterial }
        
        /// Fallback material for liquid glass effect (use `.liquidGlassBackground()` modifier instead)
        static var liquidGlass: Material {
            return .regularMaterial
        }
    }
}

// MARK: - Convenience Extensions

extension RoundedRectangle {
    /// Creates a rounded rectangle with design system corner radius
    static func designSystem(_ size: CGFloat, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size, style: style)
    }
}

extension View {
    /// Applies liquid glass effect on macOS 26+, falls back to regular material on earlier versions
    @ViewBuilder
    func liquidGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect()
        } else {
            self.background(DesignSystem.Materials.regular)
        }
    }
    
    /// Applies liquid glass effect with a shape on macOS 26+, falls back to regular material on earlier versions
    @ViewBuilder
    func liquidGlassBackground<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(DesignSystem.Materials.regular, in: shape)
        }
    }
    
    /// Applies liquid glass effect with a style on macOS 26+, falls back to regular material on earlier versions
    @available(macOS 26.0, *)
    @ViewBuilder
    func liquidGlassBackground(_ style: Glass) -> some View {
        self.glassEffect(style)
    }
    
    /// Applies liquid glass effect with a style and shape on macOS 26+, falls back to regular material on earlier versions
    @available(macOS 26.0, *)
    @ViewBuilder
    func liquidGlassBackground<S: Shape>(_ style: Glass, in shape: S) -> some View {
        self.glassEffect(style, in: shape)
    }
}

