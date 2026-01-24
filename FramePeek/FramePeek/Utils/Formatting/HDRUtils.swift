import Foundation

// MARK: - PQ (ST.2084) EOTF

/// PQ (Perceptual Quantizer) constants from SMPTE ST.2084
private enum PQConstants {
    static let m1: Double = 2610.0 / 16384.0  // 0.1593017578125
    static let m2: Double = 2523.0 / 4096.0 * 128.0  // 78.84375
    static let c1: Double = 3424.0 / 4096.0  // 0.8359375
    static let c2: Double = 2413.0 / 4096.0 * 32.0  // 18.8515625
    static let c3: Double = 2392.0 / 4096.0 * 32.0  // 18.6875
    static let peakLuminance: Double = 10000.0  // nits
}

/// Converts PQ code value (0.0-1.0) to linear light (0.0-1.0 normalized to 10000 nits)
/// - Parameter pq: PQ-encoded value in range 0.0 to 1.0
/// - Returns: Linear light value normalized to 0.0-1.0 (where 1.0 = 10000 nits)
func pqToLinear(_ pq: Double) -> Double {
    guard pq > 0 else { return 0 }
    guard pq < 1 else { return 1 }
    
    let pqPowM2 = pow(pq, 1.0 / PQConstants.m2)
    let numerator = Swift.max(pqPowM2 - PQConstants.c1, 0.0)
    let denominator = PQConstants.c2 - PQConstants.c3 * pqPowM2
    
    guard denominator > 0 else { return 0 }
    
    let linear = pow(numerator / denominator, 1.0 / PQConstants.m1)
    return linear
}

/// Converts linear light (0.0-1.0) to PQ code value
/// - Parameter linear: Linear light value normalized to 0.0-1.0 (where 1.0 = 10000 nits)
/// - Returns: PQ-encoded value in range 0.0 to 1.0
func linearToPQ(_ linear: Double) -> Double {
    guard linear > 0 else { return 0 }
    guard linear < 1 else { return 1 }
    
    let linearPowM1 = pow(linear, PQConstants.m1)
    let numerator = PQConstants.c1 + PQConstants.c2 * linearPowM1
    let denominator = 1.0 + PQConstants.c3 * linearPowM1
    
    return pow(numerator / denominator, PQConstants.m2)
}

/// Converts PQ code value to absolute luminance in nits
/// - Parameter pq: PQ-encoded value in range 0.0 to 1.0
/// - Returns: Luminance in nits (cd/m²), range 0 to 10000
func pqToNits(_ pq: Double) -> Double {
    return pqToLinear(pq) * PQConstants.peakLuminance
}

/// Converts nits to PQ code value
/// - Parameter nits: Luminance in nits (cd/m²)
/// - Returns: PQ-encoded value in range 0.0 to 1.0
func nitsToPQ(_ nits: Double) -> Double {
    let linear = nits / PQConstants.peakLuminance
    return linearToPQ(linear)
}

// MARK: - HLG (Hybrid Log-Gamma) EOTF

/// HLG constants from ITU-R BT.2100
private enum HLGConstants {
    static let a: Double = 0.17883277
    static let b: Double = 0.28466892  // 1 - 4*a
    static let c: Double = 0.55991073  // 0.5 - a * ln(4*a)
}

/// Converts HLG signal value (0.0-1.0) to relative scene light (OETF^-1)
/// - Parameter hlg: HLG-encoded value in range 0.0 to 1.0
/// - Returns: Relative scene light value
func hlgOETFInverse(_ hlg: Double) -> Double {
    guard hlg > 0 else { return 0 }
    
    if hlg <= 0.5 {
        return (hlg * hlg) / 3.0
    } else {
        return (exp((hlg - HLGConstants.c) / HLGConstants.a) + HLGConstants.b) / 12.0
    }
}

/// Converts HLG signal to display light (full EOTF including OOTF)
/// - Parameters:
///   - hlg: HLG-encoded value in range 0.0 to 1.0
///   - peakLuminance: Display peak luminance in nits (default 1000)
///   - gamma: System gamma for OOTF (default 1.2)
/// - Returns: Display luminance in nits
func hlgToNits(_ hlg: Double, peakLuminance: Double = 1000.0, gamma: Double = 1.2) -> Double {
    let sceneLight = hlgOETFInverse(hlg)
    // Apply OOTF (Opto-Optical Transfer Function)
    let displayLight = pow(sceneLight, gamma)
    return displayLight * peakLuminance
}

/// Converts HLG to normalized linear (0-1 range for given peak luminance)
/// - Parameters:
///   - hlg: HLG-encoded value
///   - peakLuminance: Reference peak luminance in nits
/// - Returns: Normalized linear value 0.0-1.0
func hlgToLinear(_ hlg: Double, peakLuminance: Double = 1000.0) -> Double {
    return hlgToNits(hlg, peakLuminance: peakLuminance) / peakLuminance
}

// MARK: - SDR Gamma

/// Standard gamma value for SDR content (BT.1886)
private let sdrGamma: Double = 2.4

/// Converts gamma-encoded SDR value to linear light
/// - Parameter sdr: Gamma-encoded value in range 0.0 to 1.0
/// - Returns: Linear light value
func sdrToLinear(_ sdr: Double) -> Double {
    guard sdr > 0 else { return 0 }
    return pow(sdr, sdrGamma)
}

