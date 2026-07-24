import Foundation

/// Bit-level reader for NAL unit bitstream parsing (Exp-Golomb aware).
/// Shared by VUIParser and FrameTypeParser.
struct BitReader {
    let bytes: [UInt8]
    var byteOffset: Int
    var bitOffset: Int = 0

    init(_ bytes: [UInt8], byteOffset: Int = 0) {
        self.bytes = bytes
        self.byteOffset = byteOffset
    }

    mutating func readBit() -> UInt8? {
        guard byteOffset < bytes.count else { return nil }
        let bit = (bytes[byteOffset] >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset == 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return bit
    }

    mutating func readBits(_ n: Int) -> UInt32? {
        guard n > 0 && n <= 32 else { return nil }
        var value: UInt32 = 0
        for _ in 0..<n {
            guard let bit = readBit() else { return nil }
            value = (value << 1) | UInt32(bit)
        }
        return value
    }

    /// Reads an unsigned Exp-Golomb coded value (ue(v)).
    /// Rejects >31 leading zeros: (1 << 32) would collapse to 0 via smart
    /// shift and trap on the subtraction.
    mutating func readUE() -> UInt32? {
        var leadingZeros = 0
        while true {
            guard let bit = readBit() else { return nil }
            if bit != 0 { break }
            leadingZeros += 1
            if leadingZeros > 31 { return nil }
        }

        if leadingZeros == 0 { return 0 }
        guard let bits = readBits(leadingZeros) else { return nil }
        return (1 << leadingZeros) - 1 + bits
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
}
