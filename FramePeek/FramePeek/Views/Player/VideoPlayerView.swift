import SwiftUI
import AVFoundation
import AVKit
import AppKit
import QuartzCore

struct VideoPlayerView: View {
    @ObservedObject private var manager = PlayerViewModelManager.shared

    private var viewModel: FramePeekViewModel? {
        manager.activeViewModel
    }
    @AppStorage("playerAutoPlay") private var playerAutoPlay: Bool = false
    @AppStorage("playerShowControls") private var playerShowControls: Bool = true
    @AppStorage("playerShowStatistics") private var playerShowStatistics: Bool = true
    @AppStorage("playerMuted") private var playerMuted: Bool = false
    @AppStorage("statisticsOverlayOffsetX") private var savedOffsetX: Double = 0
    @AppStorage("statisticsOverlayOffsetY") private var savedOffsetY: Double = 0

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var timeObserver: Any?
    @State private var duration: Double = 0
    @State private var dragOffset: CGSize = .zero
    @State private var overlaySize: CGSize = .zero
    @State private var shouldInitializePosition: Bool = false
    @State private var hasInitializedPosition: Bool = false

    var body: some View {
        ZStack {
            if let viewModel = viewModel, let videoURL = viewModel.currentVideoURL {
                // Video player view with Apple's default controls
                AVPlayerViewRepresentable(player: player, showsControls: playerShowControls)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // Reset overlay position when opening video player
                        resetOverlayPosition()
                        // Delay setup slightly to ensure view is laid out
                        Task { @MainActor in
                            setupPlayer(url: videoURL)
                        }
                    }
                    .onDisappear {
                        cleanupPlayer()
                    }
                    .onChange(of: manager.activeViewModel?.currentVideoURL) { oldValue, newValue in
                        if let newURL = newValue, newURL != oldValue {
                            // Reset overlay position when loading new video
                            resetOverlayPosition()
                            Task { @MainActor in
                                setupPlayer(url: newURL)
                            }
                        } else if newValue == nil {
                            cleanupPlayer()
                        }
                    }
                    .onChange(of: manager.activeViewModel?.extendedInfo?.fileName) { _, _ in
                        // When ViewModel changes (tab switch), update player if URL exists
                        if let viewModel = manager.activeViewModel, let url = viewModel.currentVideoURL {
                            Task { @MainActor in
                                setupPlayer(url: url)
                            }
                        }
                    }
                    .onChange(of: playerMuted) { _, newValue in
                        // Update mute state when setting changes
                        player?.isMuted = newValue
                    }
                    .onChange(of: manager.seekTime) { _, newValue in
                        // Handle seek request
                        if let seekTime = newValue, let player = player {
                            let time = CMTime(seconds: seekTime, preferredTimescale: 600)
                            player.seek(to: time)
                        }
                    }

                // Statistics overlay
                if playerShowStatistics {
                    GeometryReader { geometry in
                        statisticsOverlay
                            .background(
                                GeometryReader { overlayGeometry in
                                    Color.clear
                                        .onAppear {
                                            overlaySize = overlayGeometry.size
                                            initializePositionIfNeeded(geometry: geometry, overlaySize: overlayGeometry.size)
                                        }
                                        .onChange(of: overlayGeometry.size) { _, newValue in
                                            overlaySize = newValue
                                            initializePositionIfNeeded(geometry: geometry, overlaySize: newValue)
                                        }
                                }
                            )
                            .contentShape(Rectangle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(.leading, DesignSystem.Padding.lg)
                            .padding(.bottom, DesignSystem.Padding.xl3)
                            .offset(
                                x: savedOffsetX + dragOffset.width,
                                y: savedOffsetY + dragOffset.height
                            )
                            .highPriorityGesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        // Calculate new offset (relative to bottom-left anchor with padding)
                                        let newOffsetX = savedOffsetX + value.translation.width
                                        let newOffsetY = savedOffsetY + value.translation.height

                                        // Calculate bounds (accounting for padding)
                                        let horizontalPadding = DesignSystem.Padding.lg
                                        let bottomPadding = DesignSystem.Padding.xl2
                                        let padding = DesignSystem.Padding.lg

                                        // Minimum position: can't go further left/up than the default position
                                        let minOffsetX = -horizontalPadding
                                        let minOffsetY = -(geometry.size.height - overlaySize.height - bottomPadding - padding)

                                        // Maximum position: can't go further right/down than the opposite corner
                                        let maxOffsetX = geometry.size.width - overlaySize.width - horizontalPadding
                                        let maxOffsetY = -bottomPadding

                                        // Check if position is outside visible bounds
                                        let isOutsideBounds = newOffsetX < minOffsetX || newOffsetX > maxOffsetX ||
                                                             newOffsetY < minOffsetY || newOffsetY > maxOffsetY

                                        if isOutsideBounds {
                                            // Reset to default position if dragged out of view
                                            savedOffsetX = 0
                                            savedOffsetY = 0
                                        } else {
                                            // Keep the constrained position
                                            savedOffsetX = max(minOffsetX, min(maxOffsetX, newOffsetX))
                                            savedOffsetY = max(minOffsetY, min(maxOffsetY, newOffsetY))
                                        }

                                        dragOffset = .zero
                                    }
                            )
                    }
                }
            } else {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.lg) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No video loaded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(viewModel?.extendedInfo?.fileName ?? "Video Player")
    }

    // MARK: - Statistics Overlay

    private var statisticsOverlay: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let viewModel = viewModel, let info = viewModel.extendedInfo {
                // Resolution
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "rectangle")
                        .font(.caption)
                    Text(info.resolution)
                        .font(.caption)
                        .monospacedDigit()
                }

                // Frame rate
                if !info.frameRate.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "gauge")
                            .font(.caption)
                        Text(info.frameRate)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }

            // Current time
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(formatTime(currentTime))
                    .font(.caption)
                    .monospacedDigit()
                if duration > 0 {
                    Text("/ \(formatTime(duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Current bitrate
            if let viewModel = viewModel, let bitrate = getBitrateAtTime(currentTime, samples: viewModel.samples) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "speedometer")
                        .font(.caption)
                    Text(formatBitrate(bitrate))
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            // Color analysis stats
            if let viewModel = viewModel, let colorSample = getColorSampleAtTime(currentTime, samples: viewModel.colorSamples) {
                // Brightness
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "sun.max")
                        .font(.caption)
                    Text(String(format: "%.1f%%", colorSample.brightness * 100))
                        .font(.caption)
                        .monospacedDigit()
                }

                // Color temperature
                if let temperature = colorSample.colorTemperature {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "thermometer")
                            .font(.caption)
                        Text(String(format: "%.0f K", temperature))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(DesignSystem.Padding.md)
        .liquidGlassBackground(in: .rect(cornerRadius: DesignSystem.CornerRadius.medium))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
    }

    // MARK: - Overlay Position

    private func resetOverlayPosition() {
        savedOffsetX = 0
        savedOffsetY = 0
        dragOffset = .zero
        shouldInitializePosition = true
        hasInitializedPosition = false
    }

    private func initializePositionIfNeeded(geometry: GeometryProxy, overlaySize: CGSize) {
        // Only initialize if we explicitly need to reset, or if we've never initialized before
        guard shouldInitializePosition || !hasInitializedPosition,
              overlaySize.width > 0 && overlaySize.height > 0,
              geometry.size.width > 0 && geometry.size.height > 0 else {
            return
        }

        // With frame alignment at bottom-leading, offsets are relative to that position
        // Default position is already at bottom-left via frame alignment, so offsets start at 0
        // Only set non-zero offsets if we have saved values from AppStorage
        if shouldInitializePosition {
            // Reset to default (bottom-left with padding)
            savedOffsetX = 0
            savedOffsetY = 0
        }

        shouldInitializePosition = false
        hasInitializedPosition = true
    }

    // MARK: - Player Setup

    private func setupPlayer(url: URL) {
        cleanupPlayer()

        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer

        // Load duration
        Task {
            if let duration = try? await newPlayer.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(duration)
                }
            }
        }

        // Observe time updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak newPlayer] time in
            guard let player = newPlayer else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                currentTime = seconds
                // Update PlayerViewModelManager with current playback time
                Task { @MainActor in
                    PlayerViewModelManager.shared.updatePlaybackTime(seconds)
                }
            }
            isPlaying = player.rate > 0
        }

        // Set mute state
        newPlayer.isMuted = playerMuted

        // Auto-play if enabled
        if playerAutoPlay {
            newPlayer.play()
        }
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        currentTime = 0
        isPlaying = false
        duration = 0
    }

    // MARK: - Helper Functions

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func formatBitrate(_ bitrate: Double) -> String {
        let kbps = bitrate / 1000.0
        return String(format: "%.0f kb/s", kbps)
    }

    /// Finds the bitrate at a given time by finding the nearest sample or interpolating
    private func getBitrateAtTime(_ time: Double, samples: [BitrateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }

        // Find the sample that contains this time
        // Samples have a time (end of window) and duration (window size)
        for sample in samples {
            let windowStart = sample.time - sample.duration
            let windowEnd = sample.time

            if time >= windowStart && time <= windowEnd {
                return sample.bitrate
            }
        }

        // Use generic interpolation helper
        return interpolateValue(
            at: time,
            in: samples,
            timeKeyPath: \.time,
            valueKeyPath: \.bitrate
        )
    }

    /// Finds the color sample at a given time by finding the nearest sample or interpolating
    private func getColorSampleAtTime(_ time: Double, samples: [ColorSample]) -> ColorSample? {
        guard !samples.isEmpty else { return nil }

        let sortedSamples = samples.sorted { $0.time < $1.time }

        // Before first sample
        if time <= sortedSamples.first?.time ?? 0 {
            return sortedSamples.first
        }

        // After last sample
        if time >= sortedSamples.last?.time ?? 0 {
            return sortedSamples.last
        }

        // Find two samples to interpolate between
        guard let (sample1, sample2, t) = findInterpolationPair(at: time, in: sortedSamples, timeKeyPath: \.time) else {
            return nil
        }

        // Interpolate brightness
        let interpolatedBrightness = linearInterpolate(sample1.brightness, sample2.brightness, t: t)

        // Interpolate color temperature if both samples have it
        let interpolatedTemperature: Double?
        if let temp1 = sample1.colorTemperature, let temp2 = sample2.colorTemperature {
            interpolatedTemperature = linearInterpolate(temp1, temp2, t: t)
        } else {
            interpolatedTemperature = sample1.colorTemperature ?? sample2.colorTemperature
        }

        return ColorSample(
            time: time,
            brightness: interpolatedBrightness,
            colorTemperature: interpolatedTemperature,
            histogram: nil
        )
    }
}

