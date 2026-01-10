import SwiftUI

struct ErrorToast: View {
    let message: String
    @Binding var isVisible: Bool
    let onDismiss: () -> Void
    let autoDismissAfter: TimeInterval?
    
    @State private var autoDismissTask: Task<Void, Never>?
    
    init(
        message: String,
        isVisible: Binding<Bool>,
        onDismiss: @escaping () -> Void,
        autoDismissAfter: TimeInterval? = 5.0
    ) {
        self.message = message
        self._isVisible = isVisible
        self.onDismiss = onDismiss
        self.autoDismissAfter = autoDismissAfter
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(message)
                .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: DesignSystem.Spacing.sm)
            
            Button {
                dismissToast()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DesignSystem.Typography.callout))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss"))
        }
        .padding(.horizontal, DesignSystem.Padding.lg2)
        .padding(.vertical, DesignSystem.Padding.md2)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .stroke(.red.opacity(0.4), lineWidth: 1.5)
                }
                .background {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .fill(.red.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
        }
        .padding(.horizontal, DesignSystem.Padding.xl2)
        .padding(.top, DesignSystem.Padding.lg2)
        .frame(maxWidth: 400)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -60)
        .allowsHitTesting(isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
        .onChange(of: isVisible) { oldValue, newValue in
            if newValue {
                // Toast just became visible, start auto-dismiss timer if configured
                if let dismissAfter = autoDismissAfter {
                    startAutoDismiss(dismissAfter: dismissAfter)
                }
            } else {
                // Toast dismissed, cancel auto-dismiss task
                autoDismissTask?.cancel()
                autoDismissTask = nil
            }
        }
        .onDisappear {
            // Cancel auto-dismiss task when view disappears
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }
    
    private func startAutoDismiss(dismissAfter: TimeInterval) {
        // Cancel any existing auto-dismiss task
        autoDismissTask?.cancel()
        
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(dismissAfter * 1_000_000_000))
            await MainActor.run {
                // Only dismiss if task wasn't cancelled and toast is still visible
                if !Task.isCancelled && isVisible {
                    dismissToast()
                }
            }
        }
    }
    
    private func dismissToast() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = false
        }
        // Call dismiss handler after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

