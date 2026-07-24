import AVFoundation
import CoreMedia
import Foundation

public struct HLSLadderProgress: Sendable {
    public let message: String
    public let result: StreamingLadderAnalysis?

    public init(message: String, result: StreamingLadderAnalysis? = nil) {
        self.message = message
        self.result = result
    }
}

/// Analyzes an HLS ladder (local or remote multivariant playlist): parses the
/// manifests, samples segments per variant, and produces findings for
/// bandwidth, segment-duration, keyframe-alignment, codec, and ladder-shape
/// problems. Media-playlist URLs are analyzed as a single-variant ladder.
public func analyzeHLSLadder(
    url: URL,
    segmentSampleCount: Int = 5
) -> AsyncStream<HLSLadderProgress> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let analyzer = HLSLadderAnalyzer(sourceURL: url, segmentSampleCount: segmentSampleCount)
            let result = await analyzer.run { message in
                continuation.yield(HLSLadderProgress(message: message))
            }
            continuation.yield(HLSLadderProgress(message: "Complete", result: result))
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

struct HLSLadderAnalyzer {
    let sourceURL: URL
    let segmentSampleCount: Int

    struct VariantAnalysis {
        let report: StreamingVariantReport
        let findings: [StreamingFinding]
        let containerKind: String
    }

    func run(onProgress: @escaping @Sendable (String) -> Void) async -> StreamingLadderAnalysis {
        let masterText: String
        do {
            masterText = try await loadText(sourceURL)
        } catch {
            return StreamingLadderAnalysis(
                sourceURL: sourceURL.absoluteString,
                isVOD: false,
                variants: [],
                findings: [StreamingFinding(
                    severity: .error,
                    kind: "playlist-unreachable",
                    message: "Could not load playlist: \(error.localizedDescription)"
                )]
            )
        }

        switch HLSPlaylistParser.parse(masterText) {
        case .multivariant(let master):
            return await analyzeLadder(master: master, onProgress: onProgress)
        case .media(let media):
            var findings = media.warnings.map(parserWarningFinding)
            findings.append(StreamingFinding(
                severity: .info,
                kind: "not-multivariant",
                message: "URL is a media playlist, not a multivariant playlist; analyzing as a single variant"
            ))
            let placeholder = HLSVariantStream(
                bandwidth: 0, averageBandwidth: nil,
                resolutionWidth: nil, resolutionHeight: nil,
                frameRate: nil, codecs: [], uri: sourceURL.lastPathComponent,
                audioGroupID: nil, subtitlesGroupID: nil
            )
            let analysis = await analyzeVariant(placeholder, playlist: media, playlistURL: sourceURL)
            return StreamingLadderAnalysis(
                sourceURL: sourceURL.absoluteString,
                isVOD: media.isVOD,
                variants: [analysis.report],
                findings: findings + analysis.findings
            )
        }
    }

    // MARK: - Ladder

    private func analyzeLadder(
        master: HLSMultivariantPlaylist,
        onProgress: @escaping @Sendable (String) -> Void
    ) async -> StreamingLadderAnalysis {
        var findings = master.warnings.map(parserWarningFinding)
        findings += ladderShapeFindings(master: master)

        var analyses: [Int: VariantAnalysis] = [:]
        var isVOD = false

        let width = min(4, max(1, master.variants.count))
        await withTaskGroup(of: (Int, VariantAnalysis, Bool)?.self) { group in
            var nextIndex = 0
            var completed = 0

            func addNext(_ group: inout TaskGroup<(Int, VariantAnalysis, Bool)?>) {
                guard nextIndex < master.variants.count else { return }
                let index = nextIndex
                let variant = master.variants[index]
                nextIndex += 1
                group.addTask {
                    guard !Task.isCancelled,
                          let playlistURL = HLSPlaylistParser.resolveURI(variant.uri, against: sourceURL) else {
                        return nil
                    }
                    guard let text = try? await loadText(playlistURL),
                          case .media(let media) = HLSPlaylistParser.parse(text) else {
                        let finding = StreamingFinding(
                            severity: .error,
                            kind: "variant-unreachable",
                            message: "Could not load or parse media playlist",
                            variantURI: variant.uri
                        )
                        return (index, VariantAnalysis(
                            report: emptyReport(for: variant),
                            findings: [finding],
                            containerKind: "unknown"
                        ), false)
                    }
                    let analysis = await analyzeVariant(variant, playlist: media, playlistURL: playlistURL)
                    return (index, analysis, media.isVOD)
                }
            }

            for _ in 0..<width { addNext(&group) }
            while let outcome = await group.next() {
                if let (index, analysis, vod) = outcome {
                    analyses[index] = analysis
                    isVOD = isVOD || vod
                }
                completed += 1
                onProgress("Analyzed variant \(completed)/\(master.variants.count)")
                addNext(&group)
            }
        }

        let ordered = master.variants.indices.compactMap { analyses[$0] }
        findings += ordered.flatMap(\.findings)
        findings += crossVariantFindings(ordered)

        return StreamingLadderAnalysis(
            sourceURL: sourceURL.absoluteString,
            isVOD: isVOD,
            variants: ordered.map(\.report),
            findings: findings
        )
    }

