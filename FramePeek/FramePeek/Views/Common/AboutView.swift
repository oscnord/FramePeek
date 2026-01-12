import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.lg3) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.2), radius: DesignSystem.Shadows.small, x: 0, y: 3)
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("FramePeek")
                        .font(.system(size: DesignSystem.Typography.title2, weight: .bold, design: .default))
                    
                    if let version = appVersion {
                        Text(String(format: String(localized: "Version %@"), version))
                            .font(.system(size: DesignSystem.Typography.footnote, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                    
                    if let buildNumber = buildNumber {
                        Text(String(format: String(localized: "Build %@"), buildNumber))
                            .font(.system(size: DesignSystem.Typography.caption2, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Built by Oscar Nord in Stockholm, Sweden")
                    .font(.system(size: DesignSystem.Typography.caption2))
                    .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                
                if let copyright = copyrightText {
                    Text(copyright)
                        .font(.system(size: DesignSystem.Typography.caption))
                        .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                }
                
                Text(copyrightYear)
                    .font(.system(size: DesignSystem.Typography.caption2))
                    .foregroundStyle(DesignSystem.Colors.Semantic.tertiary)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, DesignSystem.Padding.lg)
            }
            .padding(.bottom, DesignSystem.Padding.xl2)
        }
        .frame(width: 320, height: 320)
        .background(.background)
    }
    
    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    private var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    private var copyrightText: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }
    
    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(format: "© %d", year)
    }
}


#Preview {
    AboutView()
}

