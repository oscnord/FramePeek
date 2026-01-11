import Foundation
import SwiftUI

/// Shared manager to track the active ViewModel for the video player window
@MainActor
final class PlayerViewModelManager: ObservableObject {
    static let shared = PlayerViewModelManager()
    
    @Published var activeViewModel: FramePeekViewModel?
    @Published var seekTime: Double? = nil
    @Published var currentPlaybackTime: Double? = nil
    
    private init() {}
    
    func setActiveViewModel(_ viewModel: FramePeekViewModel?) {
        activeViewModel = viewModel
    }
    
    func seekToTime(_ time: Double) {
        seekTime = time
        // Clear after a short delay to allow re-seeking
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            seekTime = nil
        }
    }
    
    func updatePlaybackTime(_ time: Double) {
        currentPlaybackTime = time
        // Also update the active view model
        activeViewModel?.currentPlaybackTime = time
    }
}