// MARK: - Interpolation Helpers

/// Performs linear interpolation between two values
private func linearInterpolate(_ v1: Double, _ v2: Double, t: Double) -> Double {
    v1 + (v2 - v1) * t
}

/// Finds two adjacent samples for interpolation and returns them with the interpolation factor
private func findInterpolationPair<T>(
    at time: Double,
    in sortedSamples: [T],
    timeKeyPath: KeyPath<T, Double>
) -> (T, T, Double)? {
    for i in 0..<sortedSamples.count - 1 {
        let sample1 = sortedSamples[i]
        let sample2 = sortedSamples[i + 1]
        let time1 = sample1[keyPath: timeKeyPath]
        let time2 = sample2[keyPath: timeKeyPath]

        if time >= time1 && time <= time2 {
            let t = (time - time1) / (time2 - time1)
            return (sample1, sample2, t)
        }
    }
    return nil
}

/// Generic interpolation for samples with time and a numeric value
private func interpolateValue<T>(
    at time: Double,
    in samples: [T],
    timeKeyPath: KeyPath<T, Double>,
    valueKeyPath: KeyPath<T, Double>
) -> Double? {
    let sortedSamples = samples.sorted { $0[keyPath: timeKeyPath] < $1[keyPath: timeKeyPath] }

    // Before first sample
    if time < sortedSamples.first?[keyPath: timeKeyPath] ?? 0 {
        return sortedSamples.first?[keyPath: valueKeyPath]
    }

    // After last sample
    if time > sortedSamples.last?[keyPath: timeKeyPath] ?? 0 {
        return sortedSamples.last?[keyPath: valueKeyPath]
    }

    // Find pair and interpolate
    guard let (sample1, sample2, t) = findInterpolationPair(at: time, in: sortedSamples, timeKeyPath: timeKeyPath) else {
        return nil
    }

    return linearInterpolate(sample1[keyPath: valueKeyPath], sample2[keyPath: valueKeyPath], t: t)
}

// MARK: - AVPlayerView Wrapper (using Apple's default controls)

struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer?
    let showsControls: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = showsControls ? .inline : .none
        playerView.videoGravity = .resizeAspect

        // Set player after view is laid out to avoid constraint warnings
        // AVPlayerView has internal constraints that need the view to have bounds first
        Task { @MainActor in
            playerView.player = player
        }

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Update controls style synchronously (safe, doesn't trigger layout)
        let newControlsStyle: AVPlayerViewControlsStyle = showsControls ? .inline : .none
        if nsView.controlsStyle != newControlsStyle {
            nsView.controlsStyle = newControlsStyle
        }

        // Update player asynchronously to avoid constraint conflicts during layout
        // Only update if player actually changed
        if nsView.player !== player {
            Task { @MainActor in
                nsView.player = player
            }
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        // Clean up player when view is removed
        nsView.player = nil
    }
}
