import Foundation
import AVFoundation
import CoreMedia

/// Detects frame type (I/P/B) from sample buffer data by parsing NAL units.
/// Supports H.264 (AVC) and HEVC (H.265).
/// Handles both AVCC/HVCC (length-prefixed) and Annex-B (start-code prefixed) formats.
func detectFrameType(sampleBuffer: CMSampleBuffer, codecType: FourCharCode) -> FrameType {
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return .unknown }

    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let status = CMBlockBufferGetDataPointer(
        dataBuffer,
        atOffset: 0,
        lengthAtOffsetOut: nil,
        totalLengthOut: &totalLength,
        dataPointerOut: &dataPointer
    )
    guard status == noErr, let pointer = dataPointer, totalLength > 0, totalLength <= Int.max else { return .unknown }

    let data = Data(bytes: pointer, count: totalLength)

    let codecID = fourCCToString(codecType).lowercased()
    let nalLengthSize = sampleBufferNALLengthSize(sampleBuffer: sampleBuffer, codecID: codecID)

    if codecID.hasPrefix("avc") || codecID == "h264" {
        return detectH264FrameType(from: data, nalLengthSize: nalLengthSize)
    } else if codecID.hasPrefix("hev") || codecID.hasPrefix("hvc") || codecID == "hevc" {
        return detectHEVCFrameType(from: data, nalLengthSize: nalLengthSize)
    }
    return .unknown
}

// MARK: - NAL framing (AnnexB + AVCC/HVCC)

private enum NALFormat {
    case annexB
    case lengthPrefixed(nalLengthSize: Int)
}

/// Determine whether buffer is Annex-B (start codes) or length-prefixed.
/// If it doesn't look like Annex-B, treat it as length-prefixed using nalLengthSize.
private func detectNALFormat(_ data: Data, nalLengthSize: Int) -> NALFormat {
    if data.count >= 3,
       data[0] == 0x00, data[1] == 0x00,
       data[2] == 0x01 || (data.count >= 4 && data[2] == 0x00 && data[3] == 0x01) {
        return .annexB
    }
    return .lengthPrefixed(nalLengthSize: max(1, min(4, nalLengthSize)))
}

/// Convert length-prefixed (AVCC/HVCC) to Annex-B for easier parsing.
/// Supports nalLengthSize 1...4.
private func convertLengthPrefixedToAnnexB(data: Data, nalLengthSize: Int) -> Data? {
    guard (1...4).contains(nalLengthSize) else { return nil }
    var out = Data()
    var offset = 0

    while offset + nalLengthSize <= data.count {
        // Read NAL length (big-endian)
        var length: UInt32 = 0
        for i in 0..<nalLengthSize {
            guard offset + i < data.count else { break }
            length = (length << 8) | UInt32(data[offset + i])
        }
        offset += nalLengthSize

        let nalLen = Int(length)
        guard nalLen > 0, nalLen <= data.count, offset + nalLen <= data.count else { break }

        out.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        out.append(data[offset ..< offset + nalLen])

        offset += nalLen
    }

    return out.isEmpty ? nil : out
}

/// Split Annex-B byte stream into NAL units (each includes NAL header bytes, excludes start code).
private func extractAnnexBNALUnits(_ annexB: Data) -> [Data] {
    var nalUnits: [Data] = []

    func findStartCode(from idx: Int) -> (start: Int, length: Int)? {
        guard idx < annexB.count else { return nil }
        var i = idx
        while i + 3 < annexB.count {
            guard i + 1 < annexB.count, i + 2 < annexB.count else { break }
            if annexB[i] == 0x00 && annexB[i+1] == 0x00 {
                if annexB[i+2] == 0x01 { return (i, 3) }
                if i + 4 < annexB.count, annexB[i+2] == 0x00 && annexB[i+3] == 0x01 { return (i, 4) }
            }
            i += 1
        }
        return nil
    }

    var cursor = 0
    while let sc = findStartCode(from: cursor) {
        let nalStart = sc.start + sc.length
        cursor = nalStart

        // find next start code for boundary
        let next = findStartCode(from: cursor)
        let nalEnd = next?.start ?? annexB.count

        if nalStart < nalEnd {
            nalUnits.append(annexB[nalStart..<nalEnd])
        }

        cursor = nalEnd
    }

    return nalUnits
}