/// Converts linear light to gamma-encoded SDR value
/// - Parameter linear: Linear light value
/// - Returns: Gamma-encoded value in range 0.0 to 1.0
func linearToSDR(_ linear: Double) -> Double {
    guard linear > 0 else { return 0 }
    return pow(linear, 1.0 / sdrGamma)
}

// MARK: - Nits Conversion Utilities

/// Converts normalized linear value to nits based on HDR content type
/// - Parameters:
///   - linear: Linear light value (0.0-1.0)
///   - contentType: Type of HDR content
/// - Returns: Luminance in nits
func linearToNits(_ linear: Double, contentType: HDRContentType) -> Double {
    switch contentType {
    case .sdr:
        return linear * 100.0  // SDR reference white = 100 nits
    case .hdr10, .pq, .dolbyVision:
        return linear * 10000.0  // PQ max = 10000 nits
    case .hlg:
        return linear * 1000.0  // HLG reference = 1000 nits
    }
}

/// Converts signal value to linear based on content type's transfer function
/// - Parameters:
///   - signal: Encoded signal value (0.0-1.0)
///   - contentType: Type of HDR content
/// - Returns: Linear light value (0.0-1.0 normalized to content type's peak)
func signalToLinear(_ signal: Double, contentType: HDRContentType) -> Double {
    switch contentType {
    case .sdr:
        return sdrToLinear(signal)
    case .hdr10, .pq, .dolbyVision:
        return pqToLinear(signal)
    case .hlg:
        return hlgToLinear(signal)
    }
}

/// Converts signal value directly to nits
/// - Parameters:
///   - signal: Encoded signal value (0.0-1.0)
///   - contentType: Type of HDR content
/// - Returns: Luminance in nits
func signalToNits(_ signal: Double, contentType: HDRContentType) -> Double {
    switch contentType {
    case .sdr:
        return sdrToLinear(signal) * 100.0
    case .hdr10, .pq, .dolbyVision:
        return pqToNits(signal)
    case .hlg:
        return hlgToNits(signal)
    }
}

// MARK: - Log Nits Scale

/// Converts nits to logarithmic scale for HDR visualization
/// - Parameter nits: Luminance in nits
/// - Returns: Log10 of nits (useful range: 0-4 for 1-10000 nits)
func nitsToLog(_ nits: Double) -> Double {
    guard nits > 0 else { return 0 }
    return log10(nits)
}

/// Converts log nits back to linear nits
/// - Parameter logNits: Logarithmic nits value
/// - Returns: Luminance in nits
func logToNits(_ logNits: Double) -> Double {
    return pow(10, logNits)
}

// MARK: - IRE Conversion

/// Converts normalized value (0-1) to IRE scale
/// - Parameter normalized: Normalized value 0.0-1.0
/// - Returns: IRE value (0 = black, 100 = reference white, >100 = super-white)
func normalizedToIRE(_ normalized: Double) -> Double {
    // Standard video: 0 = 7.5 IRE (setup), 1.0 = 100 IRE
    // For digital video without setup: 0 = 0 IRE, 1.0 = 100 IRE
    // We use the digital convention
    return normalized * 100.0
}

/// Converts IRE to normalized value
/// - Parameter ire: IRE value
/// - Returns: Normalized value 0.0-1.0
func ireToNormalized(_ ire: Double) -> Double {
    return ire / 100.0
}

// MARK: - HDR Content Type Detection

/// Determines HDR content type from video metadata
/// - Parameters:
///   - transferFunction: Transfer function string from AVFoundation
///   - colorPrimaries: Color primaries string
///   - hasDolbyVision: Whether Dolby Vision configuration was detected
/// - Returns: Detected HDR content type
func detectHDRContentType(
    transferFunction: String?,
    colorPrimaries: String?,
    hasDolbyVision: Bool
) -> HDRContentType {
    // Dolby Vision takes precedence
    if hasDolbyVision {
        return .dolbyVision
    }
    
    guard let tf = transferFunction else { return .sdr }
    
    switch tf {
    case "ITU_R_2100_HLG", "ARIB_STD_B67":
        return .hlg
    case "ITU_R_2100_PQ", "SMPTE_ST_2084":
        // Check primaries to distinguish HDR10
        if let primaries = colorPrimaries,
           primaries == "ITU_R_2020" || primaries == "P3_D65" {
            return .hdr10
        }
        return .pq
    default:
        return .sdr
    }
}

// MARK: - Reference Levels

/// Standard reference luminance levels
enum ReferenceLuminance {
    /// SDR reference white (100 nits)
    static let sdrWhite: Double = 100.0
    
    /// HDR reference white for grading (203 nits, per ITU-R BT.2408)
    static let hdrReferenceWhite: Double = 203.0
    
    /// HDR10 typical peak (1000 nits)
    static let hdr10TypicalPeak: Double = 1000.0
    
    /// PQ absolute peak (10000 nits)
    static let pqPeak: Double = 10000.0
    
    /// HLG nominal peak (1000 nits at 1.2 gamma)
    static let hlgPeak: Double = 1000.0
}
