import SwiftUI
import AVFoundation
import AppKit
import FramePeekCore

struct VideoPreviewView: View {
    @ObservedObject var viewModel: FramePeekViewModel
    @Environment(\.openWindow) private var openWindow

    @State private var thumbnailImage: NSImage?
    @State private var isHovering: Bool = false

    // Calculate aspect ratio from resolution string (e.g., "1920x1080")
    private var aspectRatio: CGFloat? {
        guard let info = viewModel.extendedInfo else { return nil }
        let components = info.resolution.split(separator: "x")
        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]),
              width > 0, height > 0 else {
            return nil
        }
        return width / height
    }

    var body: some View {
        Group {
            if let videoURL = viewModel.currentVideoURL {
                ZStack {
                    // Thumbnail image
                    if let image = thumbnailImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(aspectRatio ?? 16/9, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                    } else {
                        // Loading placeholder
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .fill(DesignSystem.Materials.thin)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    }

                    // Video player indicator and hover overlay
                    ZStack {
                        // Dark overlay on hover
                        if isHovering {
                            Color.black.opacity(0.4)
                        }

                        // Play icon (always visible, more prominent on hover)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: isHovering ? 32 : 24))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .animation(.easeInOut(duration: 0.2), value: isHovering)

                        // Enlarge icon on hover
                        if isHovering {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(6)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                        .padding(8)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio ?? 16/9, contentMode: .fit)
                .border(DesignSystem.Colors.Semantic.secondary.opacity(0.2), width: DesignSystem.Borders.thin)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .onHover { hovering in
                    isHovering = hovering
                }
                .onTapGesture {
                    // Open full player window
                    PlayerViewModelManager.shared.setActiveViewModel(viewModel)
                    openWindow(id: "videoPlayer")
                }
                .onAppear {
                    loadThumbnail(url: videoURL)
                }
                .onChange(of: viewModel.currentVideoURL) { oldValue, newValue in
                    if let newURL = newValue, newURL != oldValue {
                        loadThumbnail(url: newURL)
                    } else if newValue == nil {
                        thumbnailImage = nil
                    }
                }
            } else {
                // Placeholder when no video
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .fill(DesignSystem.Materials.thin)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fit) // Default aspect ratio
                    .overlay {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "play.rectangle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("No video loaded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }

    private func loadThumbnail(url: URL) {
        thumbnailImage = nil

        Task {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 300)

            // Get thumbnail from a few seconds in to avoid black frames
            // Try to get the third frame or at least 2-3 seconds in
            let duration = (try? await asset.load(.duration).seconds) ?? 0

            // Get frame rate to calculate third frame time
            var frameRate: Double = 30.0 // Default to 30 fps
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
               let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate) {
                frameRate = Double(nominalFrameRate)
            }

            // Calculate time for third frame (or at least 2 seconds in, whichever is smaller)
            let thirdFrameTime = 2.0 / frameRate // Time for third frame
            let minTime = min(2.0, duration * 0.1) // At least 2 seconds or 10% of duration
            let time = duration > 0 ? CMTime(seconds: max(thirdFrameTime, minTime), preferredTimescale: 600) : CMTime(seconds: 0.1, preferredTimescale: 600)

            do {
                let cgImage = try await imageGenerator.image(at: time).image
                let nsImage = NSImage(cgImage: cgImage, size: .zero)
                await MainActor.run {
                    thumbnailImage = nsImage
                }
            } catch {
                // Failed to generate thumbnail, leave as nil
            }
        }
    }
}