    private func ladderShapeFindings(master: HLSMultivariantPlaylist) -> [StreamingFinding] {
        var findings: [StreamingFinding] = []

        let sorted = master.variants.sorted { $0.bandwidth < $1.bandwidth }
        var lastPixels = 0
        for variant in sorted {
            guard let w = variant.resolutionWidth, let h = variant.resolutionHeight else { continue }
            let pixels = w * h
            if pixels < lastPixels {
                findings.append(StreamingFinding(
                    severity: .warning,
                    kind: "ladder-resolution-inversion",
                    message: "Resolution \(w)x\(h) decreases while bandwidth increases",
                    variantURI: variant.uri
                ))
            }
            lastPixels = max(lastPixels, pixels)
        }

        let bandwidths = master.variants.map(\.bandwidth)
        for bandwidth in Set(bandwidths.filter { b in bandwidths.count(where: { $0 == b }) > 1 }) {
            findings.append(StreamingFinding(
                severity: .warning,
                kind: "ladder-duplicate-bandwidth",
                message: "Multiple variants declare BANDWIDTH=\(bandwidth)"
            ))
        }

        let groupIDs = Set(master.renditions.map(\.groupID))
        for variant in master.variants {
            for group in [variant.audioGroupID, variant.subtitlesGroupID].compactMap({ $0 })
            where !groupIDs.contains(group) {
                findings.append(StreamingFinding(
                    severity: .error,
                    kind: "missing-rendition-group",
                    message: "References rendition group \"\(group)\" that has no EXT-X-MEDIA entry",
                    variantURI: variant.uri
                ))
            }
        }

        return findings
    }

    private func crossVariantFindings(_ analyses: [VariantAnalysis]) -> [StreamingFinding] {
        var findings: [StreamingFinding] = []

        let kinds = Set(analyses.map(\.containerKind).filter { $0 != "unknown" })
        if kinds.count > 1 {
            findings.append(StreamingFinding(
                severity: .warning,
                kind: "ladder-mixed-containers",
                message: "Variants mix segment container types (\(kinds.sorted().joined(separator: ", ")))"
            ))
        }

        let alignable = analyses.filter { !$0.report.isDRMProtected && !$0.report.keyframeTimes.isEmpty }
        guard let reference = alignable.first else { return findings }
        let tolerance = 1.5 / (reference.report.frameRate ?? 25.0)

        for other in alignable.dropFirst() {
            let misaligned = reference.report.keyframeTimes.contains { refTime in
                !other.report.keyframeTimes.contains { abs($0 - refTime) <= tolerance }
            }
            if misaligned {
                findings.append(StreamingFinding(
                    severity: .error,
                    kind: "keyframe-misalignment",
                    message: "Keyframe positions do not match \(reference.report.uri) within one frame duration; seamless ABR switching will break",
                    variantURI: other.report.uri
                ))
            }
        }

        return findings
    }

    // MARK: - Single variant

