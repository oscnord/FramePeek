//
//  FormatUtils.swift
//  FramePeek
//
//  Formatting utilities for duration, codec names, and channel layouts.
//

import Foundation

// MARK: - FourCC Conversion

/// Converts a FourCC code to a string representation
func fourCCToString(_ code: OSType) -> String {
    let bytes: [CChar] = [
        CChar((code >> 24) & 0xFF),
        CChar((code >> 16) & 0xFF),
        CChar((code >> 8) & 0xFF),
        CChar(code & 0xFF),
        0
    ]
    return String(cString: bytes)
}

// MARK: - Duration Formatting

/// Formats duration in a human-readable way (e.g., "1h 23m 45s" or "2m 30s")
func formatDuration(seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "N/A" }
    
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    let ms = Int((seconds - Double(totalSeconds)) * 1000)
    
    if hours > 0 {
        return String(format: "%dh %02dm %02ds", hours, minutes, secs)
    } else if minutes > 0 {
        return String(format: "%dm %02ds", minutes, secs)
    } else if secs > 0 || ms > 0 {
        return String(format: "%.2fs", seconds)
    } else {
        return "0s"
    }
}

// MARK: - Audio Channel Layout

/// Converts channel count to a descriptive layout string
func channelLayoutDescription(channels: Int) -> String {
    switch channels {
    case 1: return "Mono"
    case 2: return "Stereo"
    case 3: return "2.1"
    case 4: return "Quad"
    case 5: return "5.0"
    case 6: return "5.1"
    case 7: return "6.1"
    case 8: return "7.1"
    default: return "\(channels) channels"
    }
}

// MARK: - Codec Names

/// Converts audio codec FourCC to a human-readable name
func audioCodecName(_ fourCC: String) -> String {
    let mappings: [String: String] = [
        "aac ": "AAC",
        "mp4a": "AAC",
        "ac-3": "Dolby Digital (AC-3)",
        "ec-3": "Dolby Digital Plus (E-AC-3)",
        "alac": "Apple Lossless",
        "lpcm": "LPCM",
        "mp3 ": "MP3",
        ".mp3": "MP3",
        "opus": "Opus",
        "fLaC": "FLAC",
        "dtsc": "DTS",
        "dtse": "DTS Express",
        "dtsh": "DTS-HD",
        "dtsl": "DTS-HD Lossless"
    ]
    return mappings[fourCC] ?? fourCC.trimmingCharacters(in: .whitespaces)
}

/// Video codec FourCC to human-readable name mappings
let videoCodecMappings: [String: String] = [
    "avc1": "H.264",
    "avc2": "H.264",
    "avc3": "H.264",
    "avc4": "H.264",
    "hvc1": "HEVC (H.265)",
    "hev1": "HEVC (H.265)",
    "vp09": "VP9",
    "vp08": "VP8",
    "av01": "AV1",
    "mp4v": "MPEG-4 Part 2",
    "apch": "ProRes 422 HQ",
    "apcn": "ProRes 422",
    "apcs": "ProRes 422 LT",
    "apco": "ProRes 422 Proxy",
    "ap4h": "ProRes 4444",
    "ap4x": "ProRes 4444 XQ"
]

/// Converts video codec FourCC to a human-readable name
func videoCodecName(_ fourCC: String) -> String {
    videoCodecMappings[fourCC] ?? fourCC
}

/// Video codec FourCC to descriptive info (Format/Info in MediaInfo)
let videoCodecInfoMappings: [String: String] = [
    "avc1": "Advanced Video Coding",
    "avc2": "Advanced Video Coding",
    "avc3": "Advanced Video Coding",
    "avc4": "Advanced Video Coding",
    "hvc1": "High Efficiency Video Coding",
    "hev1": "High Efficiency Video Coding",
    "vp09": "VP9 Video",
    "vp08": "VP8 Video",
    "av01": "AV1 Video",
    "mp4v": "MPEG-4 Visual",
    "apch": "Apple ProRes 422 High Quality",
    "apcn": "Apple ProRes 422",
    "apcs": "Apple ProRes 422 LT",
    "apco": "Apple ProRes 422 Proxy",
    "ap4h": "Apple ProRes 4444",
    "ap4x": "Apple ProRes 4444 XQ"
]

