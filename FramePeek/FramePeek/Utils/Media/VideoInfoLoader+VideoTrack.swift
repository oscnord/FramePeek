import Foundation
import AVFoundation
import CoreMedia

public struct VideoTrackInfo {
    public let resolution: String
    public let videoWidth: Int
    public let videoHeight: Int
    public let frameRate: String
    public let nominalFrameRateValue: Float
    public let orientationDegrees: Int?
    public let trackBitrate: String?
    public let trackBitrateValue: Float
    public let pixelAspectRatio: String?
    public let parH: Int
    public let parV: Int
    public let cleanAperture: String?
    public let scanType: String?
    public let frameRateMode: String?
    
    public init(resolution: String, videoWidth: Int, videoHeight: Int, frameRate: String, nominalFrameRateValue: Float, orientationDegrees: Int?, trackBitrate: String?, trackBitrateValue: Float, pixelAspectRatio: String?, parH: Int, parV: Int, cleanAperture: String?, scanType: String?, frameRateMode: String?) {
        self.resolution = resolution
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.frameRate = frameRate
        self.nominalFrameRateValue = nominalFrameRateValue
        self.orientationDegrees = orientationDegrees
        self.trackBitrate = trackBitrate
        self.trackBitrateValue = trackBitrateValue
        self.pixelAspectRatio = pixelAspectRatio
        self.parH = parH
        self.parV = parV
        self.cleanAperture = cleanAperture
        self.scanType = scanType
        self.frameRateMode = frameRateMode
    }
}

public func extractVideoTrackInfo(asset: AVAsset) async -> VideoTrackInfo? {
    var videoTrack: AVAssetTrack?
    do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        videoTrack = tracks.first
    } catch {
        Log.media.error("Failed to load video tracks: \(error.localizedDescription)")
        return nil
    }

    guard let videoTrack = videoTrack else { return nil }

    do {
        let naturalSize = try await videoTrack.load(.naturalSize)
        let loadedFrameRate = try await videoTrack.load(.nominalFrameRate)

        let w = Int(naturalSize.width)
        let h = Int(naturalSize.height)
        let resolution = "\(w)x\(h)"
        let frameRate = String(format: "%.3f FPS", loadedFrameRate)

        // Orientation (preferredTransform)
        let t = (try? await videoTrack.load(.preferredTransform)) ?? CGAffineTransform.identity
        let angle = atan2(t.b, t.a) * 180.0 / .pi
        let normalized = (Int(round(angle)) % 360 + 360) % 360
        let orientationDegrees: Int? = normalized != 0 ? normalized : nil

        // Track bitrate
        let estimated = (try? await videoTrack.load(.estimatedDataRate)) ?? 0
        let trackBitrateValue = estimated
        let trackBitrate: String? = estimated > 0 ? String(format: "%.0f kb/s", estimated / 1000.0) : nil

        // Format description for PAR and clean aperture
        var pixelAspectRatio: String?
        var parH: Int = 1
        var parV: Int = 1
        var cleanAperture: String?
        var scanType: String?

        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        if let formatDesc = formatDescriptions.first,
           let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] {

            // Clean aperture
            if let caDict = extDict[kCMFormatDescriptionExtension_CleanAperture] as? [CFString: Any],
               let w = caDict[kCMFormatDescriptionKey_CleanApertureWidth] as? NSNumber,
               let h = caDict[kCMFormatDescriptionKey_CleanApertureHeight] as? NSNumber {
                cleanAperture = "\(w.intValue)x\(h.intValue)"
            }

            // Pixel aspect ratio
            if let parDict = extDict[kCMFormatDescriptionExtension_PixelAspectRatio] as? [CFString: Any],
               let h = parDict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
               let v = parDict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber {
                parH = h.intValue
                parV = v.intValue
                pixelAspectRatio = "\(parH):\(parV)"
            }

            // Scan type
            if let fieldCount = extDict[kCMFormatDescriptionExtension_FieldCount] as? NSNumber {
                switch fieldCount.intValue {
                case 1: scanType = "Progressive"
                case 2: scanType = "Interlaced (2 fields)"
                default: scanType = "Interlaced"
                }
            }
        }

        return VideoTrackInfo(
            resolution: resolution,
            videoWidth: w,
            videoHeight: h,
            frameRate: frameRate,
            nominalFrameRateValue: loadedFrameRate,
            orientationDegrees: orientationDegrees,
            trackBitrate: trackBitrate,
            trackBitrateValue: trackBitrateValue,
            pixelAspectRatio: pixelAspectRatio,
            parH: parH,
            parV: parV,
            cleanAperture: cleanAperture,
            scanType: scanType,
            frameRateMode: nil // Not extracted in original code
        )
    } catch {
        Log.media.error("Error loading video track info: \(error.localizedDescription)")
        return nil
    }
}
