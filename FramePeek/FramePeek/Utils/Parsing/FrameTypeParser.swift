import Foundation
import AVFoundation
import CoreMedia

/// Detects frame type (I/P/B) from sample buffer data by parsing NAL units.
/// Supports H.264 (AVC) and HEVC (H.265).
/// Handles both AVCC/HVCC (length-prefixed) and Annex-B (start-code prefixed) formats.
/// Parses directly from the block buffer without copying the sample payload.
public func detectFrameType(sampleBuffer: CMSampleBuffer, codecType: FourCharCode) -> FrameType {
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return .unknown }

    let codecID = fourCCToString(codecType).lowercased()

    let isH264 = codecID.hasPrefix("avc") || codecID == "h264"
    let isHEVC = codecID.hasPrefix("hev") || codecID.hasPrefix("hvc") || codecID == "hevc"
    guard isH264 || isHEVC else { return .unknown }

    let nalLengthSize = sampleBufferNALLengthSize(sampleBuffer: sampleBuffer, codecID: codecID)

    let detected = withBlockBufferBytes(dataBuffer) { bytes in
        isH264
            ? detectH264FrameType(bytes: bytes, nalLengthSize: nalLengthSize)
            : detectHEVCFrameType(bytes: bytes, nalLengthSize: nalLengthSize)
    }
    return detected ?? .unknown
}

// MARK: - Block buffer access

/// Runs body over the block buffer's bytes without copying when the buffer
/// is contiguous (the AVAssetReader common case); copies once otherwise.
/// The previous implementation read totalLength bytes from the first
/// contiguous region's pointer, which over-reads non-contiguous buffers.
private func withBlockBufferBytes<R>(
    _ blockBuffer: CMBlockBuffer,
    _ body: (UnsafeBufferPointer<UInt8>) -> R
) -> R? {
    let totalLength = CMBlockBufferGetDataLength(blockBuffer)
    guard totalLength > 0 else { return nil }

    if CMBlockBufferIsRangeContiguous(blockBuffer, atOffset: 0, length: totalLength) {
        var lengthAtOffset = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: nil,
            dataPointerOut: &dataPointer
        )
        guard status == noErr, let pointer = dataPointer, lengthAtOffset >= totalLength else { return nil }
        return pointer.withMemoryRebound(to: UInt8.self, capacity: totalLength) {
            body(UnsafeBufferPointer(start: $0, count: totalLength))
        }
    }

    var copied = [UInt8](repeating: 0, count: totalLength)
    let status = copied.withUnsafeMutableBytes {
        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: $0.baseAddress!)
    }
    guard status == noErr else { return nil }
    return copied.withUnsafeBufferPointer { body($0) }
}

// MARK: - NAL framing (AnnexB + AVCC/HVCC)

private func forEachNALUnit(
    in bytes: UnsafeBufferPointer<UInt8>,
    nalLengthSize: Int,
    _ body: (UnsafeBufferPointer<UInt8>) -> Void
) {
    if isAnnexB(bytes) {
        forEachAnnexBNALUnit(in: bytes, body)
    } else {
        forEachLengthPrefixedNALUnit(in: bytes, nalLengthSize: max(1, min(4, nalLengthSize)), body)
    }
}

private func isAnnexB(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
    if bytes.count >= 3, bytes[0] == 0x00, bytes[1] == 0x00 {
        if bytes[2] == 0x01 { return true }
        if bytes.count >= 4, bytes[2] == 0x00, bytes[3] == 0x01 { return true }
    }
    return false
}

private func forEachLengthPrefixedNALUnit(
    in bytes: UnsafeBufferPointer<UInt8>,
    nalLengthSize: Int,
    _ body: (UnsafeBufferPointer<UInt8>) -> Void
) {
    var offset = 0
    while offset + nalLengthSize <= bytes.count {
        var length: UInt32 = 0
        for i in 0..<nalLengthSize {
            length = (length << 8) | UInt32(bytes[offset + i])
        }
        offset += nalLengthSize

        let nalLength = Int(length)
        guard nalLength > 0, nalLength <= bytes.count - offset else { break }

        body(UnsafeBufferPointer(rebasing: bytes[offset ..< offset + nalLength]))
        offset += nalLength
    }
}

