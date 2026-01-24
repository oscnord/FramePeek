import Foundation

enum FrameType: String, Sendable, Codable {
    case i = "I"
    case p = "P"
    case b = "B"
    case unknown = "?"
}

enum GOPStructureType: Equatable, Sendable, Codable {
    case unknown
    case fixed(frameCount: Int)
    case variable

    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }

    var fixedFrameCount: Int? {
        if case .fixed(let count) = self { return count }
        return nil
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case type, frameCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "fixed":
            let count = try container.decode(Int.self, forKey: .frameCount)
            self = .fixed(frameCount: count)
        case "variable":
            self = .variable
        default:
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unknown:
            try container.encode("unknown", forKey: .type)
        case .fixed(let count):
            try container.encode("fixed", forKey: .type)
            try container.encode(count, forKey: .frameCount)
        case .variable:
            try container.encode("variable", forKey: .type)
        }
    }
}

struct FrameInfo: Identifiable, Sendable, Codable {
    let id: UUID
    let time: Double
    let type: FrameType
    let size: Int64?
    
    init(id: UUID = UUID(), time: Double, type: FrameType, size: Int64? = nil) {
        self.id = id
        self.time = time
        self.type = type
        self.size = size
    }
}

struct GOPSegment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let frameCount: Int?
    let frames: [FrameInfo]?

    var duration: Double { max(0, endTime - startTime) }

    static func == (lhs: GOPSegment, rhs: GOPSegment) -> Bool {
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime &&
        lhs.frameCount == rhs.frameCount
    }
}

struct GOPAnalysisStats: Equatable {
    let gopCount: Int
    let minDuration: Double?
    let avgDuration: Double?
    let maxDuration: Double?
    let minFrameCount: Int?
    let avgFrameCount: Double?
    let maxFrameCount: Int?

    init(segments: [GOPSegment]) {
        gopCount = segments.count

        let durations = segments.map(\.duration).filter { $0.isFinite && $0 > 0 }
        minDuration = durations.min()
        maxDuration = durations.max()
        avgDuration = durations.isEmpty ? nil : (durations.reduce(0, +) / Double(durations.count))

        let frameCounts = segments.compactMap(\.frameCount)
        minFrameCount = frameCounts.min()
        maxFrameCount = frameCounts.max()
        avgFrameCount = frameCounts.isEmpty ? nil : (Double(frameCounts.reduce(0, +)) / Double(frameCounts.count))
    }
}

struct GOPAnalysisResult: Equatable {
    let segments: [GOPSegment]
    let isPreview: Bool
    let scannedUntilSeconds: Double
    let isFinished: Bool
    let stats: GOPAnalysisStats
    let structureType: GOPStructureType
    let representativeGOP: GOPSegment?

    init(
        segments: [GOPSegment],
        isPreview: Bool,
        scannedUntilSeconds: Double,
        isFinished: Bool,
        structureType: GOPStructureType = .unknown,
        representativeGOP: GOPSegment? = nil
    ) {
        self.segments = segments
        self.isPreview = isPreview
        self.scannedUntilSeconds = scannedUntilSeconds
        self.isFinished = isFinished
        self.stats = GOPAnalysisStats(segments: segments)
        self.structureType = structureType
        self.representativeGOP = representativeGOP
    }
}

struct GOPOptions: Sendable {
    let maxScanSeconds: Double?
    let maxGOPs: Int?
    let emitEveryNGOPs: Int
    let detectFrameTypes: Bool
    let timeRange: ClosedRange<Double>?
    let detectFixedStructure: Bool
    let minGOPsForFixedDetection: Int
    let fixedFrameTolerance: Int

    init(
        maxScanSeconds: Double?,
        maxGOPs: Int?,
        emitEveryNGOPs: Int = 25,
        detectFrameTypes: Bool = true,
        timeRange: ClosedRange<Double>? = nil,
        detectFixedStructure: Bool = false,
        minGOPsForFixedDetection: Int = 5,
        fixedFrameTolerance: Int = 1
    ) {
        self.maxScanSeconds = maxScanSeconds
        self.maxGOPs = maxGOPs
        self.emitEveryNGOPs = max(1, emitEveryNGOPs)
        self.detectFrameTypes = detectFrameTypes
        self.timeRange = timeRange
        self.detectFixedStructure = detectFixedStructure
        self.minGOPsForFixedDetection = max(3, minGOPsForFixedDetection)
        self.fixedFrameTolerance = max(0, fixedFrameTolerance)
    }

    static func preview(maxSeconds: Double = 30, maxGOPs: Int = 200, detectFrameTypes: Bool = true, detectFixedStructure: Bool = true) -> GOPOptions {
        GOPOptions(
            maxScanSeconds: maxSeconds,
            maxGOPs: maxGOPs,
            emitEveryNGOPs: 1,
            detectFrameTypes: detectFrameTypes,
            timeRange: nil,
            detectFixedStructure: detectFixedStructure,
            minGOPsForFixedDetection: 5,
            fixedFrameTolerance: 1
        )
    }

    static func fullFile(detectFrameTypes: Bool = true, detectFixedStructure: Bool = false) -> GOPOptions {
        GOPOptions(
            maxScanSeconds: nil,
            maxGOPs: nil,
            emitEveryNGOPs: 50,
            detectFrameTypes: detectFrameTypes,
            timeRange: nil,
            detectFixedStructure: detectFixedStructure
        )
    }

    static func timeRange(_ range: ClosedRange<Double>, detectFrameTypes: Bool = true) -> GOPOptions {
        let duration = range.upperBound - range.lowerBound
        return GOPOptions(
            maxScanSeconds: duration,
            maxGOPs: nil,
            emitEveryNGOPs: 25,
            detectFrameTypes: detectFrameTypes,
            timeRange: range,
            detectFixedStructure: false
        )
    }
}

struct GOPUpdate: Sendable {
    let appendedSegments: [GOPSegment]
    let scannedUntilSeconds: Double
    let isFinished: Bool
    let isPreview: Bool
    let structureType: GOPStructureType
    let detectedFixedFrameCount: Int?
    let representativeGOP: GOPSegment?

    init(
        appendedSegments: [GOPSegment],
        scannedUntilSeconds: Double,
        isFinished: Bool,
        isPreview: Bool,
        structureType: GOPStructureType = .unknown,
        detectedFixedFrameCount: Int? = nil,
        representativeGOP: GOPSegment? = nil
    ) {
        self.appendedSegments = appendedSegments
        self.scannedUntilSeconds = scannedUntilSeconds
        self.isFinished = isFinished
        self.isPreview = isPreview
        self.structureType = structureType
        self.detectedFixedFrameCount = detectedFixedFrameCount
        self.representativeGOP = representativeGOP
    }
}
