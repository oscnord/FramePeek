import Foundation

// MARK: - Frame Color Analysis

/// Complete color analysis data for a single frame
struct FrameColorAnalysis: Identifiable {
    let id = UUID()
    let time: Double
    let luminance: LuminanceData
    let colorTemperature: ColorTemperatureData?
    let saturation: Double  // 0.0-1.0 average saturation
    let histogram: ColorHistogram
    let waveformData: WaveformData?
    let vectorscopeData: VectorscopeData?
    let exposureStatus: ExposureStatus
}

// MARK: - Luminance Data

/// Luminance statistics for a frame
struct LuminanceData {
    let min: Double           // 0.0-1.0 normalized
    let max: Double           // 0.0-1.0 normalized
    let average: Double       // 0.0-1.0 normalized
    let percentile98: Double  // Peak detection (ignores specular/noise)
    let percentile02: Double  // Shadow detection
    
    /// Contrast ratio (max/min, excluding pure black)
    var contrastRatio: Double {
        let effectiveMin = Swift.max(min, 0.001) // Avoid division by zero
        return self.max / effectiveMin
    }
    
    /// Luminance in nits (requires HDR EOTF conversion upstream)
    struct Nits {
        let min: Double
        let max: Double
        let average: Double
        let peak: Double  // 98th percentile
    }
}

// MARK: - Color Temperature Data

/// Color temperature calculated using McCamy's formula
struct ColorTemperatureData {
    let cct: Double        // Correlated Color Temperature in Kelvin
    let duv: Double        // Delta uv (distance from Planckian locus) - indicates tint
    let confidence: Double // 0.0-1.0 (low for highly saturated or unusual colors)
    
    /// Human-readable description of the color temperature
    var description: String {
        if cct < 3500 {
            return String(localized: "Warm (Tungsten)")
        } else if cct < 4500 {
            return String(localized: "Warm White")
        } else if cct < 5500 {
            return String(localized: "Neutral")
        } else if cct < 6500 {
            return String(localized: "Daylight")
        } else if cct < 7500 {
            return String(localized: "Cool Daylight")
        } else {
            return String(localized: "Cool (Overcast/Shade)")
        }
    }
    
    /// Tint description based on Duv
    var tintDescription: String? {
        if abs(duv) < 0.003 {
            return nil // On Planckian locus, no significant tint
        } else if duv > 0 {
            return String(localized: "Green tint")
        } else {
            return String(localized: "Magenta tint")
        }
    }
}

// MARK: - Waveform Data

/// Traditional broadcast-style waveform data
struct WaveformData {
    /// Each column represents a horizontal position in the frame
    /// Contains histogram of luminance values at that position
    /// columns[x][y] = intensity at horizontal position x, luminance level y
    let columns: [[Double]]  // [256 columns][256 luminance bins]
    let channelMode: WaveformChannel
    
    /// Number of horizontal columns
    var columnCount: Int { columns.count }
    
    /// Number of luminance levels per column
    var levelCount: Int { columns.first?.count ?? 256 }
}

/// Waveform channel display modes
enum WaveformChannel: String, CaseIterable, Identifiable {
    case luma = "Luma"
    case rgb = "RGB"
    case parade = "Parade"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .luma: return String(localized: "Luminance")
        case .rgb: return String(localized: "RGB Overlay")
        case .parade: return String(localized: "RGB Parade")
        }
    }
}