private func forEachAnnexBNALUnit(
    in bytes: UnsafeBufferPointer<UInt8>,
    _ body: (UnsafeBufferPointer<UInt8>) -> Void
) {
    func nextStartCode(from index: Int) -> (start: Int, length: Int)? {
        var i = index
        while i + 2 < bytes.count {
            if bytes[i] == 0x00, bytes[i + 1] == 0x00 {
                if bytes[i + 2] == 0x01 { return (i, 3) }
                if i + 3 < bytes.count, bytes[i + 2] == 0x00, bytes[i + 3] == 0x01 { return (i, 4) }
            }
            i += 1
        }
        return nil
    }

    guard let first = nextStartCode(from: 0) else { return }
    var nalStart = first.start + first.length

    while nalStart < bytes.count {
        let next = nextStartCode(from: nalStart)
        let nalEnd = next?.start ?? bytes.count

        if nalStart < nalEnd {
            body(UnsafeBufferPointer(rebasing: bytes[nalStart ..< nalEnd]))
        }

        guard let next else { break }
        nalStart = next.start + next.length
    }
}

// MARK: - EBSP -> RBSP (remove emulation prevention bytes)

/// Only the slice header's first fields are ever read, so converting a short
/// prefix avoids copying multi-megabyte slice payloads.
private func rbspPrefix(_ nal: UnsafeBufferPointer<UInt8>, maxBytes: Int = 128) -> [UInt8] {
    var rbsp: [UInt8] = []
    rbsp.reserveCapacity(min(maxBytes, nal.count))

    var zerosCount = 0
    for byte in nal {
        if zerosCount >= 2 && byte == 0x03 {
            zerosCount = 0
            continue
        }
        rbsp.append(byte)
        if rbsp.count >= maxBytes { break }
        zerosCount = byte == 0x00 ? zerosCount + 1 : 0
    }

    return rbsp
}

// MARK: - H.264 detection

private func detectH264FrameType(bytes: UnsafeBufferPointer<UInt8>, nalLengthSize: Int) -> FrameType {
    var hasIDR = false
    var sliceTypes: [Int] = []

    forEachNALUnit(in: bytes, nalLengthSize: nalLengthSize) { nal in
        guard let firstByte = nal.first else { return }
        let nalType = firstByte & 0x1F

        if nalType == 5 {
            hasIDR = true
            return
        }
        guard nalType == 1 else { return }

        let rbsp = rbspPrefix(nal)
        guard rbsp.count >= 2 else { return }

        // Start bit parsing after 1-byte NAL header
        var reader = BitReader(rbsp, byteOffset: 1)

        // first_mb_in_slice (ue)
        guard reader.readUE() != nil else { return }

        // slice_type (ue)
        if let sliceType = reader.readUE(), sliceType <= 9 {
            sliceTypes.append(Int(sliceType))
        }
    }

    if hasIDR { return .i }

    // H.264 slice_type values: 0,5=P, 1,6=B, 2,7=I, 3,8=SP, 4,9=SI
    // SP/SI slices (3,4,8,9) are for switching/error recovery - treat as P-like
    // Prefer I slices, then P, then B
    if sliceTypes.contains(where: { $0 == 2 || $0 == 7 }) {
        return .i
    }
    if sliceTypes.contains(where: { $0 == 0 || $0 == 5 || $0 == 3 || $0 == 8 }) {
        return .p
    }
    if sliceTypes.contains(where: { $0 == 1 || $0 == 6 || $0 == 4 || $0 == 9 }) {
        return .b
    }

    return .unknown
}

// MARK: - HEVC detection

private func detectHEVCFrameType(bytes: UnsafeBufferPointer<UInt8>, nalLengthSize: Int) -> FrameType {
    var hasIRAP = false
    var sliceTypes: [Int] = []

    forEachNALUnit(in: bytes, nalLengthSize: nalLengthSize) { nal in
        // HEVC NAL header is 2 bytes
        guard nal.count >= 2, let firstByte = nal.first else { return }
        let nalType = (firstByte >> 1) & 0x3F

        // IRAP 16..21 => treat as I
        if (16...21).contains(nalType) {
            hasIRAP = true
            return
        }

        // Non-IRAP VCL 0..9 (TRAIL/TSA/STSA/RADL/RASL)
        guard (0...9).contains(nalType) else { return }

        let rbsp = rbspPrefix(nal)
        guard rbsp.count >= 3 else { return }

        // Start after 2-byte NAL header
        var reader = BitReader(rbsp, byteOffset: 2)

        // first_slice_segment_in_pic_flag (1 bit)
        guard let firstSliceFlag = reader.readBit() else { return }

        // slice_pic_parameter_set_id (ue)
        guard reader.readUE() != nil else { return }

        // if not first slice: dependent_slice_segment_flag (1 bit),
        // then slice_segment_address (ue) when not dependent
        if firstSliceFlag == 0 {
            guard let dependent = reader.readBit() else { return }
            if dependent == 0 {
                guard reader.readUE() != nil else { return }
            }
        }

        // slice_type (ue): 0=B, 1=P, 2=I
        if let sliceType = reader.readUE(), sliceType <= 2 {
            sliceTypes.append(Int(sliceType))
        }
    }

    if hasIRAP { return .i }

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

    return .unknown
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