/// Gets NAL units from either Annex-B or length-prefixed input.
private func extractNALUnits(from data: Data, nalLengthSize: Int) -> [Data] {
    let format = detectNALFormat(data, nalLengthSize: nalLengthSize)
    let annexBData: Data

    switch format {
    case .annexB:
        annexBData = data
    case .lengthPrefixed(let size):
        guard let converted = convertLengthPrefixedToAnnexB(data: data, nalLengthSize: size) else { return [] }
        annexBData = converted
    }

    return extractAnnexBNALUnits(annexBData)
}

// MARK: - EBSP -> RBSP (remove emulation prevention bytes)

private func ebspToRbsp(_ ebsp: Data) -> Data {
    // Remove 0x03 following 0x00 0x00
    var rbsp = Data()
    rbsp.reserveCapacity(ebsp.count)

    var zerosCount = 0
    for i in ebsp.indices {
        // Safe access using indices
        let b = ebsp[i]
        if zerosCount >= 2 && b == 0x03 {
            // skip this emulation prevention byte
            zerosCount = 0
            continue
        }

        rbsp.append(b)

        if b == 0x00 {
            zerosCount += 1
        } else {
            zerosCount = 0
        }
    }

    return rbsp
}

// MARK: - BitReader + Exp-Golomb

private struct BitReader {
    let data: Data
    var byteOffset: Int = 0
    var bitOffset: Int = 0  // 0..7

    init(_ data: Data, byteOffset: Int = 0, bitOffset: Int = 0) {
        self.data = data
        self.byteOffset = byteOffset
        self.bitOffset = bitOffset
    }

    var isAtEnd: Bool { byteOffset >= data.count }

    mutating func readBit() -> UInt8? {
        guard byteOffset < data.count else { return nil }
        let byte = data[byteOffset]
        let bit = (byte >> (7 - bitOffset)) & 0x01

        bitOffset += 1
        if bitOffset == 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return bit
    }

    mutating func readBits(_ n: Int) -> UInt64? {
        guard n > 0, n <= 64 else { return nil } // Prevent excessive reads
        var v: UInt64 = 0
        for _ in 0..<n {
            guard let b = readBit() else { return nil }
            v = (v << 1) | UInt64(b)
        }
        return v
    }

    mutating func readUE() -> Int? {
        // Exp-Golomb ue(v)
        var leadingZeros = 0
        while true {
            guard let bit = readBit() else { return nil }
            if bit == 0 {
                leadingZeros += 1
                if leadingZeros > 31 { return nil } // sanity
            } else {
                break
            }
        }
        if leadingZeros == 0 { return 0 }
        guard let info = readBits(leadingZeros) else { return nil }
        // Prevent integer overflow - limit to safe range
        guard leadingZeros < 31 else { return nil } // 1 << 31 is safe on 64-bit, but be conservative
        let shiftResult = 1 << leadingZeros
        guard shiftResult > 0 else { return nil } // Check for overflow
        let base = shiftResult - 1
        guard base >= 0, Int(info) <= Int.max - base else { return nil }
        let codeNum = base + Int(info)
        return codeNum
    }
}

// MARK: - H.264 detection

private func detectH264FrameType(from data: Data, nalLengthSize: Int) -> FrameType {
    let nalUnits = extractNALUnits(from: data, nalLengthSize: nalLengthSize)
    guard !nalUnits.isEmpty else { return .unknown }

    var hasIDR = false
    var sliceTypes: [Int] = [] // Collect all slice types found
    var hasNonIDR = false

    for nal in nalUnits {
        guard nal.count >= 1, let firstByte = nal.first else { continue }
        let nalType = firstByte & 0x1F

        if nalType == 5 {
            hasIDR = true
            continue
        } else if nalType == 1 {
            hasNonIDR = true

            // Slice header is after 1-byte NAL header; but must parse RBSP (remove emulation bytes)
            let rbsp = ebspToRbsp(nal) // includes header; OK
            guard rbsp.count >= 2 else { continue }

            // Start bit parsing after 1-byte NAL header
            var br = BitReader(rbsp, byteOffset: 1, bitOffset: 0)

            // first_mb_in_slice (ue)
            guard br.readUE() != nil else { continue }

            // slice_type (ue)
            if let st = br.readUE(), (0...9).contains(st) {
                sliceTypes.append(st)
            }
        }
    }

    if hasIDR { return .i }

    // Process all collected slice types
    // H.264 slice_type values: 0,5=P, 1,6=B, 2,7=I, 3,8=SP, 4,9=SI
    // SP/SI slices (3,4,8,9) are for switching/error recovery - treat as P-like
    // Prefer I slices, then P, then B
    if sliceTypes.contains(where: { $0 == 2 || $0 == 7 }) {
        return .i
    }
    // P slices: 0, 5 (and SP slices 3, 8 as P-like)
    if sliceTypes.contains(where: { $0 == 0 || $0 == 5 || $0 == 3 || $0 == 8 }) {
        return .p
    }
    // B slices: 1, 6 (and SI slices 4, 9 as B-like, though rare)
    if sliceTypes.contains(where: { $0 == 1 || $0 == 6 || $0 == 4 || $0 == 9 }) {
        return .b
    }

    // If we found non-IDR NAL units but couldn't determine type, return unknown
    return hasNonIDR ? .unknown : .unknown
}