    private func analyzeVariant(
        _ variant: HLSVariantStream,
        playlist: HLSMediaPlaylist,
        playlistURL: URL
    ) async -> VariantAnalysis {
        var findings = playlist.warnings.map { parserWarningFinding($0, variantURI: variant.uri) }
        findings += segmentDurationFindings(playlist: playlist, variantURI: variant.uri)

        let isDRM = playlist.keys.contains(where: \.isDRM)
        if isDRM {
            let methods = playlist.keys.filter(\.isDRM).map(\.method).joined(separator: ", ")
            findings.append(StreamingFinding(
                severity: .info,
                kind: "drm-detected",
                message: "Content is encrypted (\(methods)); bitrate is measured, keyframe and codec checks are skipped",
                variantURI: variant.uri
            ))
        }

        let durations = playlist.segments.map(\.duration)
        let stats = durations.isEmpty ? nil : StreamingSegmentStats(
            count: durations.count,
            minDuration: durations.min() ?? 0,
            maxDuration: durations.max() ?? 0,
            averageDuration: durations.reduce(0, +) / Double(durations.count)
        )

        let containerKind: String
        if playlist.initSegmentURI != nil {
            containerKind = "fmp4"
        } else if playlist.segments.first.map({ $0.uri.lowercased().hasSuffix(".ts") }) == true {
            containerKind = "ts"
        } else {
            containerKind = "unknown"
        }

        let sampled = Array(playlist.segments.prefix(segmentSampleCount))
        var measuredPeak: Double?
        var measuredAverage: Double?
        var keyframeTimes: [Double] = []

        download: do {
            var initData = Data()
            if let initURI = playlist.initSegmentURI {
                guard let initURL = HLSPlaylistParser.resolveURI(initURI, against: playlistURL),
                      let data = try? await loadData(initURL, byteRange: playlist.initSegmentByteRange) else {
                    findings.append(StreamingFinding(
                        severity: .error,
                        kind: "init-segment-unreachable",
                        message: "Could not load init segment",
                        variantURI: variant.uri
                    ))
                    break download
                }
                initData = data
            }

            var segmentData: [Data] = []
            for segment in sampled {
                if Task.isCancelled { break download }
                guard let segmentURL = HLSPlaylistParser.resolveURI(segment.uri, against: playlistURL),
                      let data = try? await loadData(segmentURL, byteRange: segment.byteRange) else {
                    findings.append(StreamingFinding(
                        severity: .error,
                        kind: "segment-unreachable",
                        message: "Could not load segment \(segment.uri)",
                        variantURI: variant.uri
                    ))
                    break download
                }
                segmentData.append(data)
            }

            var peak = 0.0
            var totalBits = 0.0
            var totalDuration = 0.0
            for (segment, data) in zip(sampled, segmentData) where segment.duration > 0 {
                let bits = Double(data.count) * 8
                peak = max(peak, bits / segment.duration)
                totalBits += bits
                totalDuration += segment.duration
            }
            if totalDuration > 0 {
                measuredPeak = peak
                measuredAverage = totalBits / totalDuration
            }
            findings += bandwidthFindings(
                variant: variant,
                peak: measuredPeak,
                average: measuredAverage,
                sampledCount: sampled.count,
                totalCount: playlist.segments.count
            )

            if !isDRM {
                let assetFindings = await inspectConcatenatedAsset(
                    initData: initData,
                    segmentData: segmentData,
                    sampled: sampled,
                    containerKind: containerKind,
                    variant: variant,
                    keyframeTimes: &keyframeTimes
                )
                findings += assetFindings
            }
        }

        let report = StreamingVariantReport(
            uri: variant.uri,
            declaredBandwidth: variant.bandwidth,
            declaredAverageBandwidth: variant.averageBandwidth,
            resolutionWidth: variant.resolutionWidth,
            resolutionHeight: variant.resolutionHeight,
            frameRate: variant.frameRate,
            codecs: variant.codecs,
            measuredPeakBitrate: measuredPeak,
            measuredAverageBitrate: measuredAverage,
            sampledSegmentCount: sampled.count,
            segmentStats: stats,
            isDRMProtected: isDRM,
            keyframeTimes: keyframeTimes
        )
        return VariantAnalysis(report: report, findings: findings, containerKind: containerKind)
    }

