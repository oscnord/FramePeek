import Foundation
import FramePeekCore

// MARK: - Container Parser

/// Parses MP4/MOV container structure into an atom tree
public enum ContainerParser {

    // MARK: - Public API

    /// Parse the container structure of an MP4/MOV file
    /// - Parameter url: URL of the media file
    /// - Returns: ContainerAnalysisResult with the atom tree, or nil if parsing fails
    public static func parse(url: URL) async -> ContainerAnalysisResult? {
        let ext = url.pathExtension.lowercased()
        let baseFormat: ContainerFileFormat = switch ext {
        case "mov": .mov
        case "m4v": .m4v
        case "m4a": .m4a
        default: .mp4
        }

        // Check if format supports atom inspection
        guard ["mp4", "m4v", "mov", "m4a"].contains(ext) else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? fileHandle.close() }

            let fileSize = fileHandle.seekToEndOfFile()
            try? fileHandle.seek(toOffset: 0)

            // Parse all top-level atoms
            let atoms = parseAtoms(in: fileHandle, range: 0..<fileSize, depth: 0)

            // Check if fragmented
            let isFragmented = atoms.contains { $0.fourCC == "moof" }

            let format: ContainerFileFormat = if isFragmented {
                .fragmentedMP4
            } else {
                baseFormat
            }

            return ContainerAnalysisResult(
                atoms: atoms,
                fileSize: fileSize,
                format: format,
                isFragmented: isFragmented
            )
        }.value
    }

    // MARK: - Atom Parsing

    /// Known container atoms that have child atoms
    private static let containerAtoms: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl", "dinf", "edts", "udta",
        "meta", "ilst", "moof", "traf", "mfra", "sinf", "schi", "wave"
    ]

    /// Parse atoms within a range
    private static func parseAtoms(
        in fileHandle: FileHandle,
        range: Range<UInt64>,
        depth: Int
    ) -> [ContainerAtom] {
        var atoms: [ContainerAtom] = []
        var offset = range.lowerBound

        // Safety limit on recursion depth
        guard depth < 20 else { return atoms }

        while offset < range.upperBound {
            guard let atom = parseAtom(in: fileHandle, at: offset, maxOffset: range.upperBound, depth: depth) else {
                break
            }

            atoms.append(atom)
            offset += atom.size

            // Safety check for invalid atom sizes
            if atom.size == 0 { break }
        }

        return atoms
    }

    /// Parse a single atom at a given offset
    private static func parseAtom(
        in fileHandle: FileHandle,
        at offset: UInt64,
        maxOffset: UInt64,
        depth: Int
    ) -> ContainerAtom? {
        do {
            try fileHandle.seek(toOffset: offset)

            // Read atom header (8 bytes: 4 for size, 4 for type)
            guard let headerData = try fileHandle.read(upToCount: 8),
                  headerData.count == 8 else { return nil }

            let size32 = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let typeData = headerData.subdata(in: 4..<8)

            guard let fourCC = String(data: typeData, encoding: .ascii),
                  fourCC.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_") }) else {
                return nil
            }

            // Handle extended size (size == 1 means 64-bit size follows)
            var atomSize: UInt64
            var headerSize: Int = 8

            if size32 == 1 {
                // Extended size: read 8 more bytes
                guard let extSizeData = try fileHandle.read(upToCount: 8),
                      extSizeData.count == 8 else { return nil }
                atomSize = extSizeData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                headerSize = 16
            } else if size32 == 0 {
                // Size 0 means atom extends to end of file/range
                atomSize = maxOffset - offset
            } else {
                atomSize = UInt64(size32)
            }

            // Validate atom size
            guard atomSize >= UInt64(headerSize),
                  offset + atomSize <= maxOffset else {
                return nil
            }

            // Parse children if this is a container atom
            var children: [ContainerAtom] = []

            if containerAtoms.contains(fourCC) {
                // Special case: meta atom may have a 4-byte version/flags before children
                var childrenStart = offset + UInt64(headerSize)

                if fourCC == "meta" {
                    // Skip version (1 byte) and flags (3 bytes)
                    childrenStart += 4
                }

                let childrenEnd = offset + atomSize
                if childrenStart < childrenEnd {
                    children = parseAtoms(
                        in: fileHandle,
                        range: childrenStart..<childrenEnd,
                        depth: depth + 1
                    )
                }
            }

            return ContainerAtom(
                fourCC: fourCC,
                size: atomSize,
                offset: offset,
                headerSize: headerSize,
                children: children
            )
        } catch {
            return nil
        }
    }
}
