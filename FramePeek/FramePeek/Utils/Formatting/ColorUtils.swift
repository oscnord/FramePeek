import Foundation

// MARK: - HDR Detection

/// Detects HDR format based on color metadata
func detectHDRFormat(
    transferFunction: String?,
    colorPrimaries: String?,
    hasDolbyVisionConfig: Bool = false
) -> String? {
    // Check for Dolby Vision first (needs specific atom detection)
    if hasDolbyVisionConfig {
        return "Dolby Vision"
    }

    // Check transfer function for HDR indicators
    guard let tf = transferFunction else { return nil }

    switch tf {
    case "ITU_R_2100_HLG", "ARIB_STD_B67":
        return "HLG (Hybrid Log-Gamma)"
    case "ITU_R_2100_PQ", "SMPTE_ST_2084":
        // PQ transfer function - check primaries for HDR10
        if let primaries = colorPrimaries,
           primaries == "ITU_R_2020" || primaries == "P3_D65" {
            return "HDR10"
        }
        return "PQ (HDR)"
    case "Linear", "IEC_sRGB":
        return nil // SDR
    default:
        // Check for BT.2020 primaries which might indicate HDR
        if let primaries = colorPrimaries, primaries == "ITU_R_2020" {
            return "Wide Color Gamut (BT.2020)"
        }
        return nil
    }
}

// MARK: - Color Space Descriptions

/// Human-readable color primaries description
func colorPrimariesDescription(_ primaries: String?) -> String? {
    guard let primaries = primaries else { return nil }

    let mappings: [String: String] = [
        "ITU_R_709_2": "BT.709 (Rec. 709)",
        "ITU_R_2020": "BT.2020 (Rec. 2020)",
        "P3_D65": "Display P3",
        "P3_DCI": "DCI-P3",
        "SMPTE_C": "SMPTE C",
        "EBU_3213": "EBU 3213-E"
    ]

    return mappings[primaries] ?? primaries
}

/// Human-readable transfer function description
func transferFunctionDescription(_ transfer: String?) -> String? {
    guard let transfer = transfer else { return nil }

    let mappings: [String: String] = [
        "ITU_R_709_2": "BT.709",
        "ITU_R_2100_HLG": "HLG",
        "ITU_R_2100_PQ": "PQ (ST 2084)",
        "SMPTE_ST_2084": "PQ (ST 2084)",
        "ARIB_STD_B67": "HLG (ARIB)",
        "IEC_sRGB": "sRGB",
        "Linear": "Linear"
    ]

    return mappings[transfer] ?? transfer
}

/// Human-readable matrix coefficients description
func matrixDescription(_ matrix: String?) -> String? {
    guard let matrix = matrix else { return nil }

    let mappings: [String: String] = [
        "ITU_R_709_2": "BT.709",
        "ITU_R_2020": "BT.2020",
        "ITU_R_601_4": "BT.601",
        "SMPTE_240M_1995": "SMPTE 240M"
    ]

    return mappings[matrix] ?? matrix
}
