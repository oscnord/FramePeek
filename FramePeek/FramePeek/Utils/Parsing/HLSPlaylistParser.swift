import Foundation

// MARK: - Parsed playlist models (RFC 8216)

public enum HLSPlaylist: Sendable {
    case multivariant(HLSMultivariantPlaylist)
    case media(HLSMediaPlaylist)
}

public struct HLSVariantStream: Codable, Sendable, Equatable {
    public let bandwidth: Int
    public let averageBandwidth: Int?
    public let resolutionWidth: Int?
    public let resolutionHeight: Int?
    public let frameRate: Double?
    public let codecs: [String]
    public let uri: String
    public let audioGroupID: String?
    public let subtitlesGroupID: String?
}

public struct HLSRendition: Codable, Sendable, Equatable {
    public let type: String
    public let groupID: String
    public let name: String?
    public let language: String?
    public let uri: String?
    public let isDefault: Bool
}

public struct HLSMultivariantPlaylist: Codable, Sendable {
    public let variants: [HLSVariantStream]
    public let renditions: [HLSRendition]
    public let warnings: [String]
}

public struct HLSByteRange: Codable, Sendable, Equatable {
    public let length: Int
    public let offset: Int?
}

public struct HLSSegment: Codable, Sendable, Equatable {
    public let uri: String
    public let duration: Double
    public let byteRange: HLSByteRange?
    public let discontinuityBefore: Bool
}

public struct HLSKey: Codable, Sendable, Equatable {
    public let method: String
    public let uri: String?

    public var isDRM: Bool {
        method != "NONE"
    }
}

public struct HLSMediaPlaylist: Codable, Sendable {
    public let version: Int?
    public let targetDuration: Int?
    public let playlistType: String?
    public let hasEndList: Bool
    public let initSegmentURI: String?
    public let initSegmentByteRange: HLSByteRange?
    public let keys: [HLSKey]
    public let segments: [HLSSegment]
    public let warnings: [String]

    public var isVOD: Bool {
        hasEndList || playlistType == "VOD"
    }
}

// MARK: - Parser

/// Line-based RFC 8216 playlist parser. Total: malformed input produces
/// warnings on the result, never traps or throws.
public enum HLSPlaylistParser {

