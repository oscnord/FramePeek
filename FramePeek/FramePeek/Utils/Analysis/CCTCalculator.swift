import Foundation

// MARK: - McCamy's CCT Calculator

/// Calculates Correlated Color Temperature using McCamy's formula
/// This is the proper scientific method for determining CCT from chromaticity coordinates

/// CIE 1931 xy chromaticity coordinates
struct ChromaticityXY {
    let x: Double
    let y: Double
    
    /// Calculate CCT and Duv from chromaticity coordinates
    func calculateCCT() -> ColorTemperatureData? {
        // McCamy's formula works best for CCT between 2000K and 12000K
        // and for colors near the Planckian locus
        
        // Calculate n (inverse slope line from epicenter)
        // Epicenter is at (0.3320, 0.1858)
        let epicenterX = 0.3320
        let epicenterY = 0.1858
        
        guard y != epicenterY else { return nil }
        
        let n = (x - epicenterX) / (epicenterY - y)
        
        // McCamy's formula (1992)
        // CCT = 449n³ + 3525n² + 6823.3n + 5520.33
        let cct = 449.0 * pow(n, 3) + 3525.0 * pow(n, 2) + 6823.3 * n + 5520.33
        
        // Clamp to reasonable range for video content
        // Most video content falls between 1800K (warm tungsten) and 20000K (extreme blue)
        // Values outside this range are usually from highly saturated or unusual colors
        guard cct > 1800 && cct < 20000 else { return nil }
        
        // Calculate Duv (distance from Planckian locus)
        let duv = calculateDuv(cct: cct)
        
        // Calculate confidence based on distance from Planckian locus
        // Colors far from the locus have unreliable CCT values
        let confidence = calculateConfidence(duv: duv)
        
        return ColorTemperatureData(cct: cct, duv: duv, confidence: confidence)
    }
    
    /// Calculate Duv (delta uv) - distance from Planckian locus
    private func calculateDuv(cct: Double) -> Double {
        // Convert xy to uv (CIE 1960 UCS)
        let u = 4.0 * x / (-2.0 * x + 12.0 * y + 3.0)
        let v = 6.0 * y / (-2.0 * x + 12.0 * y + 3.0)
        
        // Get reference point on Planckian locus for this CCT
        let (refU, refV) = planckianLocusUV(cct: cct)
        
        // Calculate distance
        let du = u - refU
        let dv = v - refV
        
        // Duv is signed: positive = above locus (green tint), negative = below (magenta tint)
        // The sign is determined by the cross product with the locus tangent
        let duv = sqrt(du * du + dv * dv)
        
        // Determine sign based on position relative to locus
        return dv > 0 ? duv : -duv
    }
    
    /// Get uv coordinates on Planckian locus for given CCT
    /// Krystek (1985) rational approximation, valid 1000K-15000K
    private func planckianLocusUV(cct: Double) -> (u: Double, v: Double) {
        let t = cct
        let t2 = t * t

        let u = (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t2) /
                (1.0 + 8.42420235e-4 * t + 7.08145163e-7 * t2)
        let v = (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t2) /
                (1.0 - 2.89741816e-5 * t + 1.61456053e-7 * t2)

        return (u, v)
    }
    
    /// Calculate confidence score based on Duv
    private func calculateConfidence(duv: Double) -> Double {
        // Colors on the Planckian locus have |Duv| = 0
        // Typical daylight sources have |Duv| < 0.006
        // |Duv| > 0.02 indicates the color is far from any white point
        
        let absDuv = abs(duv)
        
        if absDuv < 0.003 {
            return 1.0  // Excellent - on or very near Planckian locus
        } else if absDuv < 0.006 {
            return 0.9  // Very good - within typical daylight variance
        } else if absDuv < 0.01 {
            return 0.7  // Good - slight tint but CCT is meaningful
        } else if absDuv < 0.02 {
            return 0.5  // Fair - noticeable tint, CCT less reliable
        } else if absDuv < 0.05 {
            return 0.3  // Poor - significant tint, CCT is questionable
        } else {
            return 0.1  // Very poor - color is far from any white point
        }
    }
}

// MARK: - RGB to Chromaticity Conversion

/// RGB to XYZ conversion matrices for different color spaces
enum ColorSpaceMatrix {
    /// BT.709 / sRGB to XYZ matrix
    static let bt709ToXYZ: [[Double]] = [
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041]
    ]
    
    /// BT.2020 to XYZ matrix
    static let bt2020ToXYZ: [[Double]] = [
        [0.6369580, 0.1446169, 0.1688810],
        [0.2627002, 0.6779981, 0.0593017],
        [0.0000000, 0.0280727, 1.0609851]
    ]
    
    /// Display P3 to XYZ matrix
    static let p3ToXYZ: [[Double]] = [
        [0.4865709, 0.2656677, 0.1982173],
        [0.2289746, 0.6917385, 0.0792869],
        [0.0000000, 0.0451134, 1.0439444]
    ]
}

/// Converts linear RGB to CIE XYZ
/// - Parameters:
///   - r: Red component (0-1, linear)
///   - g: Green component (0-1, linear)
///   - b: Blue component (0-1, linear)
///   - matrix: Color space conversion matrix
/// - Returns: XYZ values (X, Y, Z)
func rgbToXYZ(r: Double, g: Double, b: Double, matrix: [[Double]] = ColorSpaceMatrix.bt709ToXYZ) -> (x: Double, y: Double, z: Double) {
    let x = matrix[0][0] * r + matrix[0][1] * g + matrix[0][2] * b
    let y = matrix[1][0] * r + matrix[1][1] * g + matrix[1][2] * b
    let z = matrix[2][0] * r + matrix[2][1] * g + matrix[2][2] * b
    return (x, y, z)
}

