import Foundation

// MARK: - Bit Reader

/// Simple bit-level reader for parsing NAL unit bitstreams
private struct BitReader {
    let data: Data
    var byteOffset: Int = 0
    var bitOffset: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    /// Checks if we can read more bits
    var hasMoreBits: Bool {
        byteOffset < data.count
    }
    
    /// Reads a single bit
    mutating func readBit() -> UInt8? {
        guard byteOffset < data.count else { return nil }
        let byte = data[byteOffset]
        let bit = (byte >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset >= 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return bit
    }
    
    /// Reads n bits as an unsigned integer
    mutating func readBits(_ n: Int) -> UInt32? {
        guard n > 0 && n <= 32 else { return nil }
        var value: UInt32 = 0
        for _ in 0..<n {
            guard let bit = readBit() else { return nil }
            value = (value << 1) | UInt32(bit)
        }
        return value
    }
    
    /// Reads an unsigned Exp-Golomb coded value (ue(v))
    mutating func readUE() -> UInt32? {
        var leadingZeros = 0
        while let bit = readBit(), bit == 0 {
            leadingZeros += 1
            if leadingZeros > 32 { return nil }
        }
        
        guard leadingZeros <= 32 else { return nil }
        
        guard let bits = readBits(leadingZeros) else { return nil }
        let result = (1 << leadingZeros) - 1 + bits
        guard result <= UInt32.max else { return nil }
        return result
    }
    
    /// Reads a signed Exp-Golomb coded value (se(v))
    mutating func readSE() -> Int32? {
        guard let ue = readUE() else { return nil }
        if ue % 2 == 0 {
            return -Int32(ue / 2)
        } else {
            return Int32((ue + 1) / 2)
        }
    }
    
    /// Skips n bits (returns false if we run out of data)
    @discardableResult
    mutating func skipBits(_ n: Int) -> Bool {
        for _ in 0..<n {
            guard readBit() != nil else { return false }
        }
        return true
    }
    
    /// Aligns to next byte boundary
    mutating func alignToByte() {
        if bitOffset > 0 {
            bitOffset = 0
            byteOffset += 1
        }
    }
}

// MARK: - AVC (H.264) VUI Parser

/// Extracts max bitrate from AVC (H.264) codec configuration
/// - Parameter avcCData: Raw avcC box data containing SPS
/// - Returns: Formatted max bitrate string (e.g., "50000 kb/s") or nil if not found
func parseAVCMaxBitrate(_ avcCData: Data) -> String? {
    guard avcCData.count >= 6 else { return nil }
    
    let bytes = [UInt8](avcCData)
    let numSPS = bytes[5] & 0x1F
    
    var offset = 6
    for _ in 0..<numSPS {
        guard offset + 2 <= avcCData.count else { return nil }
        let spsLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        offset += 2
        
        guard offset + spsLength <= avcCData.count else { return nil }
        
        let spsData = avcCData.subdata(in: offset..<(offset + spsLength))
        if let maxBitrate = parseAVCSPSForMaxBitrate(spsData) {
            let kbps = maxBitrate
            return String(format: "%.0f kb/s", Double(kbps))
        }
        
        offset += spsLength
    }
    
    return nil
}

/// Parses AVC SPS to extract max bitrate from VUI
private func parseAVCSPSForMaxBitrate(_ spsData: Data) -> UInt32? {
    guard spsData.count > 1 else { return nil }
    
    var reader = BitReader(data: spsData)
    
    reader.skipBits(8)
    
    guard let profileIdc = reader.readBits(8) else { return nil }
    
    reader.skipBits(8)
    
    reader.skipBits(8)
    
    guard reader.readUE() != nil else { return nil }
    
    if profileIdc == 100 || profileIdc == 110 || profileIdc == 122 || profileIdc == 244 ||
       profileIdc == 44 || profileIdc == 83 || profileIdc == 86 || profileIdc == 118 ||
       profileIdc == 128 || profileIdc == 138 || profileIdc == 139 || profileIdc == 134 || profileIdc == 135 {
        guard let chromaFormatIdc = reader.readUE() else { return nil }
        
        if chromaFormatIdc == 3 {
            reader.skipBits(1)
        }
        
        guard reader.readUE() != nil else { return nil }
        guard reader.readUE() != nil else { return nil }
        reader.skipBits(1)
        
        if let scalingMatrixPresent = reader.readBit(), scalingMatrixPresent == 1 {
            for i in 0..<8 {
                if let scalingListPresent = reader.readBit(), scalingListPresent == 1 {
                    let listSize = (i < 6) ? 16 : 64
                    var lastScale = 8
                    for _ in 0..<listSize {
                        if let deltaScale = reader.readSE() {
                            lastScale = (lastScale + Int(deltaScale) + 256) % 256
                            if lastScale == 0 { break }
                        } else {
                            break
                        }
                    }
                }
            }
        }
    }
    
    guard reader.readUE() != nil else { return nil }
    
    guard let picOrderCntType = reader.readUE() else { return nil }
    
    if picOrderCntType == 0 {
        guard reader.readUE() != nil else { return nil }
    } else if picOrderCntType == 1 {
        reader.skipBits(1)
        reader.readSE()
        reader.readSE()
        guard let numRefFrames = reader.readUE() else { return nil }
        for _ in 0..<numRefFrames {
            reader.readSE()
        }
    }
    
    guard reader.readUE() != nil else { return nil }
    
    reader.skipBits(1)
    
    guard reader.readUE() != nil else { return nil }
    
    guard reader.readUE() != nil else { return nil }
    
    guard let frameMbsOnly = reader.readBit() else { return nil }
    
    if frameMbsOnly == 0 {
        reader.skipBits(1)
    }
    
    reader.skipBits(1)
    
    if let frameCroppingFlag = reader.readBit(), frameCroppingFlag == 1 {
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
    }
    
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    return parseAVCSPSVUI(reader: &reader)
}

/// Parses VUI parameters from AVC SPS
private func parseAVCSPSVUI(reader: inout BitReader) -> UInt32? {
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    if let aspectRatioPresent = reader.readBit(), aspectRatioPresent == 1 {
        if let aspectRatioIdc = reader.readBits(8), aspectRatioIdc == 255 {
            reader.skipBits(32)
        }
    }
    
    if let overscanPresent = reader.readBit(), overscanPresent == 1 {
        reader.skipBits(1)
    }
    
    if let videoSignalPresent = reader.readBit(), videoSignalPresent == 1 {
        reader.skipBits(4)
        if let colorDescPresent = reader.readBit(), colorDescPresent == 1 {
            reader.skipBits(24)
        }
    }
    
    if let chromaLocPresent = reader.readBit(), chromaLocPresent == 1 {
        reader.readUE()
        reader.readUE()
    }
    
    if let timingPresent = reader.readBit(), timingPresent == 1 {
        reader.skipBits(32)
        reader.skipBits(32)
        if let fixedFrameRate = reader.readBit(), fixedFrameRate == 1 {
        }
    }
    
    var hrdMaxBitrate: UInt32? = nil
    if let nalHrdPresent = reader.readBit(), nalHrdPresent == 1 {
        if let maxBitrate = parseHRDParameters(reader: &reader) {
            hrdMaxBitrate = maxBitrate
        }
    }
    
    if let vclHrdPresent = reader.readBit(), vclHrdPresent == 1 {
        if let maxBitrate = parseHRDParameters(reader: &reader) {
            hrdMaxBitrate = maxBitrate
        }
    }
    
    if hrdMaxBitrate != nil {
        _ = reader.readBit()
    }
    
    _ = reader.readBit()
    
    if let bitstreamRestriction = reader.readBit(), bitstreamRestriction == 1 {
        _ = reader.readBit()
        _ = reader.readBit()
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
    }
    
    return hrdMaxBitrate
}

/// Parses HRD (Hypothetical Reference Decoder) parameters to extract max bitrate
private func parseHRDParameters(reader: inout BitReader) -> UInt32? {
    guard let cpbCnt = reader.readUE() else { return nil }
    
    reader.skipBits(8)
    
    var maxBitrateValue: UInt32 = 0
    
    for _ in 0...cpbCnt {
        if let bitRateValueMinus1 = reader.readUE() {
            let kbps = bitRateValueMinus1 + 1
            maxBitrateValue = max(maxBitrateValue, kbps)
        }
        reader.readUE()
        _ = reader.readBit()
    }
    
    reader.skipBits(5)
    reader.skipBits(5)
    reader.skipBits(5)
    reader.skipBits(5)
    
    return maxBitrateValue > 0 ? maxBitrateValue : nil
}

// MARK: - HEVC (H.265) VUI Parser

/// Extracts max bitrate from HEVC (H.265) codec configuration
/// - Parameter hvcCData: Raw hvcC box data containing VPS/SPS
/// - Returns: Formatted max bitrate string (e.g., "50000 kb/s") or nil if not found
func parseHEVCMaxBitrate(_ hvcCData: Data) -> String? {
    guard hvcCData.count >= 23 else { return nil }
    
    let bytes = [UInt8](hvcCData)
    
    var offset = 23
    
    guard offset < hvcCData.count else { return nil }
    let numArrays = bytes[offset]
    offset += 1
    
    for _ in 0..<numArrays {
        guard offset + 3 <= hvcCData.count else { break }
        let arrayCompleteness = (bytes[offset] & 0x80) != 0
        let nalUnitType = bytes[offset] & 0x3F
        offset += 1
        let numNalus = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        offset += 2
        
        if nalUnitType == 33 {
            for _ in 0..<numNalus {
                guard offset + 2 <= hvcCData.count else { break }
                let nalLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                offset += 2
                
                guard offset + nalLength <= hvcCData.count else { break }
                
                let nalData = hvcCData.subdata(in: offset..<(offset + nalLength))
                if let maxBitrate = parseHEVCSPSForMaxBitrate(nalData) {
                    let kbps = Double(maxBitrate) / 10.0
                    return String(format: "%.0f kb/s", kbps)
                }
                
                offset += nalLength
            }
        } else {
            for _ in 0..<numNalus {
                guard offset + 2 <= hvcCData.count else { break }
                let nalLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                offset += 2
                guard offset + nalLength <= hvcCData.count else { break }
                offset += nalLength
            }
        }
    }
    
    return nil
}

/// Parses HEVC SPS to extract max bitrate from VUI
private func parseHEVCSPSForMaxBitrate(_ spsData: Data) -> UInt32? {
    guard spsData.count > 2 else { return nil }
    
    var reader = BitReader(data: spsData)
    
    reader.skipBits(16)
    
    reader.skipBits(4)
    
    guard let maxSubLayers = reader.readBits(3) else { return nil }
    reader.skipBits(1)
    
    reader.skipBits(8)
    reader.skipBits(32)
    reader.skipBits(48)
    reader.skipBits(8)
    
    if maxSubLayers > 0 {
        for _ in 0..<(maxSubLayers - 1) {
            if let profilePresent = reader.readBit(), profilePresent == 1 {
                reader.skipBits(8 + 32 + 48)
            }
            if let levelPresent = reader.readBit(), levelPresent == 1 {
                reader.skipBits(8)
            }
        }
    }
    
    guard reader.readUE() != nil else { return nil }
    
    guard let chromaFormatIdc = reader.readUE() else { return nil }
    
    if chromaFormatIdc == 3 {
        reader.skipBits(1)
    }
    
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    
    if let conformanceWindow = reader.readBit(), conformanceWindow == 1 {
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
    }
    
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    
    guard reader.readUE() != nil else { return nil }
    
    let subLayerOrderingPresent = reader.readBit()
    
    let numSubLayers = maxSubLayers + 1
    for i in 0..<numSubLayers {
        if i > 0 && subLayerOrderingPresent == 0 {
            break
        }
        reader.readUE()
        reader.readUE()
        reader.readUE()
    }
    
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    guard reader.readUE() != nil else { return nil }
    
    if let scalingListEnabled = reader.readBit(), scalingListEnabled == 1 {
        if let scalingListDataPresent = reader.readBit(), scalingListDataPresent == 1 {
        }
    }
    
    reader.skipBits(1)
    reader.skipBits(1)
    if let pcmEnabled = reader.readBit(), pcmEnabled == 1 {
        reader.skipBits(4)
        reader.skipBits(4)
        reader.readUE()
        reader.readUE()
        reader.skipBits(1)
    }
    
    guard let numShortTermRefPicSets = reader.readUE() else { return nil }
    
    for _ in 0..<numShortTermRefPicSets {
        if let interRefPicSetPredictionFlag = reader.readBit(), interRefPicSetPredictionFlag == 1 {
            reader.readUE()
            reader.readUE()
            reader.readUE()
            if let numNegativePics = reader.readUE() {
                for _ in 0..<numNegativePics {
                    reader.readUE()
                    reader.skipBits(1)
                }
            }
            if let numPositivePics = reader.readUE() {
                for _ in 0..<numPositivePics {
                    reader.readUE()
                    reader.skipBits(1)
                }
            }
        } else {
            if let numNegativePics = reader.readUE() {
                for _ in 0..<numNegativePics {
                    reader.readUE()
                    reader.skipBits(1)
                }
            }
            if let numPositivePics = reader.readUE() {
                for _ in 0..<numPositivePics {
                    reader.readUE()
                    reader.skipBits(1)
                }
            }
        }
    }
    
    if let longTermRefPicsPresent = reader.readBit(), longTermRefPicsPresent == 1 {
        reader.readUE()
    }
    
    reader.skipBits(1)
    reader.skipBits(1)
    
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    return parseHEVCSPSVUI(reader: &reader)
}

/// Parses VUI parameters from HEVC SPS
private func parseHEVCSPSVUI(reader: inout BitReader) -> UInt32? {
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    if let aspectRatioPresent = reader.readBit(), aspectRatioPresent == 1 {
        if let aspectRatioIdc = reader.readBits(8), aspectRatioIdc == 255 {
            reader.skipBits(32)
        }
    }
    
    if let overscanPresent = reader.readBit(), overscanPresent == 1 {
        reader.skipBits(1)
    }
    
    if let videoSignalPresent = reader.readBit(), videoSignalPresent == 1 {
        reader.skipBits(4)
        if let colorDescPresent = reader.readBit(), colorDescPresent == 1 {
            reader.skipBits(24)
        }
    }
    
    if let chromaLocPresent = reader.readBit(), chromaLocPresent == 1 {
        reader.readUE()
    }
    
    _ = reader.readBit()
    
    _ = reader.readBit()
    
    _ = reader.readBit()
    
    if let defaultDisplayWindow = reader.readBit(), defaultDisplayWindow == 1 {
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
    }
    
    if let timingPresent = reader.readBit(), timingPresent == 1 {
        reader.skipBits(32)
        reader.skipBits(32)
        if let vuiPocProportionalToTiming = reader.readBit(), vuiPocProportionalToTiming == 1 {
            reader.readUE()
        }
        if let vuiHrdParametersPresent = reader.readBit(), vuiHrdParametersPresent == 1 {
            if let maxBitrate = parseHEVCHRDParameters(reader: &reader) {
                return maxBitrate
            }
        }
    }
    
    if let bitstreamRestriction = reader.readBit(), bitstreamRestriction == 1 {
        _ = reader.readBit()
        _ = reader.readBit()
        _ = reader.readBit()
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
        reader.readUE()
    }
    
    return nil
}

/// Parses HEVC HRD parameters to extract max bitrate
private func parseHEVCHRDParameters(reader: inout BitReader) -> UInt32? {
    var maxBitrate: UInt32? = nil
    
    if let nalHrdPresent = reader.readBit(), nalHrdPresent == 1 {
        if let bitrate = parseHEVCSubLayerHRD(reader: &reader) {
            maxBitrate = bitrate
        }
    }
    
    if let vclHrdPresent = reader.readBit(), vclHrdPresent == 1 {
        if let bitrate = parseHEVCSubLayerHRD(reader: &reader) {
            maxBitrate = bitrate
        }
    }
    
    if maxBitrate != nil {
        if let subPicHrdPresent = reader.readBit(), subPicHrdPresent == 1 {
            reader.skipBits(8)
        }
    }
    
    return maxBitrate
}

/// Parses HEVC sub-layer HRD parameters
private func parseHEVCSubLayerHRD(reader: inout BitReader) -> UInt32? {
    guard let cpbCnt = reader.readUE() else { return nil }
    
    reader.skipBits(8)
    
    var maxBitrateValue: UInt32 = 0
    
    for _ in 0...cpbCnt {
        if let bitrateValue = reader.readUE() {
            let bitrate = (bitrateValue + 1) * 100
            maxBitrateValue = max(maxBitrateValue, bitrate)
        }
        reader.readUE()
        _ = reader.readBit()
    }
    
    reader.skipBits(5)
    reader.skipBits(5)
    reader.skipBits(5)
    
    return maxBitrateValue > 0 ? maxBitrateValue : nil
}
