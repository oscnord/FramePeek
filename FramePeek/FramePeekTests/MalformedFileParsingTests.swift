import Testing
import Foundation
import AVFoundation
@testable import FramePeekCore

/// Regression tests for parser hardening against malformed/hostile media files.
/// Each case previously crashed (arithmetic overflow trap) or misbehaved.
struct MalformedFileParsingTests {

    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url)
        return url
    }

    // MARK: - Exp-Golomb overflow (VUIParser.readUE)

    @Test func avcMaxBitrate_expGolomb32LeadingZeros_returnsNilWithoutCrashing() {
        // avcC: version/profile/compat/level/lengthSize, numSPS=1, SPS length, SPS payload.
        // SPS payload after the 4 header bytes hits readUE() with exactly 32 leading
        // zero bits followed by a 1 bit and 32 more bits: (1 << 32) - 1 used to trap.
        let sps: [UInt8] = [
            0x67, 66, 0x00, 30,
            0x00, 0x00, 0x00, 0x00,  // 32 leading zeros
            0x80,                    // terminating 1 bit
            0x00, 0x00, 0x00, 0x00,  // 32 suffix bits
        ]
        var avcC: [UInt8] = [0x01, 66, 0x00, 30, 0xFF, 0xE1]
        avcC += [UInt8(sps.count >> 8), UInt8(sps.count & 0xFF)]
        avcC += sps

        #expect(parseAVCMaxBitrate(Data(avcC)) == nil)
    }

    @Test func avcMaxBitrate_allZeroSPS_returnsNil() {
        let sps = [UInt8](repeating: 0, count: 32)
        var avcC: [UInt8] = [0x01, 66, 0x00, 30, 0xFF, 0xE1]
        avcC += [UInt8(sps.count >> 8), UInt8(sps.count & 0xFF)]
        avcC += sps

        #expect(parseAVCMaxBitrate(Data(avcC)) == nil)
    }

    // MARK: - av1C marker/version validation

    @Test func av1Parser_validMarkerAndVersion_parses() {
        // 0x81 marker+version, profile 0 / level 8 (4.0), 10-bit 4:2:0
        let av1C = Data([0x81, 0b0000_1000, 0b0100_1100, 0x00])
        let summary = parseAV1C(av1C)
        #expect(summary != nil)
        #expect(summary?.profile == 0)
        #expect(summary?.bitDepth == 10)
        #expect(summary?.chromaSubsampling == "4:2:0")
    }

    @Test func av1Parser_invalidMarker_returnsNil() {
        #expect(parseAV1C(Data([0x00, 0x08, 0x4C, 0x00])) == nil)
        #expect(parseAV1C(Data([0x82, 0x08, 0x4C, 0x00])) == nil)
    }

    // MARK: - Atom size overflow (SyncSampleParser)

    @Test func syncSampleParser_hugeLargesize_returnsNilWithoutCrashing() async throws {
        // One atom with size==1 and a 64-bit largesize of UInt64.max:
        // advancing the scan offset used to overflow-trap.
        var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        bytes += Array("moov".utf8)
        bytes += [UInt8](repeating: 0xFF, count: 8)
        let url = try temporaryFile(named: "huge-largesize.mp4", contents: Data(bytes))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await SyncSampleParser.parseSyncSamples(from: url)
        #expect(result == nil)
    }

    @Test func syncSampleParser_tinyAtomSize_returnsNilWithoutCrashing() async throws {
        // Atom declaring size 3 (smaller than its own header) used to build an
        // invalid Range (lowerBound > upperBound) and crash.
        var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x03]
        bytes += Array("moov".utf8)
        bytes += [UInt8](repeating: 0x00, count: 16)
        let url = try temporaryFile(named: "tiny-atom.mp4", contents: Data(bytes))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await SyncSampleParser.parseSyncSamples(from: url)
        #expect(result == nil)
    }

    // MARK: - TS signature detection (FormatDetector)

    @Test func formatDetector_validTSSignature_detectsMPEGTS() async throws {
        var bytes = [UInt8](repeating: 0x00, count: 188 * 3)
        bytes[0] = 0x47
        bytes[188] = 0x47
        bytes[376] = 0x47
        let url = try temporaryFile(named: "valid.ts", contents: Data(bytes))
        defer { try? FileManager.default.removeItem(at: url) }

        let format = await detectContainerFormat(asset: AVURLAsset(url: url), url: url)
        guard case .mpegTS = format else {
            Issue.record("Expected .mpegTS, got \(format)")
            return
        }
    }

    @Test func formatDetector_syncByteOnlyInFirstPacket_rejectsTS() async throws {
        // Only the first packet has the 0x47 sync byte; packets 2 and 3 don't.
        // The old check read just 188 bytes, so it never noticed.
        var bytes = [UInt8](repeating: 0x00, count: 188 * 3)
        bytes[0] = 0x47
        let url = try temporaryFile(named: "fake.ts", contents: Data(bytes))
        defer { try? FileManager.default.removeItem(at: url) }

        let format = await detectContainerFormat(asset: AVURLAsset(url: url), url: url)
        if case .mpegTS = format {
            Issue.record("File without valid TS packet grid should not be detected as MPEG-TS")
        }
    }
}
