//
//  AboutView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-02-15.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with app icon and name
            VStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                VStack(spacing: 4) {
                    Text("FramePeek")
                        .font(.system(size: 32, weight: .bold, design: .default))
                    
                    if let version = appVersion {
                        Text(String(format: String(localized: "Version %@"), version))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 30)
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Description
                VStack(spacing: 16) {
                    Text("A macOS application for inspecting video and audio files")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: String(localized: "Bitrate Analysis"),
                            description: String(localized: "Per-frame bitrate visualization with interactive charts")
                        )
                        
                        FeatureRow(
                            icon: "info.circle.fill",
                            title: String(localized: "Rich Metadata"),
                            description: String(localized: "Detailed video and audio track information")
                        )
                        
                        FeatureRow(
                            icon: "photo.on.rectangle",
                            title: String(localized: "Keyframe Detection"),
                            description: String(localized: "Visualize keyframes with thumbnails and timeline")
                        )
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // Footer
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 40)
                    
                    Text("Built by Oscar Nord in Stockholm, Sweden")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    if let copyright = copyrightText {
                        Text(copyright)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)
                }
                .padding(.bottom, 24)
        }
        .frame(width: 500, height: 600)
        .background(.background)
    }
    
    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ??
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    private var copyrightText: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    AboutView()
}

