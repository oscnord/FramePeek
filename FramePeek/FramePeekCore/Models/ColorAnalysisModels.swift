import Foundation

// MARK: - Frame Color Analysis

/// Complete color analysis data for a single frame
public struct FrameColorAnalysis: Identifiable, Sendable {
    public let id: UUID
    public let time: Double
    public let luminance: LuminanceData
    public let colorTemperature: ColorTemperatureData?
    public let saturation: Double  // 0.0-1.0 average saturation
    public let histogram: ColorHistogram
    public let waveformData: WaveformData?
    public let vectorscopeData: VectorscopeData?
    public let exposureStatus: ExposureStatus
    
    public init(id: UUID = UUID(), time: Double, luminance: LuminanceData,
                colorTemperature: ColorTemperatureData?, saturation: Double,
                histogram: ColorHistogram, waveformData: WaveformData? = nil,
                vectorscopeData: VectorscopeData? = nil, exposureStatus: ExposureStatus) {
        self.id = id
        self.time = time
        self.luminance = luminance
        self.colorTemperature = colorTemperature
        self.saturation = saturation
        self.histogram = histogram
        self.waveformData = waveformData
        self.vectorscopeData = vectorscopeData
        self.exposureStatus = exposureStatus
    }
}

// MARK: - Luminance Data

/// Luminance statistics for a frame
public struct LuminanceData: Codable, Sendable {
    public let min: Double           // 0.0-1.0 normalized
    public let max: Double           // 0.0-1.0 normalized
    public let average: Double       // 0.0-1.0 normalized
    public let percentile98: Double  // Peak detection (ignores specular/noise)
    public let percentile02: Double  // Shadow detection
    
    public init(min: Double, max: Double, average: Double, percentile98: Double, percentile02: Double) {
        self.min = min
        self.max = max
        self.average = average
        self.percentile98 = percentile98
        self.percentile02 = percentile02
    }
    
    /// Contrast ratio (max/min, excluding pure black)
    public var contrastRatio: Double {
        let effectiveMin = Swift.max(min, 0.001) // Avoid division by zero
        return self.max / effectiveMin
    }
    
    /// Luminance in nits (requires HDR EOTF conversion upstream)
    public struct Nits: Codable, Sendable {
        public let min: Double
        public let max: Double
        public let average: Double
        public let peak: Double  // 98th percentile
        
        public init(min: Double, max: Double, average: Double, peak: Double) {
            self.min = min
            self.max = max
            self.average = average
            self.peak = peak
        }
    }
}

// MARK: - Color Temperature Data

/// Color temperature calculated using McCamy's formula
public struct ColorTemperatureData: Codable, Sendable {
    public let cct: Double        // Correlated Color Temperature in Kelvin
    public let duv: Double        // Delta uv (distance from Planckian locus) - indicates tint
    public let confidence: Double // 0.0-1.0 (low for highly saturated or unusual colors)
    
    public init(cct: Double, duv: Double, confidence: Double) {
        self.cct = cct
        self.duv = duv
        self.confidence = confidence
    }
    
    /// Human-readable description of the color temperature
    public var temperatureDescription: String {
        if cct < 3500 {
            return "Warm (Tungsten)"
        } else if cct < 4500 {
            return "Warm White"
        } else if cct < 5500 {
            return "Neutral"
        } else if cct < 6500 {
            return "Daylight"
        } else if cct < 7500 {
            return "Cool Daylight"
        } else {
            return "Cool (Overcast/Shade)"
        }
    }
    
    /// Tint description based on Duv
    public var tintDescription: String? {
        if abs(duv) < 0.003 {
            return nil // On Planckian locus, no significant tint
        } else if duv > 0 {
            return "Green tint"
        } else {
            return "Magenta tint"
        }
    }
}

// MARK: - Waveform Data

/// Traditional broadcast-style waveform data
public struct WaveformData: Sendable {
    /// Each column represents a horizontal position in the frame
    /// Contains histogram of luminance values at that position
    /// columns[x][y] = intensity at horizontal position x, luminance level y
    public let columns: [[Double]]  // [256 columns][256 luminance bins]
    public let channelMode: WaveformChannel
    
    public init(columns: [[Double]], channelMode: WaveformChannel) {
        self.columns = columns
        self.channelMode = channelMode
    }
    
    /// Number of horizontal columns
    public var columnCount: Int { columns.count }
    
    /// Number of luminance levels per column
    public var levelCount: Int { columns.first?.count ?? 256 }
}

/// Waveform channel display modes
public enum WaveformChannel: String, CaseIterable, Identifiable, Codable, Sendable {
    case luma = "Luma"
    case rgb = "RGB"
    case parade = "Parade"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .luma: return "Luminance"
        case .rgb: return "RGB Overlay"
        case .parade: return "RGB Parade"
        }
    }
}

