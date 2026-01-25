import SwiftUI
import FramePeekCore

// MARK: - Atom Registry

/// Registry of known MP4/MOV atoms with human-readable metadata
enum AtomRegistry {

    // MARK: - Lookup

    /// Get metadata for an atom by its FourCC code
    static func metadata(for fourCC: String) -> AtomMetadata {
        registry[fourCC] ?? AtomMetadata(
            fourCC: fourCC,
            name: fourCC,
            description: String(localized: "Unknown atom type"),
            category: .unknown
        )
    }

    // MARK: - Registry

    private static let registry: [String: AtomMetadata] = [
        // MARK: File Type
        "ftyp": AtomMetadata(
            fourCC: "ftyp",
            name: "File Type",
            description: String(localized: "Identifies the file format and compatible brands"),
            category: .fileType
        ),

        // MARK: Containers
        "moov": AtomMetadata(
            fourCC: "moov",
            name: "Movie",
            description: String(localized: "Container for all movie metadata"),
            category: .container
        ),
        "trak": AtomMetadata(
            fourCC: "trak",
            name: "Track",
            description: String(localized: "Container for a single track (video/audio/subtitle)"),
            category: .container
        ),
        "mdia": AtomMetadata(
            fourCC: "mdia",
            name: "Media",
            description: String(localized: "Container for track media information"),
            category: .container
        ),
        "minf": AtomMetadata(
            fourCC: "minf",
            name: "Media Info",
            description: String(localized: "Container for media handler information"),
            category: .container
        ),
        "stbl": AtomMetadata(
            fourCC: "stbl",
            name: "Sample Table",
            description: String(localized: "Container for sample timing and location data"),
            category: .container
        ),
        "dinf": AtomMetadata(
            fourCC: "dinf",
            name: "Data Info",
            description: String(localized: "Container for data reference information"),
            category: .container
        ),
        "edts": AtomMetadata(
            fourCC: "edts",
            name: "Edit List",
            description: String(localized: "Container for edit list entries"),
            category: .container
        ),

        // MARK: Timing/Headers
        "mvhd": AtomMetadata(
            fourCC: "mvhd",
            name: "Movie Header",
            description: String(localized: "Duration, timescale, creation date, preferred rate"),
            category: .timing
        ),
        "tkhd": AtomMetadata(
            fourCC: "tkhd",
            name: "Track Header",
            description: String(localized: "Track ID, dimensions, enabled state, layer, volume"),
            category: .timing
        ),
        "mdhd": AtomMetadata(
            fourCC: "mdhd",
            name: "Media Header",
            description: String(localized: "Track timescale, duration, and language code"),
            category: .timing
        ),
        "hdlr": AtomMetadata(
            fourCC: "hdlr",
            name: "Handler",
            description: String(localized: "Declares track type (video/audio/text/metadata)"),
            category: .timing
        ),
        "elst": AtomMetadata(
            fourCC: "elst",
            name: "Edit List",
            description: String(localized: "Time remapping entries for track playback"),
            category: .timing
        ),
        "vmhd": AtomMetadata(
            fourCC: "vmhd",
            name: "Video Media Header",
            description: String(localized: "Video-specific header with graphics mode"),
            category: .timing
        ),
        "smhd": AtomMetadata(
            fourCC: "smhd",
            name: "Sound Media Header",
            description: String(localized: "Audio-specific header with balance information"),
            category: .timing
        ),

        // MARK: Video Sample Tables
        "stsd": AtomMetadata(
            fourCC: "stsd",
            name: "Sample Description",
            description: String(localized: "Codec configuration, format details, decoder info"),
            category: .videoTrack
        ),
        "stts": AtomMetadata(
            fourCC: "stts",
            name: "Time-to-Sample",
            description: String(localized: "Maps sample numbers to durations for timing"),
            category: .videoTrack
        ),
        "stss": AtomMetadata(
            fourCC: "stss",
            name: "Sync Samples",
            description: String(localized: "Keyframe/I-frame indices for seeking"),
            category: .videoTrack
        ),
        "stsc": AtomMetadata(
            fourCC: "stsc",
            name: "Sample-to-Chunk",
            description: String(localized: "Maps samples to chunks in mdat"),
            category: .videoTrack
        ),
        "stsz": AtomMetadata(
            fourCC: "stsz",
            name: "Sample Sizes",
            description: String(localized: "Size in bytes of each sample"),
            category: .videoTrack
        ),
        "stz2": AtomMetadata(
            fourCC: "stz2",
            name: "Compact Sample Sizes",
            description: String(localized: "Compact representation of sample sizes"),
            category: .videoTrack
        ),
        "stco": AtomMetadata(
            fourCC: "stco",
            name: "Chunk Offsets",
            description: String(localized: "File offsets for each chunk (32-bit)"),
            category: .videoTrack
        ),
        "co64": AtomMetadata(
            fourCC: "co64",
            name: "Chunk Offsets 64",
            description: String(localized: "File offsets for each chunk (64-bit for large files)"),
            category: .videoTrack
        ),
        "ctts": AtomMetadata(
            fourCC: "ctts",
            name: "Composition Offsets",
            description: String(localized: "B-frame reordering offsets (PTS vs DTS delta)"),
            category: .videoTrack
        ),
        "sdtp": AtomMetadata(
            fourCC: "sdtp",
            name: "Sample Dependency",
            description: String(localized: "Sample dependency flags for trick play"),
            category: .videoTrack
        ),
        "sbgp": AtomMetadata(
            fourCC: "sbgp",
            name: "Sample-to-Group",
            description: String(localized: "Maps samples to sample groups"),
            category: .videoTrack
        ),
        "sgpd": AtomMetadata(
            fourCC: "sgpd",
            name: "Sample Group Description",
            description: String(localized: "Descriptions for sample groups"),
            category: .videoTrack
        ),
        "cslg": AtomMetadata(
            fourCC: "cslg",
            name: "Composition Shift",
            description: String(localized: "Composition time to decode time shift info"),
            category: .videoTrack
        ),

        // MARK: Codec Specific
        "avcC": AtomMetadata(
            fourCC: "avcC",
            name: "AVC Config",
            description: String(localized: "H.264/AVC decoder configuration record"),
            category: .videoTrack
        ),
        "hvcC": AtomMetadata(
            fourCC: "hvcC",
            name: "HEVC Config",
            description: String(localized: "H.265/HEVC decoder configuration record"),
            category: .videoTrack
        ),
        "av1C": AtomMetadata(
            fourCC: "av1C",
            name: "AV1 Config",
            description: String(localized: "AV1 codec configuration box"),
            category: .videoTrack
        ),
        "vpcC": AtomMetadata(
            fourCC: "vpcC",
            name: "VP9 Config",
            description: String(localized: "VP9 codec configuration box"),
            category: .videoTrack
        ),
        "dvcC": AtomMetadata(
            fourCC: "dvcC",
            name: "Dolby Vision Config",
            description: String(localized: "Dolby Vision configuration box"),
            category: .videoTrack
        ),
        "dvvC": AtomMetadata(
            fourCC: "dvvC",
            name: "Dolby Vision Config",
            description: String(localized: "Dolby Vision cross-compatible configuration"),
            category: .videoTrack
        ),
        "colr": AtomMetadata(
            fourCC: "colr",
            name: "Color Info",
            description: String(localized: "Color primaries, transfer function, matrix coefficients"),
            category: .videoTrack
        ),
        "pasp": AtomMetadata(
            fourCC: "pasp",
            name: "Pixel Aspect Ratio",
            description: String(localized: "Horizontal and vertical spacing for non-square pixels"),
            category: .videoTrack
        ),
        "clap": AtomMetadata(
            fourCC: "clap",
            name: "Clean Aperture",
            description: String(localized: "Clean aperture dimensions for cropping"),
            category: .videoTrack
        ),

        // MARK: Audio
        "esds": AtomMetadata(
            fourCC: "esds",
            name: "ES Descriptor",
            description: String(localized: "Elementary stream descriptor for AAC/MP3"),
            category: .audioTrack
        ),
        "dac3": AtomMetadata(
            fourCC: "dac3",
            name: "AC-3 Specific",
            description: String(localized: "Dolby Digital (AC-3) configuration"),
            category: .audioTrack
        ),
        "dec3": AtomMetadata(
            fourCC: "dec3",
            name: "E-AC-3 Specific",
            description: String(localized: "Dolby Digital Plus (E-AC-3) configuration"),
            category: .audioTrack
        ),
        "dOps": AtomMetadata(
            fourCC: "dOps",
            name: "Opus Specific",
            description: String(localized: "Opus audio codec configuration"),
            category: .audioTrack
        ),
        "dfLa": AtomMetadata(
            fourCC: "dfLa",
            name: "FLAC Specific",
            description: String(localized: "FLAC audio codec configuration"),
            category: .audioTrack
        ),
        "chan": AtomMetadata(
            fourCC: "chan",
            name: "Channel Layout",
            description: String(localized: "Audio channel layout description"),
            category: .audioTrack
        ),

        // MARK: Metadata
        "udta": AtomMetadata(
            fourCC: "udta",
            name: "User Data",
            description: String(localized: "Custom metadata container (comments, tags)"),
            category: .metadata
        ),
        "meta": AtomMetadata(
            fourCC: "meta",
            name: "Metadata",
            description: String(localized: "iTunes/ID3 style metadata container"),
            category: .metadata
        ),
        "ilst": AtomMetadata(
            fourCC: "ilst",
            name: "Item List",
            description: String(localized: "iTunes metadata items (title, artist, album)"),
            category: .metadata
        ),
        "keys": AtomMetadata(
            fourCC: "keys",
            name: "Metadata Keys",
            description: String(localized: "Metadata key definitions for mdta handler"),
            category: .metadata
        ),
        "free": AtomMetadata(
            fourCC: "free",
            name: "Free Space",
            description: String(localized: "Padding/free space for in-place editing"),
            category: .metadata
        ),
        "skip": AtomMetadata(
            fourCC: "skip",
            name: "Skip",
            description: String(localized: "Padding space to be skipped"),
            category: .metadata
        ),
        "wide": AtomMetadata(
            fourCC: "wide",
            name: "Wide",
            description: String(localized: "Placeholder for 64-bit atom expansion"),
            category: .metadata
        ),
        "uuid": AtomMetadata(
            fourCC: "uuid",
            name: "UUID Box",
            description: String(localized: "Extended type box with UUID identifier"),
            category: .metadata
        ),

        // MARK: Data
        "mdat": AtomMetadata(
            fourCC: "mdat",
            name: "Media Data",
            description: String(localized: "Actual compressed video/audio sample data"),
            category: .data
        ),
        "dref": AtomMetadata(
            fourCC: "dref",
            name: "Data Reference",
            description: String(localized: "References to media data locations"),
            category: .data
        ),

        // MARK: Fragmented MP4
        "moof": AtomMetadata(
            fourCC: "moof",
            name: "Movie Fragment",
            description: String(localized: "Movie fragment header for fragmented MP4"),
            category: .container
        ),
        "mfhd": AtomMetadata(
            fourCC: "mfhd",
            name: "Fragment Header",
            description: String(localized: "Movie fragment sequence number"),
            category: .timing
        ),
        "traf": AtomMetadata(
            fourCC: "traf",
            name: "Track Fragment",
            description: String(localized: "Track fragment container for fMP4"),
            category: .container
        ),
        "tfhd": AtomMetadata(
            fourCC: "tfhd",
            name: "Track Fragment Header",
            description: String(localized: "Track fragment defaults and flags"),
            category: .timing
        ),
        "tfdt": AtomMetadata(
            fourCC: "tfdt",
            name: "Track Fragment Decode Time",
            description: String(localized: "Base media decode time for fragment"),
            category: .timing
        ),
        "trun": AtomMetadata(
            fourCC: "trun",
            name: "Track Run",
            description: String(localized: "Per-sample durations, sizes, flags in fragment"),
            category: .videoTrack
        ),
        "sidx": AtomMetadata(
            fourCC: "sidx",
            name: "Segment Index",
            description: String(localized: "Segment index for DASH/HLS seeking"),
            category: .timing
        ),
        "mfra": AtomMetadata(
            fourCC: "mfra",
            name: "Movie Fragment Random Access",
            description: String(localized: "Random access point index for fragments"),
            category: .container
        ),
        "tfra": AtomMetadata(
            fourCC: "tfra",
            name: "Track Fragment Random Access",
            description: String(localized: "Track-specific random access points"),
            category: .timing
        ),
        "mfro": AtomMetadata(
            fourCC: "mfro",
            name: "Fragment Offset",
            description: String(localized: "Offset to mfra box from end of file"),
            category: .timing
        ),

        // MARK: Protection/DRM
        "sinf": AtomMetadata(
            fourCC: "sinf",
            name: "Protection Scheme",
            description: String(localized: "Protection scheme information box"),
            category: .metadata
        ),
        "schm": AtomMetadata(
            fourCC: "schm",
            name: "Scheme Type",
            description: String(localized: "Protection/encryption scheme type"),
            category: .metadata
        ),
        "schi": AtomMetadata(
            fourCC: "schi",
            name: "Scheme Info",
            description: String(localized: "Scheme-specific information"),
            category: .metadata
        ),
        "tenc": AtomMetadata(
            fourCC: "tenc",
            name: "Track Encryption",
            description: String(localized: "Default encryption parameters for track"),
            category: .metadata
        ),
        "pssh": AtomMetadata(
            fourCC: "pssh",
            name: "Protection System",
            description: String(localized: "Protection system specific header (Widevine, PlayReady)"),
            category: .metadata
        ),
        "senc": AtomMetadata(
            fourCC: "senc",
            name: "Sample Encryption",
            description: String(localized: "Per-sample encryption data (IVs, subsample info)"),
            category: .metadata
        ),
        "saiz": AtomMetadata(
            fourCC: "saiz",
            name: "Sample Aux Info Sizes",
            description: String(localized: "Sizes of auxiliary sample information"),
            category: .metadata
        ),
        "saio": AtomMetadata(
            fourCC: "saio",
            name: "Sample Aux Info Offsets",
            description: String(localized: "Offsets to auxiliary sample information"),
            category: .metadata
        )
    ]
}

// MARK: - Category UI Extensions

extension AtomCategory {

    /// Color for this category
    var color: Color {
        switch self {
        case .container:
            return .gray
        case .videoTrack:
            return .blue
        case .audioTrack:
            return .green
        case .metadata:
            return .purple
        case .timing:
            return .orange
        case .data:
            return Color.secondary
        case .fileType:
            return .cyan
        case .unknown:
            return Color.secondary
        }
    }

    /// SF Symbol icon for this category
    var icon: String {
        switch self {
        case .container:
            return "folder"
        case .videoTrack:
            return "film"
        case .audioTrack:
            return "waveform"
        case .metadata:
            return "tag"
        case .timing:
            return "clock"
        case .data:
            return "doc"
        case .fileType:
            return "doc.badge.gearshape"
        case .unknown:
            return "questionmark.square"
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .container:
            return String(localized: "Container")
        case .videoTrack:
            return String(localized: "Video")
        case .audioTrack:
            return String(localized: "Audio")
        case .metadata:
            return String(localized: "Metadata")
        case .timing:
            return String(localized: "Timing")
        case .data:
            return String(localized: "Data")
        case .fileType:
            return String(localized: "File Type")
        case .unknown:
            return String(localized: "Unknown")
        }
    }
}
