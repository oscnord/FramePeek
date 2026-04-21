import Foundation
import SwiftUI
import FramePeekCore

/// Shared manager to track the active ViewModel for the video player window
@MainActor
@Observable
final class PlayerViewModelManager {
    static let shared = PlayerViewModelManager()

    var activeViewModel: FramePeekViewModel?
    var seekTime: Double?

    /// Throttled playback time for chart RuleMarks and other heavy views.
    /// Only updates when time changes by ≥ `playbackTimeThreshold` seconds,
    /// preventing expensive chart redraws on every 0.1s tick.
    var currentPlaybackTime: Double?

    /// High-frequency playback time updated on every AVPlayer tick (0.1s).
    /// Use this for lightweight consumers (overlays, timecodes) that need
    /// precise tracking without triggering chart invalidation.
    @ObservationIgnored var precisePlaybackTime: Double?

    /// Minimum change in seconds before `currentPlaybackTime` is updated.
    @ObservationIgnored private let playbackTimeThreshold: Double = 0.2

    @ObservationIgnored private var seekClearTask: Task<Void, Never>?

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
                try await Task.sleep(for: .milliseconds(100))
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
        precisePlaybackTime = time

        // Only propagate to the observed property when the change is visually meaningful
        if let current = currentPlaybackTime {
            if abs(time - current) >= playbackTimeThreshold {
                currentPlaybackTime = time
            }
        } else {
            currentPlaybackTime = time
        }
    }
}
