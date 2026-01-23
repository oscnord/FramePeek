import Foundation
import SwiftUI

/// Shared manager to track the active ViewModel for the video player window
@MainActor
final class PlayerViewModelManager: ObservableObject {
    static let shared = PlayerViewModelManager()

    @Published var activeViewModel: FramePeekViewModel?
    @Published var seekTime: Double?
    @Published var currentPlaybackTime: Double?

    private var seekClearTask: Task<Void, Never>?

    private init() {}

    func setActiveViewModel(_ viewModel: FramePeekViewModel?) {
        activeViewModel = viewModel
    }

    func seekToTime(_ time: Double) {
        // Cancel any pending clear task
        seekClearTask?.cancel()
        seekClearTask = nil

        seekTime = time

        // Clear after a short delay to allow re-seeking to the same time
        // This task can be cancelled if a new seek happens
        seekClearTask = Task {
            do {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                // Only clear if task wasn't cancelled
                if !Task.isCancelled {
                    seekTime = nil
                }
            } catch {
                // Task was cancelled, which is expected behavior
            }
            seekClearTask = nil
        }
    }

    func updatePlaybackTime(_ time: Double) {
        currentPlaybackTime = time
        // Also update the active view model
        activeViewModel?.currentPlaybackTime = time
    }
}