/// Returns descriptive codec info
func videoCodecInfo(_ fourCC: String) -> String? {
    videoCodecInfoMappings[fourCC]
}

// MARK: - Container Format Detection

/// Detects container format from file URL
func detectContainerFormat(url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "mp4", "m4v":
        return "MPEG-4"
    case "mov":
        return "QuickTime"
    case "mkv":
        return "Matroska"
    case "webm":
        return "WebM"
    case "avi":
        return "AVI"
    case "wmv":
        return "Windows Media Video"
    case "flv":
        return "Flash Video"
    case "ts", "mts", "m2ts":
        return "MPEG-TS"
    case "mpg", "mpeg":
        return "MPEG-PS"
    case "3gp":
        return "3GPP"
    case "mxf":
        return "MXF"
    default:
        return nil
    }
}

// MARK: - Codec Profile Parsing

/// Parses HEVC (H.265) profile from hvcC box data
func parseHEVCProfile(_ data: Data) -> String? {
    guard data.count >= 13 else { return nil }
    
    let bytes = [UInt8](data)
    // Byte 1: general_profile_space (2 bits), general_tier_flag (1 bit), general_profile_idc (5 bits)
    let profileIdc = bytes[1] & 0x1F
    let tierFlag = (bytes[1] >> 5) & 0x01
    
    // Byte 12: general_level_idc
    let levelIdc = bytes[12]
    let level = Double(levelIdc) / 30.0
    
    let profileName: String
    switch profileIdc {
    case 1: profileName = "Main"
    case 2: profileName = "Main 10"
    case 3: profileName = "Main Still Picture"
    case 4: profileName = "Range Extensions"
    case 5: profileName = "High Throughput"
    default: profileName = "Profile \(profileIdc)"
    }
    
    let tierName = tierFlag == 1 ? "High" : "Main"
    return "\(profileName)@L\(String(format: "%.1f", level))@\(tierName)"
}

/// Parses AVC (H.264) profile from avcC box data
func parseAVCProfile(_ data: Data) -> String? {
    guard data.count >= 4 else { return nil }
    
    let bytes = [UInt8](data)
    // Byte 1: AVCProfileIndication
    // Byte 2: profile_compatibility
    // Byte 3: AVCLevelIndication
    let profileIdc = bytes[1]
    let levelIdc = bytes[3]
    let level = Double(levelIdc) / 10.0
    
    let profileName: String
    switch profileIdc {
    case 66: profileName = "Baseline"
    case 77: profileName = "Main"
    case 88: profileName = "Extended"
    case 100: profileName = "High"
    case 110: profileName = "High 10"
    case 122: profileName = "High 4:2:2"
    case 244: profileName = "High 4:4:4 Predictive"
    default: profileName = "Profile \(profileIdc)"
    }
    
    return "\(profileName)@L\(String(format: "%.1f", level))"
}

/// Parses VP9 profile from vpcC box data
func parseVP9Profile(_ data: Data) -> String? {
    guard data.count >= 8 else { return nil }
    
    let bytes = [UInt8](data)
    // Byte 4: profile
    // Byte 5: level
    let profile = bytes[4]
    let level = bytes[5]
    
    let profileName: String
    switch profile {
    case 0: profileName = "Profile 0 (8-bit 4:2:0)"
    case 1: profileName = "Profile 1 (8-bit 4:2:2/4:4:4)"
    case 2: profileName = "Profile 2 (10/12-bit 4:2:0)"
    case 3: profileName = "Profile 3 (10/12-bit 4:2:2/4:4:4)"
    default: profileName = "Profile \(profile)"
    }
    
    return "\(profileName) Level \(level)"
}
