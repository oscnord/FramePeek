import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("fileOpeningBehavior") private var fileOpeningBehavior: FileOpeningBehavior = .prompt

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Appearance") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    Picker("", selection: Binding(
                        get: { appearanceMode },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                appearanceMode = newValue
                            }
                        }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Choose how FramePeek should appear. 'System' follows your Mac's appearance setting.")
                        .font(.system(size: DesignSystem.Typography.footnote))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }

            SettingsSection(title: "Interface") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        HStack {
                            Text("File Opening Behavior")
                                .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                            Spacer()
                            Picker("", selection: $fileOpeningBehavior) {
                                ForEach(FileOpeningBehavior.allCases) { behavior in
                                    Text(behavior.displayName).tag(behavior)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        Text("Choose what happens when you open a file while another file is already open in the current tab.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
        }
    }
}
