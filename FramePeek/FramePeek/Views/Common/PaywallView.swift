import SwiftUI
import AppKit

struct PaywallView: View {
    @ObservedObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var showErrorToast: Bool = false
    
    let fileCount: Int
    let remainingFiles: Int
    let onDismiss: (() -> Void)?
    
    init(
        purchaseManager: PurchaseManager,
        fileCount: Int,
        remainingFiles: Int,
        onDismiss: (() -> Void)? = nil
    ) {
        self.purchaseManager = purchaseManager
        self.fileCount = fileCount
        self.remainingFiles = remainingFiles
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(NSColor.controlBackgroundColor),
                    Color(NSColor.controlBackgroundColor).opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Close button - placed early in ZStack to be on top
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Close"))
                    .padding(DesignSystem.Padding.md)
                }
                Spacer()
            }
            
            // Main content
            VStack(spacing: 0) {
                // Header with app icon
                VStack(spacing: DesignSystem.Spacing.lg) {
                    appIcon
                    
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Text(String(localized: "You've used up your free file inspections"))
                            .font(.system(size: DesignSystem.Typography.title2, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(String(format: String(localized: "After analyzing %lld files for free, consider purchasing FramePeek to continue."), fileCount))
                            .font(.system(size: DesignSystem.Typography.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, DesignSystem.Padding.xl2)
                .padding(.horizontal, DesignSystem.Padding.xl3)
                .padding(.bottom, DesignSystem.Padding.md)
                
                // Action buttons
                VStack(spacing: DesignSystem.Spacing.lg) {
                    if purchaseManager.isLoading {
                        processingView
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            if let price = purchaseManager.productPrice {
                                VStack(spacing: DesignSystem.Spacing.xs) {
                                    Text(price)
                                        .font(.system(size: DesignSystem.Typography.title2, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text(String(localized: "One-time purchase"))
                                        .font(.system(size: DesignSystem.Typography.caption2))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, DesignSystem.Padding.xl2)
                            }

                            Button {
                                Task {
                                    await purchaseManager.purchase()
                                }
                            } label: {
                                Text(String(localized: "Purchase FramePeek"))
                                    .font(.system(size: DesignSystem.Typography.callout, weight: .semibold))
                                    .padding(.horizontal, DesignSystem.Padding.xl2)
                                    .padding(.vertical, DesignSystem.Padding.md2)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(purchaseManager.isPurchased)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        
                        Button {
                            Task {
                                await purchaseManager.restorePurchases()
                            }
                        } label: {
                            Text(String(localized: "Restore Purchases"))
                                .font(.system(size: DesignSystem.Typography.subheadline))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: purchaseManager.isLoading)
                .padding(.horizontal, DesignSystem.Padding.xl3)
                .padding(.bottom, DesignSystem.Padding.xl2)
            }
            
        }
        .frame(width: 520, height: 420)
        .background(.background, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous))
        .overlay(alignment: .top) {
            // Error toast overlay at top - doesn't affect layout
            if let errorMessage = purchaseManager.errorMessage {
                ErrorToast(
                    message: errorMessage,
                    isVisible: $showErrorToast,
                    onDismiss: dismissErrorToast
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Load product price when view appears
            Task {
                await purchaseManager.loadProductPrice()
            }
        }
        .onChange(of: purchaseManager.errorMessage) { oldValue, newValue in
            if let newMessage = newValue {
                // If already showing an error, dismiss it first (even if same message)
                if showErrorToast {
                    // Dismiss current toast
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showErrorToast = false
                    }
                    // Wait for dismiss animation, then show new error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showErrorToast = true
                    }
                } else {
                    // No toast showing, show immediately
                    showErrorToast = true
                }
            } else {
                // Error cleared, dismiss toast
                dismissErrorToast()
            }
        }
        .onChange(of: purchaseManager.isPurchased) { oldValue, newValue in
            if newValue {
                onDismiss?()
                dismiss()
            }
        }
    }
    
    private var appIcon: some View {
        Group {
            if let icon = NSApplication.shared.applicationIconImage {
                ZStack {
                    // Colored background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .blue.opacity(0.2),
                                    .purple.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)
                    
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 6)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .blue.opacity(0.2),
                                    .purple.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)
                    
                    Image(systemName: "video.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .background {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xlarge, style: .continuous)
                                .fill(.regularMaterial)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                }
            }
        }
    }
    
    private var processingView: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            SafeProgressView(controlSize: .small)
            
            Text(String(localized: "Processing…"))
                .font(.system(size: DesignSystem.Typography.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func dismissErrorToast() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showErrorToast = false
        }
        // Clear error message after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            purchaseManager.errorMessage = nil
        }
    }
}

