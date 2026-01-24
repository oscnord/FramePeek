import Foundation
import AVFoundation
import CoreMedia

// MARK: - Dolby Vision Configuration

/// Dolby Vision configuration extracted from dvcC/dvvC atoms
struct DolbyVisionConfig {
    let profile: Int           // 0-9
    let level: Int             // 0-13
    let blSignalCompatibility: Int  // Base layer signal compatibility
    let rpuPresent: Bool       // RPU (Reference Processing Unit) data present
    let elPresent: Bool        // Enhancement layer present
    let blPresent: Bool        // Base layer present
    
    /// Human-readable profile description
    var profileDescription: String {
        switch profile {
        case 0: return "dvav.per"
        case 1: return "dvav.pen"
        case 2: return "dvhe.der"
        case 3: return "dvhe.den"
        case 4: return "dvhe.dtr"
        case 5: return "dvhe.stn"
        case 6: return "dvhe.dtb"
        case 7: return "dvhe.st (HDR10 Compatible)"
        case 8: return "dvhe.se (HDR10/HLG Compatible)"
        case 9: return "dvav.se (SDR Compatible)"
        default: return "Unknown Profile \(profile)"
        }
    }
    
    /// Human-readable level description
    var levelDescription: String {
        switch level {
        case 0: return "Unspecified"
        case 1: return "Level 1 (HD 24fps)"
        case 2: return "Level 2 (HD 30fps)"
        case 3: return "Level 3 (HD 60fps)"
        case 4: return "Level 4 (FHD 24fps)"
        case 5: return "Level 5 (FHD 30fps)"
        case 6: return "Level 6 (FHD 60fps)"
        case 7: return "Level 7 (UHD 24fps)"
        case 8: return "Level 8 (UHD 30fps)"
        case 9: return "Level 9 (UHD 60fps)"
        case 10: return "Level 10 (UHD 120fps)"
        case 11: return "Level 11 (8K 24fps)"
        case 12: return "Level 12 (8K 30fps)"
        case 13: return "Level 13 (8K 60fps)"
        default: return "Level \(level)"
        }
    }
    
    /// Is this profile cross-compatible with HDR10?
    var isHDR10Compatible: Bool {
        profile == 7 || profile == 8
    }
    
    /// Is this profile cross-compatible with HLG?
    var isHLGCompatible: Bool {
        profile == 8
    }
    
    /// Is this profile cross-compatible with SDR?
    var isSDRCompatible: Bool {
        profile == 9
    }
    
    /// Short codec string (e.g., "dvhe.07.06")
    var codecString: String {
        let profileHex = String(format: "%02d", profile)
        let levelHex = String(format: "%02d", level)
        
        let prefix: String
        switch profile {
        case 0, 1, 9:
            prefix = "dvav"
        default:
            prefix = "dvhe"
        }
        
        return "\(prefix).\(profileHex).\(levelHex)"
    }
}

// MARK: - Dolby Vision Metadata (from dovi_tool)

/// Extended Dolby Vision metadata from dovi_tool analysis
struct DolbyVisionMetadata {
    let config: DolbyVisionConfig?
    
    // L6 metadata (static HDR metadata)
    let maxCLL: Int?           // Maximum Content Light Level (nits)
    let maxFALL: Int?          // Maximum Frame Average Light Level (nits)
    
    // L1 metadata (scene-based)
    let minPQ: Double?         // Minimum PQ value
    let maxPQ: Double?         // Maximum PQ value
    let avgPQ: Double?         // Average PQ value
    
    // Additional info
    let rpuCount: Int?         // Number of RPU NAL units
    let dmDataCount: Int?      // Number of DM (Display Management) data blocks
    
    /// Human-readable MaxCLL
    var maxCLLDescription: String? {
        guard let maxCLL = maxCLL else { return nil }
        return "\(maxCLL) nits"
    }
    
    /// Human-readable MaxFALL
    var maxFALLDescription: String? {
        guard let maxFALL = maxFALL else { return nil }
        return "\(maxFALL) nits"
    }
}

// MARK: - Native dvcC/dvvC Parsing