    public static func parse(_ text: String) -> HLSPlaylist {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var warnings: [String] = []
        if lines.first != "#EXTM3U" {
            warnings.append("Playlist does not start with #EXTM3U")
        }

        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            return .multivariant(parseMultivariant(lines: lines, warnings: warnings))
        }
        return .media(parseMedia(lines: lines, warnings: warnings))
    }

    public static func resolveURI(_ uri: String, against baseURL: URL) -> URL? {
        URL(string: uri, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: Multivariant

    private static func parseMultivariant(lines: [String], warnings: [String]) -> HLSMultivariantPlaylist {
        var warnings = warnings
        var variants: [HLSVariantStream] = []
        var renditions: [HLSRendition] = []
        var pendingStreamInf: [String: String]?

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                if pendingStreamInf != nil {
                    warnings.append("EXT-X-STREAM-INF without a following URI line")
                }
                pendingStreamInf = parseAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = parseAttributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
                guard let type = attrs["TYPE"], let groupID = attrs["GROUP-ID"] else {
                    warnings.append("EXT-X-MEDIA missing TYPE or GROUP-ID")
                    continue
                }
                renditions.append(HLSRendition(
                    type: type,
                    groupID: groupID,
                    name: attrs["NAME"],
                    language: attrs["LANGUAGE"],
                    uri: attrs["URI"],
                    isDefault: attrs["DEFAULT"] == "YES"
                ))
            } else if line.hasPrefix("#") {
                continue
            } else if let attrs = pendingStreamInf {
                pendingStreamInf = nil
                let bandwidth = attrs["BANDWIDTH"].flatMap { Int($0) }
                if bandwidth == nil {
                    warnings.append("Variant \(line) is missing required BANDWIDTH")
                }
                var width: Int?
                var height: Int?
                if let res = attrs["RESOLUTION"] {
                    let parts = res.lowercased().split(separator: "x")
                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                        width = w
                        height = h
                    } else {
                        warnings.append("Unparseable RESOLUTION \"\(res)\"")
                    }
                }
                variants.append(HLSVariantStream(
                    bandwidth: bandwidth ?? 0,
                    averageBandwidth: attrs["AVERAGE-BANDWIDTH"].flatMap { Int($0) },
                    resolutionWidth: width,
                    resolutionHeight: height,
                    frameRate: attrs["FRAME-RATE"].flatMap { Double($0) },
                    codecs: attrs["CODECS"].map { codecs in
                        codecs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    } ?? [],
                    uri: line,
                    audioGroupID: attrs["AUDIO"],
                    subtitlesGroupID: attrs["SUBTITLES"]
                ))
            }
        }

        if pendingStreamInf != nil {
            warnings.append("EXT-X-STREAM-INF without a following URI line")
        }
        return HLSMultivariantPlaylist(variants: variants, renditions: renditions, warnings: warnings)
    }

    // MARK: Media

    private static func parseMedia(lines: [String], warnings: [String]) -> HLSMediaPlaylist {
        var warnings = warnings
        var version: Int?
        var targetDuration: Int?
        var playlistType: String?
        var hasEndList = false
        var initSegmentURI: String?
        var initSegmentByteRange: HLSByteRange?
        var keys: [HLSKey] = []
        var segments: [HLSSegment] = []

        var pendingDuration: Double?
        var pendingByteRange: HLSByteRange?
        var pendingDiscontinuity = false

        for line in lines {
            if line.hasPrefix("#EXT-X-VERSION:") {
                version = Int(line.dropFirst("#EXT-X-VERSION:".count))
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = Int(line.dropFirst("#EXT-X-TARGETDURATION:".count))
                if targetDuration == nil {
                    warnings.append("Unparseable EXT-X-TARGETDURATION")
                }
            } else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                playlistType = String(line.dropFirst("#EXT-X-PLAYLIST-TYPE:".count))
            } else if line == "#EXT-X-ENDLIST" {
                hasEndList = true
            } else if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count)
                let durationPart = value.split(separator: ",", maxSplits: 1)[0]
                pendingDuration = Double(durationPart)
                if pendingDuration == nil {
                    warnings.append("Unparseable EXTINF duration \"\(durationPart)\"")
                }
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingByteRange = parseByteRange(String(line.dropFirst("#EXT-X-BYTERANGE:".count)))
                if pendingByteRange == nil {
                    warnings.append("Unparseable EXT-X-BYTERANGE")
                }
            } else if line == "#EXT-X-DISCONTINUITY" {
                pendingDiscontinuity = true
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = parseAttributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                initSegmentURI = attrs["URI"]
                initSegmentByteRange = attrs["BYTERANGE"].flatMap { parseByteRange($0) }
                if initSegmentURI == nil {
                    warnings.append("EXT-X-MAP missing URI")
                }
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attrs = parseAttributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                guard let method = attrs["METHOD"] else {
                    warnings.append("EXT-X-KEY missing METHOD")
                    continue
                }
                keys.append(HLSKey(method: method, uri: attrs["URI"]))
            } else if line.hasPrefix("#") {
                continue
            } else {
                if pendingDuration == nil {
                    warnings.append("Segment URI \(line) has no preceding EXTINF")
                }
                segments.append(HLSSegment(
                    uri: line,
                    duration: pendingDuration ?? 0,
                    byteRange: pendingByteRange,
                    discontinuityBefore: pendingDiscontinuity
                ))
                pendingDuration = nil
                pendingByteRange = nil
                pendingDiscontinuity = false
            }
        }

        return HLSMediaPlaylist(
            version: version,
            targetDuration: targetDuration,
            playlistType: playlistType,
            hasEndList: hasEndList,
            initSegmentURI: initSegmentURI,
            initSegmentByteRange: initSegmentByteRange,
            keys: keys,
            segments: segments,
            warnings: warnings
        )
    }

    // MARK: Attribute lists (RFC 8216 section 4.2)

    static func parseAttributes(_ input: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var pairs: [String] = []
        var current = ""
        var inQuotes = false

        for char in input {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char == "," && !inQuotes {
                pairs.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        pairs.append(current)

        for pair in pairs {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            attributes[key] = value
        }
        return attributes
    }

    /// "length[@offset]"
    static func parseByteRange(_ input: String) -> HLSByteRange? {
        let parts = input.split(separator: "@", maxSplits: 1)
        guard let first = parts.first, let length = Int(first) else { return nil }
        let offset = parts.count == 2 ? Int(parts[1]) : nil
        if parts.count == 2 && offset == nil { return nil }
        return HLSByteRange(length: length, offset: offset)
    }
}
