import SwiftUI

/// Overlay view that displays safe area guides on top of the video player
struct SafeAreaGuidesOverlay: View {
    let activeGuides: Set<SafeAreaGuideType>
    let videoAspectRatio: CGFloat
    
    private let guideColor = Color.red
    private let guideOpacity: CGFloat = 0.7
    private let lineWidth: CGFloat = 1.5
    private let labelFont = Font.system(size: 12, weight: .medium)
    private let crosshairSize: CGFloat = 40
    
    var body: some View {
        GeometryReader { geometry in
            let videoFrame = calculateVideoFrame(in: geometry.size)
            
            ZStack {
                // Render each active guide
                ForEach(Array(activeGuides), id: \.self) { guide in
                    guideView(for: guide, videoFrame: videoFrame, containerSize: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    /// Calculates the actual video frame within the container (accounting for letterboxing/pillarboxing)
    private func calculateVideoFrame(in containerSize: CGSize) -> CGRect {
        let containerAspect = containerSize.width / containerSize.height
        
        var videoWidth: CGFloat
        var videoHeight: CGFloat
        
        if videoAspectRatio > containerAspect {
            // Video is wider - letterboxing (black bars top/bottom)
            videoWidth = containerSize.width
            videoHeight = containerSize.width / videoAspectRatio
        } else {
            // Video is taller - pillarboxing (black bars left/right)
            videoHeight = containerSize.height
            videoWidth = containerSize.height * videoAspectRatio
        }
        
        let x = (containerSize.width - videoWidth) / 2
        let y = (containerSize.height - videoHeight) / 2
        
        return CGRect(x: x, y: y, width: videoWidth, height: videoHeight)
    }
    
    @ViewBuilder
    private func guideView(for guide: SafeAreaGuideType, videoFrame: CGRect, containerSize: CGSize) -> some View {
        switch guide {
        case .titleSafe, .actionSafe:
            broadcastSafeGuide(guide: guide, videoFrame: videoFrame)
        case .centerCrosshair:
            centerCrosshairGuide(videoFrame: videoFrame)
        default:
            if guide.isAspectRatio {
                aspectRatioGuide(guide: guide, videoFrame: videoFrame)
            }
        }
    }
    
    // MARK: - Broadcast Safe Guides
    
    private func broadcastSafeGuide(guide: SafeAreaGuideType, videoFrame: CGRect) -> some View {
        let inset = guide.safeAreaInset ?? 0
        let insetX = videoFrame.width * inset
        let insetY = videoFrame.height * inset
        
        let guideWidth = videoFrame.width - (insetX * 2)
        let guideHeight = videoFrame.height - (insetY * 2)
        
        return ZStack(alignment: .topLeading) {
            // Guide rectangle
            Rectangle()
                .strokeBorder(guideColor.opacity(guideOpacity), lineWidth: lineWidth)
                .frame(width: guideWidth, height: guideHeight)
            
            // Label
            Text(guide.shortLabel)
                .font(labelFont)
                .foregroundStyle(guideColor.opacity(guideOpacity))
                .padding(4)
        }
        .position(
            x: videoFrame.midX,
            y: videoFrame.midY
        )
    }
    
    // MARK: - Aspect Ratio Guides
    
    @ViewBuilder
    private func aspectRatioGuide(guide: SafeAreaGuideType, videoFrame: CGRect) -> some View {
        if let targetAspect = guide.aspectRatio {
            let videoAspect = videoFrame.width / videoFrame.height

            let guideWidth: CGFloat = min(
                targetAspect > videoAspect ? videoFrame.width : videoFrame.height * targetAspect,
                videoFrame.width
            )
            let guideHeight: CGFloat = min(
                targetAspect > videoAspect ? videoFrame.width / targetAspect : videoFrame.height,
                videoFrame.height
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(guideColor.opacity(guideOpacity), lineWidth: lineWidth)
                    .frame(width: guideWidth, height: guideHeight)

                Text(guide.shortLabel)
                    .font(labelFont)
                    .foregroundStyle(guideColor.opacity(guideOpacity))
                    .padding(4)
            }
            .position(
                x: videoFrame.midX,
                y: videoFrame.midY
            )
        }
    }
    
    // MARK: - Center Crosshair
    
    private func centerCrosshairGuide(videoFrame: CGRect) -> some View {
        let centerX = videoFrame.midX
        let centerY = videoFrame.midY
        
        return ZStack {
            // Horizontal line
            Rectangle()
                .fill(guideColor.opacity(guideOpacity))
                .frame(width: crosshairSize, height: lineWidth)
                .position(x: centerX, y: centerY)
            
            // Vertical line
            Rectangle()
                .fill(guideColor.opacity(guideOpacity))
                .frame(width: lineWidth, height: crosshairSize)
                .position(x: centerX, y: centerY)
            
            // Center dot
            Circle()
                .fill(guideColor.opacity(guideOpacity))
                .frame(width: 4, height: 4)
                .position(x: centerX, y: centerY)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        
        // Simulated video content
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(16/9, contentMode: .fit)
        
        SafeAreaGuidesOverlay(
            activeGuides: [.titleSafe, .actionSafe, .aspect2_39, .centerCrosshair],
            videoAspectRatio: 16/9
        )
    }
    .frame(width: 800, height: 450)
}