/// Parses Dolby Vision configuration from dvcC or dvvC atom data
/// - Parameter data: Raw atom data
/// - Returns: Parsed configuration or nil if invalid
func parseDolbyVisionConfig(data: Data) -> DolbyVisionConfig? {
    // dvcC/dvvC structure (ETSI TS 103 572):
    // - 1 byte: version (should be 1)
    // - 2 bits: dv_version_major
    // - 6 bits: dv_version_minor  
    // - 7 bits: dv_profile
    // - 6 bits: dv_level
    // - 1 bit: rpu_present_flag
    // - 1 bit: el_present_flag
    // - 1 bit: bl_present_flag
    // - 4 bits: dv_bl_signal_compatibility_id
    // - Remaining bits reserved
    
    guard data.count >= 4 else { return nil }
    
    let bytes = [UInt8](data)
    
    // Version check
    let version = bytes[0]
    guard version == 1 || version == 0 else { return nil }
    
    // Parse fields
    let byte1 = bytes[1]
    let byte2 = bytes[2]
    let byte3 = bytes[3]
    
    // dv_version_major: bits 7-6 of byte1
    // dv_version_minor: bits 5-0 of byte1
    // (we don't need these for now)
    
    // dv_profile: bit 7 of byte1 (MSB) + bits 7-2 of byte2 = 7 bits total
    // Actually: profile is bits 0-6 starting from byte 1 bit 0 across bytes
    // Let's use the standard interpretation:
    // byte1[7:6] = dv_version_major (2 bits)
    // byte1[5:0] = dv_version_minor (6 bits)
    // byte2[7:1] = dv_profile (7 bits)
    // byte2[0] + byte3[7:3] = dv_level (6 bits)
    // byte3[2] = rpu_present_flag
    // byte3[1] = el_present_flag
    // byte3[0] = bl_present_flag
    
    let profile = Int((byte2 >> 1) & 0x7F)
    let level = Int(((byte2 & 0x01) << 5) | ((byte3 >> 3) & 0x1F))
    let rpuPresent = ((byte3 >> 2) & 0x01) == 1
    let elPresent = ((byte3 >> 1) & 0x01) == 1
    let blPresent = (byte3 & 0x01) == 1
    
    // bl_signal_compatibility_id is in the next byte if present
    var blSignalCompatibility = 0
    if data.count >= 5 {
        blSignalCompatibility = Int((bytes[4] >> 4) & 0x0F)
    }
    
    return DolbyVisionConfig(
        profile: profile,
        level: level,
        blSignalCompatibility: blSignalCompatibility,
        rpuPresent: rpuPresent,
        elPresent: elPresent,
        blPresent: blPresent
    )
}

/// Extracts Dolby Vision configuration from a video track
/// - Parameter track: AVAssetTrack to analyze
/// - Returns: Dolby Vision configuration if present
func extractDolbyVisionConfig(from track: AVAssetTrack) async -> DolbyVisionConfig? {
    do {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any],
              let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any] else {
            return nil
        }
        
        // Try dvcC first (more common), then dvvC
        if let dvcCData = atoms["dvcC" as CFString] as? Data {
            return parseDolbyVisionConfig(data: dvcCData)
        }
        
        if let dvvCData = atoms["dvvC" as CFString] as? Data {
            return parseDolbyVisionConfig(data: dvvCData)
        }
        
        return nil
    } catch {
        return nil
    }
}

// MARK: - dovi_tool Integration

/// Manager for dovi_tool CLI integration
class DoviToolManager {
    static let shared = DoviToolManager()
    
    private var cachedPath: String?
    private var pathChecked = false
    
    /// Finds dovi_tool in PATH or user-configured location
    func findDoviTool() -> String? {
        if pathChecked, let cached = cachedPath {
            return cached
        }
        
        // Check user-configured path first (if set)
        let userPath = UserDefaults.standard.string(forKey: "doviToolPath") ?? ""
        if !userPath.isEmpty {
            let expandedUserPath = NSString(string: userPath).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedUserPath) {
                cachedPath = expandedUserPath
                pathChecked = true
                return expandedUserPath
            }
        }
        
        // Auto-detect in common locations
        // Order matters: Apple Silicon Homebrew, Intel Homebrew, system paths, Cargo
        let commonPaths = [
            "/opt/homebrew/bin/dovi_tool",      // Apple Silicon Homebrew
            "/usr/local/bin/dovi_tool",          // Intel Homebrew / manual install
            "/usr/bin/dovi_tool",                // System path
            "~/.cargo/bin/dovi_tool",            // Rust Cargo install
            "/opt/local/bin/dovi_tool",          // MacPorts
            "~/bin/dovi_tool"                    // User bin directory
        ]
        