/// Waveform scale options
enum WaveformScale: String, CaseIterable, Identifiable, Codable {
    case ire = "IRE"
    case percentage = "Percentage"
    case nits = "Nits"
    case logNits = "Log Nits"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ire: return "IRE (0-100+)"
        case .percentage: return "% (0-100)"
        case .nits: return String(localized: "Nits (HDR)")
        case .logNits: return String(localized: "Log Nits (HDR)")
        }
    }
    
    /// Whether this scale is appropriate for SDR content
    var isSuitableForSDR: Bool {
        switch self {
        case .ire, .percentage: return true
        case .nits, .logNits: return false
        }
    }
    
    /// Maximum value for this scale (SDR reference)
    var maxValueSDR: Double {
        switch self {
        case .ire: return 109.0 // 109 IRE = 100% white + super-white
        case .percentage: return 100.0
        case .nits: return 100.0 // SDR reference white
        case .logNits: return 2.0 // log10(100)
        }
    }
    
    /// Maximum value for this scale (HDR)
    var maxValueHDR: Double {
        switch self {
        case .ire: return 109.0
        case .percentage: return 100.0
        case .nits: return 10000.0 // PQ max
        case .logNits: return 4.0 // log10(10000)
        }
    }
}

// MARK: - Vectorscope Data

/// Vectorscope plot data showing color distribution
struct VectorscopeData {
    /// Points in UV space with intensity
    /// u, v are normalized to -0.5 to 0.5 range
    let points: [VectorscopePoint]
    
    /// Aggregated grid for efficient rendering (64x64 or 128x128)
    let grid: [[Double]]?  // Intensity at each grid position
    let gridSize: Int
    
    init(points: [VectorscopePoint], gridSize: Int = 128) {
        self.points = points
        self.gridSize = gridSize
        
        // Create aggregated grid for efficient rendering
        var grid = [[Double]](repeating: [Double](repeating: 0, count: gridSize), count: gridSize)
        
        for point in points {
            // Convert UV (-0.5 to 0.5) to grid coordinates (0 to gridSize-1)
            let gridX = Int((point.u + 0.5) * Double(gridSize - 1))
            let gridY = Int((point.v + 0.5) * Double(gridSize - 1))
            
            if gridX >= 0 && gridX < gridSize && gridY >= 0 && gridY < gridSize {
                grid[gridY][gridX] += point.intensity
            }
        }
        
        // Normalize grid values
        let maxIntensity = grid.flatMap { $0 }.max() ?? 1.0
        if maxIntensity > 0 {
            for y in 0..<gridSize {
                for x in 0..<gridSize {
                    grid[y][x] /= maxIntensity
                }
            }
        }
        
        self.grid = grid
    }
}

/// Single point in vectorscope
struct VectorscopePoint {
    let u: Double      // -0.5 to 0.5 (Cb/blue-yellow axis)
    let v: Double      // -0.5 to 0.5 (Cr/red-cyan axis)
    let intensity: Double  // Weight/count for this color
}

// MARK: - Exposure Status

/// Exposure assessment for a frame
enum ExposureStatus: String, CaseIterable {
    case underexposed = "Underexposed"
    case slightlyUnder = "Slightly Under"
    case properlyExposed = "Properly Exposed"
    case slightlyOver = "Slightly Over"
    case overexposed = "Overexposed"
    case clipped = "Clipped"
    case highDynamicRange = "High Dynamic Range"
    
    var displayName: String {
        switch self {
        case .underexposed: return String(localized: "Underexposed")
        case .slightlyUnder: return String(localized: "Slightly Under")
        case .properlyExposed: return String(localized: "Properly Exposed")
        case .slightlyOver: return String(localized: "Slightly Over")
        case .overexposed: return String(localized: "Overexposed")
        case .clipped: return String(localized: "Clipped")
        case .highDynamicRange: return String(localized: "High DR")
        }
    }
    
    var color: String {
        switch self {
        case .underexposed: return "blue"
        case .slightlyUnder: return "cyan"
        case .properlyExposed: return "green"
        case .slightlyOver: return "yellow"
        case .overexposed: return "orange"
        case .clipped: return "red"
        case .highDynamicRange: return "purple"
        }
    }
    