/// Waveform scale options
public enum WaveformScale: String, CaseIterable, Identifiable, Codable, Sendable {
    case ire = "IRE"
    case percentage = "Percentage"
    case nits = "Nits"
    case logNits = "Log Nits"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .ire: return "IRE (0-100+)"
        case .percentage: return "% (0-100)"
        case .nits: return "Nits (HDR)"
        case .logNits: return "Log Nits (HDR)"
        }
    }
    
    /// Whether this scale is appropriate for SDR content
    public var isSuitableForSDR: Bool {
        switch self {
        case .ire, .percentage: return true
        case .nits, .logNits: return false
        }
    }
    
    /// Maximum value for this scale (SDR reference)
    public var maxValueSDR: Double {
        switch self {
        case .ire: return 109.0 // 109 IRE = 100% white + super-white
        case .percentage: return 100.0
        case .nits: return 100.0 // SDR reference white
        case .logNits: return 2.0 // log10(100)
        }
    }
    
    /// Maximum value for this scale (HDR)
    public var maxValueHDR: Double {
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
public struct VectorscopeData: Sendable {
    /// Points in UV space with intensity
    /// u, v are normalized to -0.5 to 0.5 range
    public let points: [VectorscopePoint]
    
    /// Aggregated grid for efficient rendering (64x64 or 128x128)
    public let grid: [[Double]]?  // Intensity at each grid position
    public let gridSize: Int
    
    public init(points: [VectorscopePoint], gridSize: Int = 128) {
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
public struct VectorscopePoint: Sendable {
    public let u: Double      // -0.5 to 0.5 (Cb/blue-yellow axis)
    public let v: Double      // -0.5 to 0.5 (Cr/red-cyan axis)
    public let intensity: Double  // Weight/count for this color
    
    public init(u: Double, v: Double, intensity: Double) {
        self.u = u
        self.v = v
        self.intensity = intensity
    }
}

// MARK: - Exposure Status

/// Exposure assessment for a frame
public enum ExposureStatus: String, CaseIterable, Codable, Sendable {
    case underexposed = "Underexposed"
    case slightlyUnder = "Slightly Under"
    case properlyExposed = "Properly Exposed"
    case slightlyOver = "Slightly Over"
    case overexposed = "Overexposed"
    case clipped = "Clipped"
    case highDynamicRange = "High Dynamic Range"
    
    public var displayName: String {
        switch self {
        case .underexposed: return "Underexposed"
        case .slightlyUnder: return "Slightly Under"
        case .properlyExposed: return "Properly Exposed"
        case .slightlyOver: return "Slightly Over"
        case .overexposed: return "Overexposed"
        case .clipped: return "Clipped"
        case .highDynamicRange: return "High DR"
        }
    }
    
    public var color: String {
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
    
    public var symbolName: String {
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
public enum HDRContentType: String, CaseIterable, Codable, Sendable {
    case sdr = "SDR"
    case hdr10 = "HDR10"
    case hlg = "HLG"
    case dolbyVision = "Dolby Vision"
    case pq = "PQ (Generic)"
    
    public var displayName: String {
        switch self {
        case .sdr: return "SDR"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "Dolby Vision"
        case .pq: return "PQ (ST.2084)"
        }
    }
    
    public var isHDR: Bool {
        self != .sdr
    }
    
    public var usesPQ: Bool {
        switch self {
        case .hdr10, .dolbyVision, .pq: return true
        case .sdr, .hlg: return false
        }
    }
    
    public var usesHLG: Bool {
        self == .hlg
    }
    
    /// Maximum luminance in nits for this content type
    public var maxNits: Double {
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
public struct ColorAnalysisConfig: Sendable {
    public let hdrContentType: HDRContentType
    public let waveformScale: WaveformScale
    public let generateWaveform: Bool
    public let generateVectorscope: Bool
    public let waveformResolution: Int  // Number of horizontal columns (64, 128, 256)
    public let vectorscopeResolution: Int  // Grid size (64, 128)
    
    public init(hdrContentType: HDRContentType, waveformScale: WaveformScale,
                generateWaveform: Bool, generateVectorscope: Bool,
                waveformResolution: Int, vectorscopeResolution: Int) {
        self.hdrContentType = hdrContentType
        self.waveformScale = waveformScale
        self.generateWaveform = generateWaveform
        self.generateVectorscope = generateVectorscope
        self.waveformResolution = waveformResolution
        self.vectorscopeResolution = vectorscopeResolution
    }
    
    public static let `default` = ColorAnalysisConfig(
        hdrContentType: .sdr,
        waveformScale: .percentage,
        generateWaveform: true,
        generateVectorscope: true,
        waveformResolution: 256,
        vectorscopeResolution: 128
    )
    
    public static func forHDR(_ type: HDRContentType) -> ColorAnalysisConfig {
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
public struct ColorAnalysisUpdate: Sendable {
    public let samples: [FrameColorAnalysis]
    public let progress: Double  // 0.0 to 1.0
    public let isFinished: Bool
    
    public init(samples: [FrameColorAnalysis], progress: Double, isFinished: Bool) {
        self.samples = samples
        self.progress = progress
        self.isFinished = isFinished
    }
    
    /// Aggregated statistics across all samples
    public var aggregatedStats: AggregatedColorStats? {
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
public struct AggregatedColorStats: Codable, Sendable {
    public let luminanceMin: Double
    public let luminanceMax: Double
    public let luminanceAvg: Double
    public let saturationAvg: Double
    public let cctAvg: Double?
    public let cctMin: Double?
    public let cctMax: Double?
    
    public init(luminanceMin: Double, luminanceMax: Double, luminanceAvg: Double,
                saturationAvg: Double, cctAvg: Double?, cctMin: Double?, cctMax: Double?) {
        self.luminanceMin = luminanceMin
        self.luminanceMax = luminanceMax
        self.luminanceAvg = luminanceAvg
        self.saturationAvg = saturationAvg
        self.cctAvg = cctAvg
        self.cctMin = cctMin
        self.cctMax = cctMax
    }
    
    public var contrastRatio: Double {
        let effectiveMin = max(luminanceMin, 0.001)
        return luminanceMax / effectiveMin
    }
}
