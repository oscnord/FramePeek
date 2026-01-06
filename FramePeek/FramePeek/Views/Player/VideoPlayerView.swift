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
    
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var timeObserver: Any?
    @State private var duration: Double = 0
    
    var body: some View {
        ZStack {
            if let viewModel = viewModel, let videoURL = viewModel.currentVideoURL {
                // Video player view with Apple's default controls
                AVPlayerViewRepresentable(player: player, showsControls: playerShowControls)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // Delay setup slightly to ensure view is laid out
                        DispatchQueue.main.async {
                            setupPlayer(url: videoURL)
                        }
                    }
                    .onDisappear {
                        cleanupPlayer()
                    }
                    .onChange(of: manager.activeViewModel?.currentVideoURL) { oldValue, newValue in
                        if let newURL = newValue, newURL != oldValue {
                            DispatchQueue.main.async {
                                setupPlayer(url: newURL)
                            }
                        } else if newValue == nil {
                            cleanupPlayer()
                        }
                    }
                    .onChange(of: manager.activeViewModel?.extendedInfo?.fileName) { oldValue, newValue in
                        // When ViewModel changes (tab switch), update player if URL exists
                        if let viewModel = manager.activeViewModel, let url = viewModel.currentVideoURL {
                            DispatchQueue.main.async {
                                setupPlayer(url: url)
                            }
                        }
                    }
                
                // Statistics overlay
                if playerShowStatistics {
                    VStack {
                        Spacer()
                        HStack {
                            statisticsOverlay
                                .padding(DesignSystem.Padding.lg)
                            Spacer()
                        }
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
        }
        .padding(DesignSystem.Padding.md)
        .liquidGlassBackground(in: .rect(cornerRadius: DesignSystem.CornerRadius.medium))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
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
            }
            isPlaying = player.rate > 0
        }
        
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
        
        // If not found, find nearest samples and interpolate
        let sortedSamples = samples.sorted { $0.time < $1.time }
        
        // Before first sample
        if time < sortedSamples.first?.time ?? 0 {
            return sortedSamples.first?.bitrate
        }
        
        // After last sample
        if time > sortedSamples.last?.time ?? 0 {
            return sortedSamples.last?.bitrate
        }
        
        // Find two samples to interpolate between
        for i in 0..<sortedSamples.count - 1 {
            let sample1 = sortedSamples[i]
            let sample2 = sortedSamples[i + 1]
            
            if time >= sample1.time && time <= sample2.time {
                // Linear interpolation
                let t = (time - sample1.time) / (sample2.time - sample1.time)
                return sample1.bitrate + (sample2.bitrate - sample1.bitrate) * t
            }
        }
        
        return nil
    }
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
        DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                nsView.player = player
            }
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        // Clean up player when view is removed
        nsView.player = nil
    }
}

