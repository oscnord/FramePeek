//
//  TabBarView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabManager.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTabId,
                            onSelect: {
                                tabManager.switchToTab(id: tab.id)
                            },
                            onClose: {
                                tabManager.removeTab(id: tab.id)
                            }
                        )
                    }
                }
                .padding(.leading, 8)
            }
            
            // Add new tab button
            Button {
                tabManager.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "New Tab"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 26)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) {
            // Native tab bar separator
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5)
        }
    }
}

struct TabButton: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(tab.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                // Close button - only show on hover or when selected
                if isHovered || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minWidth: 80, maxWidth: 180)
            .background(
                Group {
                    if isSelected {
                        // Selected tab - matches window background for native look
                        Color(NSColor.windowBackgroundColor)
                    } else if isHovered {
                        // Hovered tab - very subtle background
                        Color(NSColor.controlBackgroundColor).opacity(0.3)
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    // Native selection indicator - accent color line at bottom
                    Rectangle()
                        .fill(Color(NSColor.controlAccentColor))
                        .frame(height: 2.5)
                        .offset(y: 0.25)
                }
            }
            .overlay(alignment: .top) {
                // Top border for selected tab to separate from window chrome
                if isSelected {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 0.5)
                        .offset(y: -0.25)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    TabBarView(tabManager: TabManager())
        .frame(width: 800)
}