    private func segmentDurationFindings(playlist: HLSMediaPlaylist, variantURI: String) -> [StreamingFinding] {
        var findings: [StreamingFinding] = []

        if let target = playlist.targetDuration {
            for segment in playlist.segments where Int(segment.duration.rounded()) > target {
                findings.append(StreamingFinding(
                    severity: .error,
                    kind: "segment-exceeds-target-duration",
                    message: "Segment \(segment.uri) duration \(String(format: "%.3f", segment.duration))s exceeds EXT-X-TARGETDURATION \(target)",
                    variantURI: variantURI
                ))
            }
        } else if !playlist.segments.isEmpty {
            findings.append(StreamingFinding(
                severity: .error,
                kind: "missing-target-duration",
                message: "Media playlist has no EXT-X-TARGETDURATION",
                variantURI: variantURI
            ))
        }

        let body = playlist.segments.dropLast().map(\.duration)
        if body.count >= 3 {
            let mean = body.reduce(0, +) / Double(body.count)
            let variance = body.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(body.count)
            if mean > 0, variance.squareRoot() / mean > 0.15 {
                findings.append(StreamingFinding(
                    severity: .warning,
                    kind: "jittery-segmentation",
                    message: "Segment durations vary widely (mean \(String(format: "%.2f", mean))s, stddev \(String(format: "%.2f", variance.squareRoot()))s); uneven segments hurt ABR",
                    variantURI: variantURI
                ))
            }
        }

        return findings
    }

    private func bandwidthFindings(
        variant: HLSVariantStream,
        peak: Double?,
        average: Double?,
        sampledCount: Int,
        totalCount: Int
    ) -> [StreamingFinding] {
        var findings: [StreamingFinding] = []
        let scope = "sampled \(sampledCount) of \(totalCount) segments"

        if let peak, variant.bandwidth > 0, peak > Double(variant.bandwidth) * 1.01 {
            findings.append(StreamingFinding(
                severity: .error,
                kind: "bandwidth-exceeded",
                message: "Measured peak segment bitrate \(Int(peak)) bps exceeds declared BANDWIDTH \(variant.bandwidth) (RFC 8216: BANDWIDTH must be an upper bound; \(scope))",
                variantURI: variant.uri
            ))
        }
        if let average, let declared = variant.averageBandwidth, declared > 0 {
            let deviation = abs(average - Double(declared)) / Double(declared)
            if deviation > 0.15 {
                findings.append(StreamingFinding(
                    severity: .warning,
                    kind: "average-bandwidth-deviation",
                    message: "Measured average bitrate \(Int(average)) bps deviates \(Int(deviation * 100))% from declared AVERAGE-BANDWIDTH \(declared) (\(scope))",
                    variantURI: variant.uri
                ))
            }
        }
        return findings
    }

    // MARK: - Concatenated-asset checks (keyframes, codecs)

    private func inspectConcatenatedAsset(
        initData: Data,
        segmentData: [Data],
        sampled: [HLSSegment],
        containerKind: String,
        variant: HLSVariantStream,
        keyframeTimes: inout [Double]
    ) async -> [StreamingFinding] {
        guard !segmentData.isEmpty else { return [] }

        var findings: [StreamingFinding] = []
        var concatenated = initData
        for data in segmentData { concatenated.append(data) }

        let fileExtension = containerKind == "ts" ? "ts" : "mp4"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("framepeek-hls-\(UUID().uuidString).\(fileExtension)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try concatenated.write(to: tempURL)
        } catch {
            return []
        }

        let asset = AVURLAsset(url: tempURL)

        for await markers in extractKeyframesStream(asset: asset) {
            keyframeTimes.append(contentsOf: markers.map(\.time))
        }
        keyframeTimes.sort()

        let frameDuration = 1.5 / (variant.frameRate ?? 25.0)
        var boundary = keyframeTimes.first ?? 0
        for segment in sampled {
            let aligned = keyframeTimes.contains { abs($0 - boundary) <= frameDuration }
            if !aligned {
                findings.append(StreamingFinding(
                    severity: .error,
                    kind: "segment-not-keyframe-aligned",
                    message: "Segment \(segment.uri) does not start on a keyframe (expected near \(String(format: "%.3f", boundary))s)",
                    variantURI: variant.uri
                ))
            }
            boundary += segment.duration
        }

        findings += await codecFindings(asset: asset, variant: variant)
        return findings
    }

