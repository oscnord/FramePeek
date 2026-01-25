import Foundation

// MARK: - Frame Type

/// Type of video frame (I, P, B)
public enum FrameType: String, Sendable, Codable, CaseIterable {
    case i = "I"
    case p = "P"
    case b = "B"
    case unknown = "?"
}

// MARK: - GOP Structure Type

/// Describes the GOP structure pattern
public enum GOPStructureType: Equatable, Sendable, Codable {
    case unknown
    case fixed(frameCount: Int)
    case variable

    public var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }

    public var fixedFrameCount: Int? {
        if case .fixed(let count) = self { return count }
        return nil
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case type, frameCount
    }
    
    public init(from decoder: Decoder) throws {
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
    
    public func encode(to encoder: Encoder) throws {
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

// MARK: - Frame Info

/// Information about a single video frame
public struct FrameInfo: Identifiable, Sendable, Codable {
    public let id: UUID
    public let time: Double
    public let type: FrameType
    public let size: Int64?
    
    public init(id: UUID = UUID(), time: Double, type: FrameType, size: Int64? = nil) {
        self.id = id
        self.time = time
        self.type = type
        self.size = size
    }
}

// MARK: - GOP Segment

/// A single GOP (Group of Pictures) segment
public struct GOPSegment: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let startTime: Double
    public let endTime: Double
    public let frameCount: Int?
    public let frames: [FrameInfo]?

    public var duration: Double { max(0, endTime - startTime) }
    
    public init(id: UUID = UUID(), startTime: Double, endTime: Double, frameCount: Int?, frames: [FrameInfo]?) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.frameCount = frameCount
        self.frames = frames
    }

    public static func == (lhs: GOPSegment, rhs: GOPSegment) -> Bool {
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime &&
        lhs.frameCount == rhs.frameCount
    }
}

// MARK: - GOP Analysis Stats

/// Statistics computed from GOP analysis
public struct GOPAnalysisStats: Equatable, Codable, Sendable {
    public let gopCount: Int
    public let minDuration: Double?
    public let avgDuration: Double?
    public let maxDuration: Double?
    public let minFrameCount: Int?
    public let avgFrameCount: Double?
    public let maxFrameCount: Int?

    public init(segments: [GOPSegment]) {
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
    
    public init(gopCount: Int, minDuration: Double?, avgDuration: Double?, maxDuration: Double?,
                minFrameCount: Int?, avgFrameCount: Double?, maxFrameCount: Int?) {
        self.gopCount = gopCount
        self.minDuration = minDuration
        self.avgDuration = avgDuration
        self.maxDuration = maxDuration
        self.minFrameCount = minFrameCount
        self.avgFrameCount = avgFrameCount
        self.maxFrameCount = maxFrameCount
    }
}

// MARK: - GOP Analysis Result

/// Complete result of GOP analysis
public struct GOPAnalysisResult: Equatable, Codable, Sendable {
    public let segments: [GOPSegment]
    public let isPreview: Bool
    public let scannedUntilSeconds: Double
    public let isFinished: Bool
    public let stats: GOPAnalysisStats
    public let structureType: GOPStructureType
    public let representativeGOP: GOPSegment?

    public init(
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

// MARK: - GOP Options

/// Configuration options for GOP analysis
public struct GOPOptions: Sendable {
    public let maxScanSeconds: Double?
    public let maxGOPs: Int?
    public let emitEveryNGOPs: Int
    public let detectFrameTypes: Bool
    public let timeRange: ClosedRange<Double>?
    public let detectFixedStructure: Bool
    public let minGOPsForFixedDetection: Int
    public let fixedFrameTolerance: Int

    public init(
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

    public static func preview(maxSeconds: Double = 30, maxGOPs: Int = 200, detectFrameTypes: Bool = true, detectFixedStructure: Bool = true) -> GOPOptions {
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

    public static func fullFile(detectFrameTypes: Bool = true, detectFixedStructure: Bool = false) -> GOPOptions {
        GOPOptions(
            maxScanSeconds: nil,
            maxGOPs: nil,
            emitEveryNGOPs: 50,
            detectFrameTypes: detectFrameTypes,
            timeRange: nil,
            detectFixedStructure: detectFixedStructure
        )
    }

    public static func timeRange(_ range: ClosedRange<Double>, detectFrameTypes: Bool = true) -> GOPOptions {
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

// MARK: - GOP Update

/// Progressive update during GOP analysis
public struct GOPUpdate: Sendable {
    public let appendedSegments: [GOPSegment]
    public let scannedUntilSeconds: Double
    public let isFinished: Bool
    public let isPreview: Bool
    public let structureType: GOPStructureType
    public let detectedFixedFrameCount: Int?
    public let representativeGOP: GOPSegment?

    public init(
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
