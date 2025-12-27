//
//  TabManager.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import SwiftUI

struct TabItem: Identifiable {
    let id: UUID
    let viewModel: FramePeekViewModel
    var displayName: String // filename or "Untitled"
}

@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var selectedTabId: UUID?
    
    var currentTab: TabItem? {
        guard let selectedTabId = selectedTabId else { return nil }
        return tabs.first { $0.id == selectedTabId }
    }
    
    var currentViewModel: FramePeekViewModel? {
        currentTab?.viewModel
    }
    
    init() {
        // Start with one empty tab
        addTab()
    }
    
    func addTab() {
        let id = UUID()
        let viewModel = FramePeekViewModel()
        let tab = TabItem(id: id, viewModel: viewModel, displayName: "Untitled")
        tabs.append(tab)
        selectedTabId = id
    }
    
    func removeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        let viewModel = tabs[index].viewModel
        
        // Cancel any in-progress analysis and clear all data
        viewModel.cancelAnalysis()
        viewModel.reset() // Clear all loaded data (samples, keyframes, thumbnails, etc.)
        
        // Remove the tab - this will deallocate the viewModel
        tabs.remove(at: index)
        
        // If we removed the selected tab, select another one
        if selectedTabId == id {
            if tabs.isEmpty {
                // Create a new empty tab if we removed the last one
                addTab()
            } else {
                // Select the tab at the same index, or the last tab if we removed the last one
                let newIndex = min(index, tabs.count - 1)
                selectedTabId = tabs[newIndex].id
            }
        }
    }
    
    func switchToTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabId = id
    }
    
    func updateTabDisplayName(id: UUID, name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].displayName = name
    }
    
    func getTabIndex(id: UUID) -> Int? {
        tabs.firstIndex(where: { $0.id == id })
    }
    
    func getNextTabId(from id: UUID) -> UUID? {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == id }),
              currentIndex < tabs.count - 1 else {
            return tabs.first?.id
        }
        return tabs[currentIndex + 1].id
    }
    
    func getPreviousTabId(from id: UUID) -> UUID? {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == id }),
              currentIndex > 0 else {
            return tabs.last?.id
        }
        return tabs[currentIndex - 1].id
    }
    
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
    
    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0 && sourceIndex < tabs.count,
              destinationIndex >= 0 && destinationIndex <= tabs.count else {
            return
        }
        
        let tab = tabs.remove(at: sourceIndex)
        let insertIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(tab, at: insertIndex)
    }
}

