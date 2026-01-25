import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            // Sidebar with tabs
            VStack(spacing: DesignSystem.Spacing.sm) {
                List(selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.displayName, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .listRowInsets(EdgeInsets(
                    top: 4,
                    leading: DesignSystem.Padding.md,
                    bottom: 4,
                    trailing: DesignSystem.Padding.md
                ))
            }
            .navigationTitle("Settings")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView()
                        case .analysis:
                            AnalysisSettingsView()
                        case .playbackDisplay:
                            PlaybackDisplaySettingsView()
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.xxl2)
                .padding(.top, DesignSystem.Padding.xxl)
                .padding(.bottom, DesignSystem.Padding.xl2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SettingsView()
}