// MARK: - HEVC detection

private func detectHEVCFrameType(from data: Data, nalLengthSize: Int) -> FrameType {
    let nalUnits = extractNALUnits(from: data, nalLengthSize: nalLengthSize)
    guard !nalUnits.isEmpty else { return .unknown }

    var hasIRAP = false
    var sliceTypes: [Int] = [] // Collect all slice types found
    var hasNonIRAP = false

    for nal in nalUnits {
        // HEVC NAL header is 2 bytes
        guard nal.count >= 2, let firstByte = nal.first else { continue }
        let nalType = (firstByte >> 1) & 0x3F

        // IRAP 16..21 => treat as I
        if (16...21).contains(nalType) {
            hasIRAP = true
            continue
        }

        // Non-IRAP VCL 0..9 (TRAIL/TSA/STSA/RADL/RASL)
        if (0...9).contains(nalType) {
            hasNonIRAP = true

            // Parse slice header in RBSP
            let rbsp = ebspToRbsp(nal)
            guard rbsp.count >= 3 else { continue }

            // Start after 2-byte NAL header (FIXED)
            var br = BitReader(rbsp, byteOffset: 2, bitOffset: 0)

            // first_slice_segment_in_pic_flag (1 bit)
            guard let firstSliceFlagRaw = br.readBit() else { continue }
            let firstSliceFlag = firstSliceFlagRaw != 0

            // slice_pic_parameter_set_id (ue)
            guard br.readUE() != nil else { continue }

            // if firstSliceFlag == 0: dependent_slice_segment_flag (1 bit)
            // if dependent == 0: slice_segment_address (ue)
            if !firstSliceFlag {
                guard let dependentRaw = br.readBit() else { continue }
                let dependent = dependentRaw != 0
                if !dependent {
                    guard br.readUE() != nil else { continue }
                }
            }

            // slice_type (ue): 0=B, 1=P, 2=I
            if let st = br.readUE(), (0...2).contains(st) {
                sliceTypes.append(st)
            }
        }
    }

    if hasIRAP { return .i }

    // Process all collected slice types
    // Prefer I slices, then P, then B
    if sliceTypes.contains(2) {
        return .i
    }
    if sliceTypes.contains(1) {
        return .p
    }
    if sliceTypes.contains(0) {
        return .b
    }

    return hasNonIRAP ? .unknown : .unknown
}

// MARK: - CMFormatDescription helpers (nal length size)

private func sampleBufferNALLengthSize(sampleBuffer: CMSampleBuffer, codecID: String) -> Int {
    guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        return 4 // safe fallback
    }

    // H.264 avcC
    if codecID.hasPrefix("avc") || codecID == "h264" {
        var paramCount: Int = 0
        var nalSize: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fmt,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &paramCount,
            nalUnitHeaderLengthOut: &nalSize
        )
        if status == noErr, (1...4).contains(Int(nalSize)) {
            return Int(nalSize)
        }
    }

    // HEVC hvcC
    if codecID.hasPrefix("hev") || codecID.hasPrefix("hvc") || codecID == "hevc" {
        if #available(iOS 11.0, macOS 10.13, *) {
            var paramCount: Int = 0
            var nalSize: Int32 = 0
            let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                fmt,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &paramCount,
                nalUnitHeaderLengthOut: &nalSize
            )
            if status == noErr, (1...4).contains(Int(nalSize)) {
                return Int(nalSize)
            }
        }
    }

    return 4
}
