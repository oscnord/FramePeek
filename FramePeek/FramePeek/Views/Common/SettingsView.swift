//
//  SettingsView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showInspector") private var showInspector: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 20)
            }
            .padding(.bottom, 24)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Appearance section
                    SettingsSection(title: "Appearance") {
                        VStack(alignment: .leading, spacing: 16) {
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Interface section
                    SettingsSection(title: "Interface") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show Inspector by Default", isOn: $showInspector)
                                .font(.system(size: 14, weight: .medium))
                            
                            Text("When enabled, the inspector panel will be visible when you open a new file.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 40)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 500)
        .background(.background)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            content
                .padding(.leading, 4)
        }
    }
}

#Preview {
    SettingsView()
}