    private func codecFindings(asset: AVAsset, variant: HLSVariantStream) async -> [StreamingFinding] {
        guard !variant.codecs.isEmpty,
              let track = await AVAssetLoader.firstTrack(of: asset, mediaType: .video),
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first else {
            return []
        }

        let fourcc = fourCCString(CMFormatDescriptionGetMediaSubType(description))
        let declaredVideo = variant.codecs.first {
            ["avc1", "avc3", "hvc1", "hev1", "av01", "vp09", "dvh1", "dvhe"].contains(String($0.prefix(4)))
        }
        guard let declaredVideo else { return [] }
        let declaredFourCC = String(declaredVideo.prefix(4))

        let compatible: Set<Set<String>> = [["avc1", "avc3"], ["hvc1", "hev1"]]
        let matches = fourcc == declaredFourCC
            || compatible.contains { $0.contains(fourcc) && $0.contains(declaredFourCC) }
        if !matches {
            return [StreamingFinding(
                severity: .error,
                kind: "codec-mismatch",
                message: "CODECS declares \(declaredVideo) but segments contain \(fourcc)",
                variantURI: variant.uri
            )]
        }

        if declaredFourCC == "avc1" || declaredFourCC == "avc3" {
            let atoms = CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
            ) as? [String: Any]
            if let avcC = atoms?["avcC"] as? Data, avcC.count >= 4 {
                let actual = String(format: "%02x%02x%02x", avcC[1], avcC[2], avcC[3])
                let declaredSuffix = declaredVideo.split(separator: ".").dropFirst().joined().lowercased()
                if declaredSuffix.count == 6, declaredSuffix != actual {
                    return [StreamingFinding(
                        severity: .warning,
                        kind: "codec-profile-mismatch",
                        message: "CODECS declares \(declaredVideo) but segments contain avc1.\(actual)",
                        variantURI: variant.uri
                    )]
                }
            }
        }

        return []
    }

    // MARK: - Helpers

    private func emptyReport(for variant: HLSVariantStream) -> StreamingVariantReport {
        StreamingVariantReport(
            uri: variant.uri,
            declaredBandwidth: variant.bandwidth,
            declaredAverageBandwidth: variant.averageBandwidth,
            resolutionWidth: variant.resolutionWidth,
            resolutionHeight: variant.resolutionHeight,
            frameRate: variant.frameRate,
            codecs: variant.codecs,
            measuredPeakBitrate: nil,
            measuredAverageBitrate: nil,
            sampledSegmentCount: 0,
            segmentStats: nil,
            isDRMProtected: false,
            keyframeTimes: []
        )
    }

    private func parserWarningFinding(_ warning: String) -> StreamingFinding {
        parserWarningFinding(warning, variantURI: nil)
    }

    private func parserWarningFinding(_ warning: String, variantURI: String?) -> StreamingFinding {
        StreamingFinding(severity: .warning, kind: "playlist-syntax", message: warning, variantURI: variantURI)
    }

    private func loadText(_ url: URL) async throws -> String {
        let data = try await loadData(url, byteRange: nil)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private func loadData(_ url: URL, byteRange: HLSByteRange?) async throws -> Data {
        var data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            data = body
        }
        if let byteRange {
            let start = byteRange.offset ?? 0
            let end = min(start + byteRange.length, data.count)
            guard start >= 0, start < end else { throw URLError(.dataLengthExceedsMaximum) }
            data = data.subdata(in: start..<end)
        }
        return data
    }

    private func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
