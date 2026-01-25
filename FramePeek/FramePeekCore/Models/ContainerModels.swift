import Foundation

// MARK: - Container Atom

/// Represents a single atom/box in an MP4/MOV container
public struct ContainerAtom: Identifiable, Sendable, Codable {
    public let id: UUID
    public let fourCC: String
    public let size: UInt64
    public let offset: UInt64
    public let headerSize: Int
    public let children: [ContainerAtom]

    public var isContainer: Bool { !children.isEmpty }
    public var contentSize: UInt64 { size > UInt64(headerSize) ? size - UInt64(headerSize) : 0 }

    public init(
        id: UUID = UUID(),
        fourCC: String,
        size: UInt64,
        offset: UInt64,
        headerSize: Int = 8,
        children: [ContainerAtom] = []
    ) {
        self.id = id
        self.fourCC = fourCC
        self.size = size
        self.offset = offset
        self.headerSize = headerSize
        self.children = children
    }
}

// MARK: - Container Analysis Result

/// Complete result of container structure analysis
public struct ContainerAnalysisResult: Sendable, Codable {
    public let atoms: [ContainerAtom]
    public let fileSize: UInt64
    public let format: ContainerFileFormat
    public let isFragmented: Bool

    public init(
        atoms: [ContainerAtom],
        fileSize: UInt64,
        format: ContainerFileFormat,
        isFragmented: Bool = false
    ) {
        self.atoms = atoms
        self.fileSize = fileSize
        self.format = format
        self.isFragmented = isFragmented
    }

    /// Recursively count all atoms in the structure
    public var totalAtomCount: Int {
        func count(_ atoms: [ContainerAtom]) -> Int {
            atoms.reduce(0) { $0 + 1 + count($1.children) }
        }
        return count(atoms)
    }
}

// MARK: - Container File Format

/// Detected container file format for atom inspection
public enum ContainerFileFormat: String, Sendable, Codable, CaseIterable {
    case mp4 = "MP4"
    case mov = "QuickTime"
    case m4v = "M4V"
    case m4a = "M4A"
    case fragmentedMP4 = "Fragmented MP4"
    case cmaf = "CMAF"
    case other = "Other"

    public var supportsAtomInspection: Bool {
        switch self {
        case .mp4, .mov, .m4v, .m4a, .fragmentedMP4, .cmaf:
            return true
        case .other:
            return false
        }
    }
}

// MARK: - Atom Category

/// Category of atom for color-coding and grouping
public enum AtomCategory: String, Sendable, Codable, CaseIterable {
    case container
    case videoTrack
    case audioTrack
    case metadata
    case timing
    case data
    case fileType
    case unknown
}

// MARK: - Atom Metadata

/// Human-readable metadata about an atom type
public struct AtomMetadata: Sendable {
    public let fourCC: String
    public let name: String
    public let description: String
    public let category: AtomCategory

    public init(fourCC: String, name: String, description: String, category: AtomCategory) {
        self.fourCC = fourCC
        self.name = name
        self.description = description
        self.category = category
    }
}
