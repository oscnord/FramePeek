import SwiftUI

struct LiquidGlassToolbarButton: View {
    let systemImage: String
    let action: () -> Void
    let keyboardShortcut: KeyEquivalent?
    let modifiers: EventModifiers
    
    @Namespace private var namespace
    @State private var isHovered: Bool = false
    
    init(
        systemImage: String,
        action: @escaping () -> Void,
        keyboardShortcut: KeyEquivalent? = nil,
        modifiers: EventModifiers = []
    ) {
        self.systemImage = systemImage
        self.action = action
        self.keyboardShortcut = keyboardShortcut
        self.modifiers = modifiers
    }
    
    var body: some View {
        if #available(macOS 26.0, *) {
            glassButton
        } else {
            fallbackButton
        }
    }
    
    @available(macOS 26.0, *)
    private var glassButton: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16)
                .glassEffect()
                .glassEffectID(systemImage, in: namespace)
        }
        .apply { view in
            if let shortcut = keyboardShortcut {
                view.keyboardShortcut(shortcut, modifiers: modifiers)
            } else {
                view
            }
        }
    }
    
    private var fallbackButton: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                        .fill(
                            isHovered ?
                                Color(NSColor.controlBackgroundColor).opacity(0.7) :
                                Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .apply { view in
            if let shortcut = keyboardShortcut {
                view.keyboardShortcut(shortcut, modifiers: modifiers)
            } else {
                view
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

extension View {
    @ViewBuilder
    func apply<V: View>(@ViewBuilder transform: (Self) -> V) -> some View {
        transform(self)
    }
}

