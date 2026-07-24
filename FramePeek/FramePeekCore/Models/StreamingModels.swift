import Foundation

// MARK: - Findings

public enum StreamingFindingSeverity: String, Codable, Sendable, CaseIterable {
    case error
    case warning
    case info
}

public struct StreamingFinding: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(kind)|\(variantURI ?? "")|\(message)" }
    public let severity: StreamingFindingSeverity
    public let kind: String
    public let message: String
    public let variantURI: String?

    public init(severity: StreamingFindingSeverity, kind: String, message: String, variantURI: String? = nil) {
        self.severity = severity
        self.kind = kind
        self.message = message
        self.variantURI = variantURI
    }
}

// MARK: - Per-variant report

public struct StreamingSegmentStats: Codable, Sendable, Equatable {
    public let count: Int
    public let minDuration: Double
    public let maxDuration: Double
    public let averageDuration: Double

    public init(count: Int, minDuration: Double, maxDuration: Double, averageDuration: Double) {
        self.count = count
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.averageDuration = averageDuration
    }
}

public struct StreamingVariantReport: Codable, Sendable, Identifiable, Equatable {
    public var id: String { uri }
    public let uri: String
    public let declaredBandwidth: Int
    public let declaredAverageBandwidth: Int?
    public let resolutionWidth: Int?
    public let resolutionHeight: Int?
    public let frameRate: Double?
    public let codecs: [String]
    public let measuredPeakBitrate: Double?
    public let measuredAverageBitrate: Double?
    public let sampledSegmentCount: Int
    public let segmentStats: StreamingSegmentStats?
    public let isDRMProtected: Bool
    public let keyframeTimes: [Double]

    public init(
        uri: String,
        declaredBandwidth: Int,
        declaredAverageBandwidth: Int?,
        resolutionWidth: Int?,
        resolutionHeight: Int?,
        frameRate: Double?,
        codecs: [String],
        measuredPeakBitrate: Double?,
        measuredAverageBitrate: Double?,
        sampledSegmentCount: Int,
        segmentStats: StreamingSegmentStats?,
        isDRMProtected: Bool,
        keyframeTimes: [Double]
    ) {
        self.uri = uri
        self.declaredBandwidth = declaredBandwidth
        self.declaredAverageBandwidth = declaredAverageBandwidth
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.frameRate = frameRate
        self.codecs = codecs
        self.measuredPeakBitrate = measuredPeakBitrate
        self.measuredAverageBitrate = measuredAverageBitrate
        self.sampledSegmentCount = sampledSegmentCount
        self.segmentStats = segmentStats
        self.isDRMProtected = isDRMProtected
        self.keyframeTimes = keyframeTimes
    }
}

// MARK: - Ladder analysis result

public struct StreamingLadderAnalysis: Codable, Sendable {
    public let sourceURL: String
    public let isVOD: Bool
    public let variants: [StreamingVariantReport]
    public let findings: [StreamingFinding]

    public init(sourceURL: String, isVOD: Bool, variants: [StreamingVariantReport], findings: [StreamingFinding]) {
        self.sourceURL = sourceURL
        self.isVOD = isVOD
        self.variants = variants
        self.findings = findings
    }

    public func findings(withSeverity severity: StreamingFindingSeverity) -> [StreamingFinding] {
        findings.filter { $0.severity == severity }
    }
}
