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

    // Section visibility settings (all expanded by default)
    @AppStorage("overlayShowVideo") private var showVideoSection: Bool = true
    @AppStorage("overlayShowPlayback") private var showPlaybackSection: Bool = true
    @AppStorage("overlayShowAudio") private var showAudioSection: Bool = true
    @AppStorage("overlayShowAnalysis") private var showAnalysisSection: Bool = true

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var timeObserver: Any?
    @State private var duration: Double = 0
    @State private var dragOffset: CGSize = .zero
    @State private var overlaySize: CGSize = .zero
    @State private var shouldInitializePosition: Bool = false
    @State private var hasInitializedPosition: Bool = false

    // Section expansion state
    @State private var videoSectionExpanded: Bool = true
    @State private var playbackSectionExpanded: Bool = true
    @State private var audioSectionExpanded: Bool = true
    @State private var analysisSectionExpanded: Bool = true

    // Selected audio track (0-based index, updated when player selection changes)
    @State private var selectedAudioTrackIndex: Int = 0

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
                            .fixedSize()
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
            // Video Section
            if showVideoSection {
                videoSection
            }

            // Playback Section
            if showPlaybackSection {
                playbackSection
            }

            // Audio Section
            if showAudioSection {
                audioSection
            }

            // Analysis Section
            if showAnalysisSection {
                analysisSection
            }
        }
        .padding(DesignSystem.Padding.md)
        .liquidGlassBackground(in: .rect(cornerRadius: DesignSystem.CornerRadius.medium))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
        .contextMenu {
            sectionToggleMenu
        }
    }

    // MARK: - Video Section

    @ViewBuilder
    private var videoSection: some View {
        OverlaySectionView(
            title: String(localized: "Video"),
            systemImage: "film",
            isExpanded: $videoSectionExpanded
        ) {
            if let info = viewModel?.extendedInfo {
                // Resolution + Codec line
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(info.resolution)
                        .font(.caption)
                        .monospacedDigit()
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(info.codec)
                        .font(.caption)
                    if let profile = info.codecProfile {
                        Text(profile)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Frame rate + mode
                if !info.frameRate.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(info.frameRate)
                            .font(.caption)
                            .monospacedDigit()
                        if let mode = info.frameRateMode {
                            Text("(\(mode))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Bit depth + chroma
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let bitDepth = info.bitDepth {
                        Text(bitDepth)
                            .font(.caption)
                    }
                    if let chroma = info.chromaSubsampling {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(chroma)
                            .font(.caption)
                    }
                }

                // HDR + Color info badges
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let hdr = info.hdrFormat, !hdr.isEmpty {
                        OverlayBadgeRow(text: hdr, color: .purple)
                    }
                    if info.isWideGamut, let primaries = info.colorPrimaries {
                        OverlayBadgeRow(text: primaries, color: .cyan)
                    }
                }
            }
        }
    }

    // MARK: - Playback Section

    @ViewBuilder
    private var playbackSection: some View {
        OverlaySectionView(
            title: String(localized: "Playback"),
            systemImage: "play.circle",
            isExpanded: $playbackSectionExpanded
        ) {
            // Current time / Duration / Remaining
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .monospacedDigit()
                if duration > 0 {
                    Text("/")
                        .foregroundStyle(.tertiary)
                    Text(formatTime(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("(-\(formatTime(duration - currentTime)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            // Frame number + SMPTE timecode
            if let info = viewModel?.extendedInfo, let fps = info.nominalFrameRate, fps > 0 {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // Frame number
                    let frameNumber = Int(currentTime * fps)
                    let totalFrames = Int(duration * fps)
                    Text(String(localized: "Frame"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(frameNumber.formatted())")
                        .font(.caption)
                        .monospacedDigit()
                    if totalFrames > 0 {
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Text("\(totalFrames.formatted())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                // SMPTE Timecode
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("TC:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatSMPTETimecode(currentTime, fps: fps))
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            // Bitrate sparkline + current value
            if let viewModel = viewModel, !viewModel.samples.isEmpty {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    BitrateSparklineView(
                        samples: viewModel.samples,
                        currentTime: currentTime,
                        windowSeconds: 15,
                        width: 70,
                        height: 18
                    )

                    if let bitrate = getBitrateAtTime(currentTime, samples: viewModel.samples) {
                        Text(formatBitrateMbps(bitrate))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Audio Section

    @ViewBuilder
    private var audioSection: some View {
        OverlaySectionView(
            title: String(localized: "Audio"),
            systemImage: "speaker.wave.2",
            isExpanded: $audioSectionExpanded
        ) {
            if let info = viewModel?.extendedInfo, !info.audioTracks.isEmpty {
                // Get the currently selected audio track (fallback to first if index out of bounds)
                let trackIndex = min(selectedAudioTrackIndex, info.audioTracks.count - 1)
                let audioTrack = info.audioTracks[trackIndex]

                // Track indicator (if multiple tracks)
                if info.audioTracks.count > 1 {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(String(localized: "Track"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(trackIndex + 1)/\(info.audioTracks.count)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }

                // Audio track info
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(audioTrack.codecDisplayName)
                        .font(.caption)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(audioTrack.channelLayout)
                        .font(.caption)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(formatSampleRate(audioTrack.sampleRateHz))
                        .font(.caption)
                        .monospacedDigit()
                }

                // Bitrate + language
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let bitrate = audioTrack.bitrateKbps {
                        Text("\(Int(bitrate)) kbps")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    if let lang = audioTrack.languageCode, lang != "und" {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(formatLanguage(lang))
                            .font(.caption)
                    }
                }

                // Audio level meter (if waveform data available for this track)
                // Note: waveformData is keyed by audioTrack.index, not array position
                if let viewModel = viewModel,
                   let waveformSamples = viewModel.waveformData[audioTrack.index],
                   let amplitude = getAmplitudeAtTime(currentTime, samples: waveformSamples) {
                    AudioLevelMeterView(
                        amplitude: amplitude,
                        width: 70,
                        height: 6,
                        showDecibels: true
                    )
                }
            } else {
                Text(String(localized: "No audio"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Analysis Section

    @ViewBuilder
    private var analysisSection: some View {
        OverlaySectionView(
            title: String(localized: "Analysis"),
            systemImage: "waveform.badge.magnifyingglass",
            isExpanded: $analysisSectionExpanded
        ) {
            // GOP info + frame type timeline
            if let viewModel = viewModel, let gopAnalysis = viewModel.gopAnalysis, !gopAnalysis.segments.isEmpty {
                // GOP position row
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("GOP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let (gopIndex, totalGOPs) = getGOPAtTime(currentTime, analysis: gopAnalysis) {
                        Text("\(gopIndex + 1)/\(totalGOPs)")
                            .font(.caption)
                            .monospacedDigit()
                    } else {
                        Text("-/-")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }

                    // Current frame type badge (with fixed width to prevent jumping)
                    if let frameType = getFrameTypeAtTime(currentTime, analysis: gopAnalysis) {
                        FrameTypeBadge(frameType: frameType)
                    } else {
                        // Reserve space for badge
                        Text("?")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    }
                }

                // Frame type timeline (rolling visualization)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        FrameTypeTimelineView(
                            segments: gopAnalysis.segments,
                            currentTime: currentTime,
                            windowSeconds: 10,
                            width: 80,
                            height: 16,
                            representativeGOP: gopAnalysis.representativeGOP,
                            structureType: gopAnalysis.structureType,
                            videoDuration: duration > 0 ? duration : nil
                        )
                        FrameTypeLegend()
                    }

                    // Show indicator when using extrapolated/predicted pattern
                    if gopAnalysis.structureType.isFixed {
                        Text(String(localized: "~ Constant GOP pattern"))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // A/V Sync status
            if let viewModel = viewModel, let syncResult = viewModel.syncAnalysisResult {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(String(localized: "Sync:"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SyncStatusIndicator(
                        status: syncResult.overallSyncStatus,
                        offsetMs: syncResult.primaryTrackSyncOffsetMs,
                        showLabel: true
                    )

                    // VFR warning
                    if syncResult.isVariableFrameRate {
                        OverlayBadgeRow(text: "VFR", color: .orange)
                    }
                }
            }

            // Luminance and color temperature display
            if let viewModel = viewModel,
               let analysis = viewModel.frameAnalysisAtTime(currentTime) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Luminance percentage
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f%%", analysis.luminance.average * 100))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    
                    // CCT if available
                    if let cct = analysis.colorTemperature?.cct {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0fK", cct))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            } else if let viewModel = viewModel, let colorSample = getColorSampleAtTime(currentTime, samples: viewModel.colorSamples) {
                // Fallback to legacy brightness/temperature if no professional analysis
                HStack(spacing: DesignSystem.Spacing.md) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f%%", colorSample.brightness * 100))
                            .font(.caption)
                            .monospacedDigit()
                    }

                    if let temperature = colorSample.colorTemperature {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0fK", temperature))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }

            // Keyframe distance
            if let viewModel = viewModel, !viewModel.keyframeThumbs.isEmpty {
                if let (prevDistance, nextDistance) = getKeyframeDistances(currentTime, keyframes: viewModel.keyframeThumbs) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        if let prev = prevDistance {
                            Text("◀ \(String(format: "%.1fs", prev))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "key")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        if let next = nextDistance {
                            Text("\(String(format: "%.1fs", next)) ▶")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section Toggle Menu

    private var sectionToggleMenu: some View {
        Group {
            Toggle(String(localized: "Video"), isOn: $showVideoSection)
            Toggle(String(localized: "Playback"), isOn: $showPlaybackSection)
            Toggle(String(localized: "Audio"), isOn: $showAudioSection)
            Toggle(String(localized: "Analysis"), isOn: $showAnalysisSection)
            Divider()
            Button(String(localized: "Show All")) {
                showVideoSection = true
                showPlaybackSection = true
                showAudioSection = true
                showAnalysisSection = true
            }
            Button(String(localized: "Collapse All")) {
                videoSectionExpanded = false
                playbackSectionExpanded = false
                audioSectionExpanded = false
                analysisSectionExpanded = false
            }
            Button(String(localized: "Expand All")) {
                videoSectionExpanded = true
                playbackSectionExpanded = true
                audioSectionExpanded = true
                analysisSectionExpanded = true
            }
        }
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

        // Reset audio track selection
        selectedAudioTrackIndex = 0

        // Load duration and detect initial audio track
        Task {
            if let duration = try? await newPlayer.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(duration)
                }
            }

            // Get initial selected audio track index
            await updateSelectedAudioTrack()
        }

        // Observe time updates and audio track changes
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

            // Periodically check for audio track changes (user may change via system controls)
            Task { @MainActor in
                await updateSelectedAudioTrack()
            }
        }

        // Set mute state
        newPlayer.isMuted = playerMuted

        // Auto-play if enabled
        if playerAutoPlay {
            newPlayer.play()
        }
    }

    /// Updates the selected audio track index based on the player's current media selection
    private func updateSelectedAudioTrack() async {
        guard let playerItem = player?.currentItem else { return }

        do {
            let asset = playerItem.asset

            // Get the audible characteristic group
            if let group = try await asset.loadMediaSelectionGroup(for: .audible) {
                let currentSelection = playerItem.currentMediaSelection
                if let selectedOption = currentSelection.selectedMediaOption(in: group) {
                    // Find the index of the selected option
                    if let index = group.options.firstIndex(of: selectedOption) {
                        if selectedAudioTrackIndex != index {
                            selectedAudioTrackIndex = index
                        }
                    }
                }
            }
        } catch {
            // Silently ignore - some assets don't support media selection
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

    private func formatBitrateMbps(_ bitrate: Double) -> String {
        let mbps = bitrate / 1_000_000.0
        return String(format: "%.1f Mb/s", mbps)
    }

    private func formatSMPTETimecode(_ seconds: Double, fps: Double) -> String {
        let totalFrames = Int(seconds * fps)
        let roundedFPS = Int(fps.rounded())
        guard roundedFPS > 0 else { return "00:00:00:00" }

        let frames = totalFrames % roundedFPS
        let totalSeconds = totalFrames / roundedFPS
        let secs = totalSeconds % 60
        let mins = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        return String(format: "%02d:%02d:%02d:%02d", hours, mins, secs, frames)
    }

    private func formatSampleRate(_ hz: Double) -> String {
        if hz >= 1000 {
            return String(format: "%.1f kHz", hz / 1000.0)
        }
        return String(format: "%.0f Hz", hz)
    }

    private func formatLanguage(_ code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// Gets the amplitude at the current time from waveform samples
    private func getAmplitudeAtTime(_ time: Double, samples: [WaveformSample]) -> Double? {
        guard !samples.isEmpty else { return nil }

        let sortedSamples = samples.sorted { $0.time < $1.time }

        // Find closest sample
        var closestSample = sortedSamples.first!
        var minDistance = abs(closestSample.time - time)

        for sample in sortedSamples {
            let distance = abs(sample.time - time)
            if distance < minDistance {
                minDistance = distance
                closestSample = sample
            }
        }

        return closestSample.amplitude
    }

    /// Gets the current GOP index and total GOPs
    private func getGOPAtTime(_ time: Double, analysis: GOPAnalysisResult) -> (index: Int, total: Int)? {
        guard !analysis.segments.isEmpty else { return nil }

        for (index, segment) in analysis.segments.enumerated() {
            if time >= segment.startTime && time < segment.endTime {
                return (index, analysis.segments.count)
            }
        }

        // If past all segments, return last one
        if time >= (analysis.segments.last?.endTime ?? 0) {
            return (analysis.segments.count - 1, analysis.segments.count)
        }

        return nil
    }

    /// Gets the frame type at the current time
    private func getFrameTypeAtTime(_ time: Double, analysis: GOPAnalysisResult) -> FrameType? {
        guard !analysis.segments.isEmpty else { return nil }

        // Find the GOP containing this time
        for segment in analysis.segments {
            if time >= segment.startTime && time < segment.endTime {
                // Find frame within this GOP
                if let frames = segment.frames {
                    for (index, frame) in frames.enumerated() {
                        let nextFrameTime = index + 1 < frames.count ? frames[index + 1].time : segment.endTime
                        if time >= frame.time && time < nextFrameTime {
                            return frame.type
                        }
                    }
                }
                // If no frames data, assume first frame is I-frame
                if time < segment.startTime + 0.1 {
                    return .i
                }
                return nil
            }
        }

        return nil
    }

    /// Gets distances to previous and next keyframes
    private func getKeyframeDistances(_ time: Double, keyframes: [KeyframeThumbnail]) -> (prev: Double?, next: Double?)? {
        guard !keyframes.isEmpty else { return nil }

        let sortedKeyframes = keyframes.sorted { $0.time < $1.time }
        var prevDistance: Double?
        var nextDistance: Double?

        for keyframe in sortedKeyframes {
            if keyframe.time <= time {
                prevDistance = time - keyframe.time
            } else {
                nextDistance = keyframe.time - time
                break
            }
        }

        return (prevDistance, nextDistance)
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