    var symbolName: String {
        switch self {
        case .underexposed: return "moon.fill"
        case .slightlyUnder: return "minus.circle"
        case .properlyExposed: return "checkmark.circle.fill"
        case .slightlyOver: return "plus.circle"
        case .overexposed: return "sun.max.fill"
        case .clipped: return "exclamationmark.triangle.fill"
        case .highDynamicRange: return "sparkles"
        }
    }
}

// MARK: - HDR Content Type

/// Type of HDR content for analysis configuration
enum HDRContentType: String, CaseIterable {
    case sdr = "SDR"
    case hdr10 = "HDR10"
    case hlg = "HLG"
    case dolbyVision = "Dolby Vision"
    case pq = "PQ (Generic)"
    
    var displayName: String {
        switch self {
        case .sdr: return "SDR"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "Dolby Vision"
        case .pq: return "PQ (ST.2084)"
        }
    }
    
    var isHDR: Bool {
        self != .sdr
    }
    
    var usesPQ: Bool {
        switch self {
        case .hdr10, .dolbyVision, .pq: return true
        case .sdr, .hlg: return false
        }
    }
    
    var usesHLG: Bool {
        self == .hlg
    }
    
    /// Maximum luminance in nits for this content type
    var maxNits: Double {
        switch self {
        case .sdr: return 100.0
        case .hdr10, .pq: return 10000.0
        case .hlg: return 1000.0
        case .dolbyVision: return 10000.0
        }
    }
}

// MARK: - Color Analysis Configuration

/// Configuration for color analysis
struct ColorAnalysisConfig {
    let hdrContentType: HDRContentType
    let waveformScale: WaveformScale
    let generateWaveform: Bool
    let generateVectorscope: Bool
    let waveformResolution: Int  // Number of horizontal columns (64, 128, 256)
    let vectorscopeResolution: Int  // Grid size (64, 128)
    
    static let `default` = ColorAnalysisConfig(
        hdrContentType: .sdr,
        waveformScale: .percentage,
        generateWaveform: true,
        generateVectorscope: true,
        waveformResolution: 256,
        vectorscopeResolution: 128
    )
    
    static func forHDR(_ type: HDRContentType) -> ColorAnalysisConfig {
        ColorAnalysisConfig(
            hdrContentType: type,
            waveformScale: type.isHDR ? .nits : .percentage,
            generateWaveform: true,
            generateVectorscope: true,
            waveformResolution: 256,
            vectorscopeResolution: 128
        )
    }
}

// MARK: - Analysis Update

/// Progressive update during color analysis
struct ColorAnalysisUpdate {
    let samples: [FrameColorAnalysis]
    let progress: Double  // 0.0 to 1.0
    let isFinished: Bool
    
    /// Aggregated statistics across all samples
    var aggregatedStats: AggregatedColorStats? {
        guard !samples.isEmpty else { return nil }
        
        let luminances = samples.map { $0.luminance }
        let saturations = samples.map { $0.saturation }
        let temperatures = samples.compactMap { $0.colorTemperature }
        
        return AggregatedColorStats(
            luminanceMin: luminances.map { $0.min }.min() ?? 0,
            luminanceMax: luminances.map { $0.max }.max() ?? 0,
            luminanceAvg: luminances.map { $0.average }.reduce(0, +) / Double(luminances.count),
            saturationAvg: saturations.reduce(0, +) / Double(saturations.count),
            cctAvg: temperatures.isEmpty ? nil : temperatures.map { $0.cct }.reduce(0, +) / Double(temperatures.count),
            cctMin: temperatures.map { $0.cct }.min(),
            cctMax: temperatures.map { $0.cct }.max()
        )
    }
}

/// Aggregated statistics from color analysis
struct AggregatedColorStats {
    let luminanceMin: Double
    let luminanceMax: Double
    let luminanceAvg: Double
    let saturationAvg: Double
    let cctAvg: Double?
    let cctMin: Double?
    let cctMax: Double?
    
    var contrastRatio: Double {
        let effectiveMin = max(luminanceMin, 0.001)
        return luminanceMax / effectiveMin
    }
}
