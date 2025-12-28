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
            Spacer()
            
            // Header with app icon and name
            VStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                
                VStack(spacing: 4) {
                    Text("FramePeek")
                        .font(.system(size: 24, weight: .bold, design: .default))
                    
                    if let version = appVersion {
                        Text(String(format: String(localized: "Version %@"), version))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let buildNumber = buildNumber {
                        Text(String(format: String(localized: "Build %@"), buildNumber))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 4) {
                Text("Built by Oscar Nord in Stockholm, Sweden")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                
                if let copyright = copyrightText {
                    Text(copyright)
                        .font(.system(size: 9))
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
        .frame(width: 320, height: 320)
        .background(.background)
    }
    
    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ??
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    private var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    private var copyrightText: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }
}


#Preview {
    AboutView()
}