/// Converts CIE XYZ to xy chromaticity coordinates
/// - Parameters:
///   - X: CIE X
///   - Y: CIE Y (luminance)
///   - Z: CIE Z
/// - Returns: xy chromaticity coordinates, or nil if sum is zero
func xyzToChromacity(X: Double, Y: Double, Z: Double) -> ChromaticityXY? {
    let sum = X + Y + Z
    guard sum > 0.0001 else { return nil }  // Avoid division by near-zero
    
    return ChromaticityXY(
        x: X / sum,
        y: Y / sum
    )
}

/// Calculates CCT from RGB values
/// - Parameters:
///   - r: Red component (0-1, gamma-encoded)
///   - g: Green component (0-1, gamma-encoded)
///   - b: Blue component (0-1, gamma-encoded)
///   - colorSpace: Color space for conversion matrix selection
///   - contentType: HDR content type for proper linearization
/// - Returns: Color temperature data, or nil if CCT cannot be calculated
func calculateCCTFromRGB(
    r: Double, g: Double, b: Double,
    colorSpace: ColorSpace = .bt709,
    contentType: HDRContentType = .sdr
) -> ColorTemperatureData? {
    // Step 1: Linearize RGB values based on content type
    let linearR = signalToLinear(r, contentType: contentType)
    let linearG = signalToLinear(g, contentType: contentType)
    let linearB = signalToLinear(b, contentType: contentType)
    
    // Step 2: Select appropriate color space matrix
    let matrix: [[Double]]
    switch colorSpace {
    case .bt709, .srgb:
        matrix = ColorSpaceMatrix.bt709ToXYZ
    case .bt2020:
        matrix = ColorSpaceMatrix.bt2020ToXYZ
    case .p3:
        matrix = ColorSpaceMatrix.p3ToXYZ
    }
    
    // Step 3: Convert to XYZ
    let xyz = rgbToXYZ(r: linearR, g: linearG, b: linearB, matrix: matrix)
    
    // Step 4: Convert to xy chromaticity
    guard let chromacity = xyzToChromacity(X: xyz.x, Y: xyz.y, Z: xyz.z) else {
        return nil
    }
    
    // Step 5: Calculate CCT using McCamy's formula
    return chromacity.calculateCCT()
}

/// Color space enumeration for matrix selection
public enum ColorSpace: String, CaseIterable {
    case bt709 = "BT.709"
    case bt2020 = "BT.2020"
    case p3 = "P3"
    case srgb = "sRGB"
    
    /// Detect color space from AVFoundation color primaries string
    static func from(colorPrimaries: String?) -> ColorSpace {
        guard let primaries = colorPrimaries else { return .bt709 }
        
        switch primaries {
        case "ITU_R_2020":
            return .bt2020
        case "P3_D65", "P3_DCI":
            return .p3
        case "ITU_R_709_2", "IEC_sRGB":
            return .bt709
        default:
            return .bt709
        }
    }
}

// MARK: - Frame Average CCT Calculation

/// Calculates average CCT from planar frame data
/// Weight by luminance and inverse saturation so neutral, bright pixels dominate
func calculateFrameAverageCCT(
    rgb: PlanarRGB,
    luminancePlane: [Float],
    colorSpace: ColorSpace = .bt709,
    contentType: HDRContentType = .sdr
) -> ColorTemperatureData? {
    let pixelCount = rgb.count
    guard luminancePlane.count == pixelCount else { return nil }

    var totalR: Float = 0
    var totalG: Float = 0
    var totalB: Float = 0
    var totalWeight: Float = 0

    for i in 0..<pixelCount {
        let luma = luminancePlane[i]

        // Skip very dark pixels (unreliable for CCT)
        guard luma > 0.05 else { continue }

        let r = rgb.r[i]
        let g = rgb.g[i]
        let b = rgb.b[i]

        // Skip highly saturated pixels - CCT is only meaningful for near-neutral colors
        let maxC = Swift.max(r, Swift.max(g, b))
        let minC = Swift.min(r, Swift.min(g, b))
        let saturation = maxC > 0.001 ? (maxC - minC) / maxC : 0
        guard saturation < 0.5 else { continue }

        let weight = luma * (1.0 - saturation)

        totalR += r * weight
        totalG += g * weight
        totalB += b * weight
        totalWeight += weight
    }

    guard totalWeight > 0 else { return nil }

    return calculateCCTFromRGB(
        r: Double(totalR / totalWeight),
        g: Double(totalG / totalWeight),
        b: Double(totalB / totalWeight),
        colorSpace: colorSpace,
        contentType: contentType
    )
}

// MARK: - CCT Reference Values

/// Common CCT reference values for display
enum CCTReference {
    /// Candle light (~1850K)
    static let candle: Double = 1850
    
    /// Incandescent/Tungsten (~2700K)
    static let tungsten: Double = 2700
    
    /// Warm white LED (~3000K)
    static let warmWhite: Double = 3000
    
    /// Halogen (~3200K)
    static let halogen: Double = 3200
    
    /// Neutral white (~4000K)
    static let neutralWhite: Double = 4000
    
    /// Cool white fluorescent (~4500K)
    static let coolWhite: Double = 4500
    
    /// D50 (photographic daylight) (~5000K)
    static let d50: Double = 5003
    
    /// Direct sunlight (~5500K)
    static let directSunlight: Double = 5500
    
    /// D65 (standard daylight illuminant) (~6500K)
    static let d65: Double = 6504
    
    /// Overcast sky (~6500-7500K)
    static let overcast: Double = 7000
    
    /// Blue sky / shade (~8000-10000K)
    static let blueSky: Double = 9000
}