        for path in commonPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                cachedPath = expandedPath
                pathChecked = true
                return expandedPath
            }
        }
        
        // Try finding via shell (spawn a login shell to get proper PATH)
        // This handles cases where the tool is in a non-standard location added to user's PATH
        if let shellPath = findViaShell() {
            cachedPath = shellPath
            pathChecked = true
            return shellPath
        }
        
        pathChecked = true
        cachedPath = nil
        return nil
    }
    
    /// Attempts to find dovi_tool using a login shell (to get user's PATH)
    private func findViaShell() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which dovi_tool"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // Failed to run shell
        }
        
        return nil
    }
    
    /// Checks if dovi_tool is available
    var isAvailable: Bool {
        findDoviTool() != nil
    }
    
    /// Resets the cached path (call when user changes settings)
    func resetCache() {
        pathChecked = false
        cachedPath = nil
    }
    
    /// Analyzes a Dolby Vision file using dovi_tool
    /// - Parameter url: URL to the video file
    /// - Returns: Extended Dolby Vision metadata
    func analyzeFile(url: URL) async -> DolbyVisionMetadata? {
        guard let doviToolPath = findDoviTool() else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runDoviToolInfo(path: doviToolPath, fileURL: url)
                continuation.resume(returning: result)
            }
        }
    }
    
    private func runDoviToolInfo(path: String, fileURL: URL) -> DolbyVisionMetadata? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["info", "-i", fileURL.path, "-j"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0 else {
                return nil
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return parseDoviToolOutput(data: outputData)
        } catch {
            return nil
        }
    }
    
    private func parseDoviToolOutput(data: Data) -> DolbyVisionMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Parse configuration
        var config: DolbyVisionConfig?
        if let header = json["header"] as? [String: Any] {
            let profile = header["dv_profile"] as? Int ?? 0
            let level = header["dv_level"] as? Int ?? 0
            let rpuPresent = header["rpu_present_flag"] as? Bool ?? false
            let elPresent = header["el_present_flag"] as? Bool ?? false
            let blPresent = header["bl_present_flag"] as? Bool ?? false
            let blCompat = header["dv_bl_signal_compatibility_id"] as? Int ?? 0
            
            config = DolbyVisionConfig(
                profile: profile,
                level: level,
                blSignalCompatibility: blCompat,
                rpuPresent: rpuPresent,
                elPresent: elPresent,
                blPresent: blPresent
            )
        }
        
        // Parse L6 metadata (if present)
        var maxCLL: Int?
        var maxFALL: Int?
        
        if let l6 = json["level6"] as? [String: Any] {
            maxCLL = l6["max_content_light_level"] as? Int
            maxFALL = l6["max_frame_average_light_level"] as? Int
        }
        
        // Parse L1 metadata summary
        var minPQ: Double?
        var maxPQ: Double?
        var avgPQ: Double?
        
        if let l1Summary = json["level1_summary"] as? [String: Any] {
            minPQ = l1Summary["min_pq"] as? Double
            maxPQ = l1Summary["max_pq"] as? Double
            avgPQ = l1Summary["avg_pq"] as? Double
        }
        
        // Count RPUs
        let rpuCount = json["rpu_count"] as? Int
        let dmDataCount = json["dm_data_count"] as? Int
        
        return DolbyVisionMetadata(
            config: config,
            maxCLL: maxCLL,
            maxFALL: maxFALL,
            minPQ: minPQ,
            maxPQ: maxPQ,
            avgPQ: avgPQ,
            rpuCount: rpuCount,
            dmDataCount: dmDataCount
        )
    }
}

// MARK: - Convenience Functions

/// Checks if a video file contains Dolby Vision
/// - Parameter url: URL to the video file
/// - Returns: True if Dolby Vision is detected
func hasDolbyVision(url: URL) async -> Bool {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
        return false
    }
    return await extractDolbyVisionConfig(from: track) != nil
}

/// Gets complete Dolby Vision information for a video
/// - Parameters:
///   - url: URL to the video file
///   - useDoviTool: Whether to try using dovi_tool for extended metadata
/// - Returns: Dolby Vision metadata if present
func getDolbyVisionInfo(url: URL, useDoviTool: Bool = true) async -> DolbyVisionMetadata? {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
        return nil
    }
    
    let config = await extractDolbyVisionConfig(from: track)
    
    // If dovi_tool is available and requested, get extended metadata
    if useDoviTool && DoviToolManager.shared.isAvailable {
        if let doviMetadata = await DoviToolManager.shared.analyzeFile(url: url) {
            return doviMetadata
        }
    }
    
    // Return basic metadata from native parsing
    guard let config = config else { return nil }
    
    return DolbyVisionMetadata(
        config: config,
        maxCLL: nil,
        maxFALL: nil,
        minPQ: nil,
        maxPQ: nil,
        avgPQ: nil,
        rpuCount: nil,
        dmDataCount: nil
    )
}
