import Foundation

// MARK: - AV1 Config Parsing

/// Parses the av1C configuration box from an AV1 video stream
/// - Parameter data: Raw av1C data (minimum 4 bytes required)
/// - Returns: Parsed AV1 configuration summary, or nil if invalid
func parseAV1C(_ data: Data) -> AV1ConfigSummary? {
    guard data.count >= 4 else { return nil }
    let bytes = [UInt8](data)

    // Byte 0: marker (1) + version (7 bits) - should be 0x81 for version 1
    // Byte 1: seq_profile (3 bits) + seq_level_idx_0 (5 bits)
    // Byte 2: seq_tier_0 (1) + high_bitdepth (1) + twelve_bit (1) + monochrome (1) + chroma_subsampling_x (1) + chroma_subsampling_y (1) + chroma_sample_position (2)
    // Byte 3: reserved (3) + initial_presentation_delay_present (1) + initial_presentation_delay_minus_one/reserved (4)

    // Byte 1: profile (bits 5..7)
    let profile = Int((bytes[1] & 0b1110_0000) >> 5)
    // Byte 1: level (bits 0..4)
    let level = Int(bytes[1] & 0b0001_1111)

    let seqProfile = profile
    let highBitDepth = (bytes[2] & 0b0100_0000) != 0
    let twelveBit = (bytes[2] & 0b0010_0000) != 0

    // AV1 bit depth calculation per spec:
    // - Profile 0 (Main): 8 or 10-bit, 4:2:0 or Monochrome
    // - Profile 1 (High): 8 or 10-bit, 4:4:4
    // - Profile 2 (Professional): 8, 10, or 12-bit, all chroma subsampling
    let bitDepth: Int
    if seqProfile == 2 && highBitDepth {
        bitDepth = twelveBit ? 12 : 10
    } else {
        bitDepth = highBitDepth ? 10 : 8
    }

    let monoChrome = (bytes[2] & 0b0001_0000) != 0
    let subsamplingX = (bytes[2] & 0b0000_1000) != 0
    let subsamplingY = (bytes[2] & 0b0000_0100) != 0

    let chroma: String
    if monoChrome {
        chroma = "Monochrome"
    } else if !subsamplingX && !subsamplingY {
        chroma = "4:4:4"
    } else if subsamplingX && !subsamplingY {
        chroma = "4:2:2"
    } else if subsamplingX && subsamplingY {
        chroma = "4:2:0"
    } else {
        chroma = "Unknown"
    }

    // Full range flag is in byte 3
    let fullRange = (bytes[3] & 0b1000_0000) != 0

    return AV1ConfigSummary(
        profile: profile,
        level: level,
        bitDepth: bitDepth,
        chromaSubsampling: chroma,
        fullRange: fullRange
    )
}

// MARK: - AV1 Level Description

/// Returns human-readable AV1 level description
func av1LevelDescription(_ level: Int) -> String {
    // AV1 levels: 2.0, 2.1, 2.2, 2.3, 3.0, 3.1, 3.2, 3.3, 4.0, 4.1, 4.2, 4.3, 5.0, 5.1, 5.2, 5.3, 6.0, 6.1, 6.2, 6.3
    let major = (level >> 2) + 2
    let minor = level & 0x03
    return "\(major).\(minor)"
}

/// Returns human-readable AV1 profile description
func av1ProfileDescription(_ profile: Int) -> String {
    switch profile {
    case 0: return "Main"
    case 1: return "High"
    case 2: return "Professional"
    default: return "Unknown (\(profile))"
    }
}
