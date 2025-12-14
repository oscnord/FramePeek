# MediaInspector – Agent and Contributor Guide

This document is a concise guide for AI agents and human contributors to understand, navigate, and extend the MediaInspector codebase efficiently.

## Goal of the project

MediaInspector is a macOS SwiftUI application that inspects local media files and extracts rich, user-friendly metadata using AVFoundation and CoreMedia. It provides:

- Video metadata (container, codec, resolution, frame rate, HDR/color info, PAR/DAR, bitrate estimations)
- Audio track details (codec, channels, sample rate, bitrate, language)
- Frame-by-frame bitrate analysis with interactive charts
- Keyframe detection and thumbnail visualization

## High-level architecture

- Core frameworks
  - AVFoundation and CoreMedia for media inspection.
  - SwiftUI for the user interface.
  - Foundation for utilities and formatting.
  - AppKit for macOS-specific features (file dialogs, images).

- Primary flow
  - Input: A file URL is selected via NSOpenPanel → turned into an AVURLAsset.
  - Orchestration: `MediaInspectorViewModel` coordinates loading via `getExtendedInfo(url:asset:)`.
  - Frame Analysis: `extractFramesStream(asset:options:)` provides progressive bitrate sampling.
  - Keyframe Detection: `extractKeyframes(asset:)` identifies sync samples (I-frames).
  - Output: `ExtendedVideoInfo` model and `[BitrateSample]` for UI consumption.

## Project structure

```text
MediaInspector/
├── MediaInspectorApp.swift          # App entry point (@main)
├── MediaInspector.swift             # Main window/view
├── MediaInspectorViewModel.swift    # @MainActor ViewModel, coordinates all loading
├── AboutView.swift                  # About dialog view
├── fileUtils.swift                  # NSOpenPanel file dialog helper
├── BitrateSample.swift              # Identifiable sample for charts
├── BitrateChartView.swift           # SwiftUI chart for bitrate visualization
├── KeyframeTimelineView.swift       # Keyframe markers timeline
├── KeyframeThumbnailStrip.swift     # Keyframe thumbnail strip
├── InfoInspectorView/               # Inspector panel components
│   ├── InfoInspectorView.swift      # Main inspector view
│   ├── QuickSummaryCard.swift       # Summary card component
│   ├── CollapsibleSection.swift     # Collapsible metadata sections
│   ├── KeyValueComponents.swift     # Key-value display components
│   ├── ExtendedVideoInfo+Metadata.swift # Metadata display extensions
│   ├── AudioTrackInfo+Display.swift # Audio track display extensions
│   ├── CopiedBanner.swift           # Copy-to-clipboard feedback
│   ├── EmptyInspectorState.swift    # Empty state view
│   ├── SectionDivider.swift         # Section divider component
│   └── ViewHelpers.swift            # View helper utilities
└── Utils/                           # Core utilities
    ├── MediaModels.swift            # Data models (ExtendedVideoInfo, AudioTrackInfo, etc.)
    ├── VideoInfoLoader.swift        # Main metadata extraction orchestrator
    ├── AudioInfoLoader.swift        # Audio track loading
    ├── FormatUtils.swift            # FourCC, duration, codec name utilities
    ├── ColorUtils.swift             # HDR detection, color metadata helpers
    ├── AspectRatioUtils.swift       # Aspect ratio calculations
    ├── VideoUtils.swift             # File size and bitrate utilities
    ├── AV1Parser.swift              # AV1 codec configuration parsing
    ├── FrameAnalysis.swift          # Bitrate/FPS analysis utilities
    ├── ExtractFramesStream.swift    # AsyncStream-based frame extraction
    ├── FrameAggregation.swift       # Frame data aggregation utilities
    ├── FastBitrateExtractor.swift   # Optimized bitrate extraction
    ├── KeyframeMarker.swift         # Keyframe detection
    └── GenerateKeyframeThumbnails.swift # Thumbnail generation
```

## Key modules and responsibilities

### UI Layer

- **MediaInspectorApp.swift** – App entry point with `@main`.
- **MediaInspector.swift** – Main window layout and structure with drag-and-drop support.
- **MediaInspectorViewModel.swift** – `@MainActor` ViewModel that:
  - Manages file selection via `openFileDialog()` and `pickFile()`.
  - Coordinates async loading of metadata, frames, and keyframes.
  - Exposes published properties: `samples`, `extendedInfo`, `keyframes`, `keyframeThumbs`, etc.
  - Supports configurable sampling modes (auto, everyFrame, interval).
  - Handles analysis cancellation and progress tracking.
- **AboutView.swift** – About dialog with app information and features.
- **InfoInspectorView/** – Inspector panel components:
  - **InfoInspectorView.swift** – Main inspector view orchestrating all metadata display.
  - **QuickSummaryCard.swift** – Summary card with key metrics.
  - **CollapsibleSection.swift** – Reusable collapsible section component.
  - **KeyValueComponents.swift** – Key-value pair display components.
  - **ExtendedVideoInfo+Display.swift** – Display extensions for video metadata.
  - **AudioTrackInfo+Display.swift** – Display extensions for audio track info.
  - **CopiedBanner.swift** – Copy-to-clipboard feedback banner.
  - **EmptyInspectorState.swift** – Empty state when no file is loaded.
  - **SectionDivider.swift** – Visual section divider component.
  - **ViewHelpers.swift** – Helper utilities for views.
- **BitrateChartView.swift** – Interactive bitrate chart over time using Swift Charts.
- **KeyframeTimelineView.swift** – Timeline visualization of keyframe positions.
- **KeyframeThumbnailStrip.swift** – Horizontal strip of keyframe thumbnails.

### Core Utilities (Utils/)

- **VideoInfoLoader.swift**
  - Orchestrates metadata extraction from AVAsset via `getExtendedInfo(url:asset:)`.
  - Loads duration, video track, format descriptions, color/HDR info, PAR/DAR, bitrates.
  - Parses codec configuration atoms (hvcC, avcC, vpcC, av1C, dvcC/dvvC).
  - Returns `ExtendedVideoInfo`.

- **AudioInfoLoader.swift**
  - `loadAudioInfo(asset:)` → returns `[AudioTrackInfo]` with codec, channels, sample rate, bitrate, language.

- **VideoUtils.swift** – File size and bitrate utilities:
  - `getFileSizeString(for: URL)` → formatted size (e.g., "123.45 MiB")
  - `getFileSizeBytes(for: URL)` → raw bytes
  - `getOverallBitrateString(asset:fileURL:)` → overall bitrate in kb/s

- **FormatUtils.swift** – Formatting and codec mapping:
  - `fourCCToString(_:)` → FourCC code to string
  - `formatDuration(seconds:)` → human-readable duration
  - `channelLayoutDescription(channels:)` → "Stereo", "5.1", etc.
  - `audioCodecName(_:)` / `videoCodecName(_:)` → human-readable codec names

- **ColorUtils.swift** – HDR and color metadata:
  - `detectHDRFormat(transferFunction:colorPrimaries:hasDolbyVisionConfig:)`
  - `colorPrimariesDescription(_:)`, `transferFunctionDescription(_:)`, `matrixDescription(_:)`

- **AspectRatioUtils.swift** – Aspect ratio calculations:
  - `calculateDisplayAspectRatio(width:height:parH:parV:)`
  - `resolutionCategory(width:height:)` → "4K UHD", "Full HD", etc.
  - `gcd(_:_:)` – helper for ratio simplification

- **AV1Parser.swift** – AV1 codec configuration:
  - `parseAV1C(_:)` → `AV1ConfigSummary` (profile, level, bitDepth, chroma, fullRange)
  - `av1LevelDescription(_:)`, `av1ProfileDescription(_:)`

- **FrameAnalysis.swift** – Frame rate statistics and extraction:
  - `frameRateStats(from:)` → average FPS, min/max intervals
  - `startFrameExtractionProgressive(asset:...)` → progressive updates
  - `extractFrames(asset:maxSamples:completion:)` → batch extraction

- **ExtractFramesStream.swift** – AsyncStream-based frame extraction:
  - `extractFramesStream(asset:options:)` → yields `FrameAnalysisUpdate` progressively

- **FrameAggregation.swift** – Frame data aggregation utilities:
  - Aggregates frame samples and computes statistics.

- **FastBitrateExtractor.swift** – Optimized bitrate extraction:
  - High-performance bitrate extraction with configurable accuracy.

- **KeyframeMarker.swift** – Keyframe detection:
  - `extractKeyframes(asset:maxKeyframes:minSpacingSeconds:)` → `[KeyframeMarker]`
  - Uses `kCMSampleAttachmentKey_NotSync` to identify sync samples (I-frames).

- **GenerateKeyframeThumbnails.swift** – Thumbnail generation:
  - `GenerateKeyframeThumbnails(asset:keyframeTimes:maxThumbnails:thumbHeight:)` → `[KeyframeThumbnail]`

### Models (MediaModels.swift)

- **ExtendedVideoInfo** – All video metadata fields (see Data model section).
- **AudioTrackInfo** – Per-track audio info (index, codec, channels, sampleRate, bitrate, language).
- **FrameAnalysisResult** – Batch result with samples and FPS stats.
- **FrameSamplingOptions** – Configures sampling behavior (interval, maxSamples, emitEveryNSamples).
- **AV1ConfigSummary** – Parsed AV1 configuration.

### Other Files

- **BitrateSample.swift** – `Identifiable` struct with `time` and `bitrate` for chart data.
- **fileUtils.swift** – `openFileDialog(completion:)` using NSOpenPanel for file selection.
- **AboutView.swift** – About dialog displaying app version, features, and author information.

## Data model (ExtendedVideoInfo)

The following fields are populated by `getExtendedInfo`; all are properties on the `ExtendedVideoInfo` struct:

- **File and container**
  - `fileName`, `fileSize`, `fileSizeBytes`, `overallBitrate`
  - `duration` (raw), `durationFormatted`
  - `containerFormat`, `containerFormatProfile`
  - `codecIdRaw`

- **Video geometry and timing**
  - `resolution`, `displayAspectRatio`, `frameRate`
  - `orientationDegrees`, `pixelAspectRatio`, `cleanAperture`
  - `scanType`, `frameRateMode`

- **Codec and stream details**
  - `codec`, `codecProfile`, `codecIdInfo`
  - `trackBitrate`, `maxBitrate`
  - `bitsPerPixelFrame`, `videoStreamSize`

- **Color and HDR**
  - `colorSpace`, `chromaSubsampling`, `bitDepth`
  - `colorPrimaries`, `transferFunction`, `matrixCoefficients`, `colorRange`
  - `hdrFormat`

- **AV1 specifics**
  - `av1CSize`, `av1Profile`, `av1Level`, `av1ChromaSubsampling`, `av1FullRange`

- **Metadata**
  - `creationDate`, `metadataTitle`, `metadataArtist`, `metadataEncoder`, `metadataDescription`

- **Audio**
  - `audioTracks: [AudioTrackInfo]`

### AudioTrackInfo

```swift
struct AudioTrackInfo {
    let index: Int
    let codec: String
    let codecDisplayName: String
    let channels: Int
    let channelLayout: String
    let sampleRateHz: Double
    let bitrateKbps: Float?
    let languageCode: String?
}
```

## Control flow of getExtendedInfo(url:asset:)

1. **File-level info**
   - Derives file name from URL.
   - Gets file size via `getFileSizeString(for:)` and `getFileSizeBytes(for:)`.
   - Computes overall bitrate via `getOverallBitrateString(asset:fileURL:)`.

2. **Duration and basic metadata**
   - Uses `asset.load(.duration)` (async/await) for duration.
   - Formats via `formatDuration(seconds:)`.
   - Loads creation date via `asset.load(.creationDate)`.
   - Extracts common metadata (title, artist, encoder, description) from `asset.commonMetadata`.

3. **Video track discovery**
   - Loads the first video track via `asset.loadTracks(withMediaType: .video)`.
   - Reads `naturalSize`, `nominalFrameRate`, `preferredTransform` (for orientation).
   - Gets `estimatedDataRate` for track-level bitrate.

4. **Format description parsing**
   - Extracts codec FourCC via `CMFormatDescriptionGetMediaSubType`.
   - Maps codec ID to human-readable name via `videoCodecName(_:)`.
   - Reads format description extensions for:
     - Color primaries, transfer function, YCbCr matrix.
     - Full range vs limited (`kCVImageBufferYCbCrMatrix_XXX`).
     - Bits per component.
     - Depth (heuristic chroma subsampling).
     - Clean aperture and pixel aspect ratio (PAR).
     - Field count → scan type (interlaced/progressive).
   - Parses sample description atoms:
     - Dolby Vision (`dvcC`/`dvvC`)
     - HEVC (`hvcC`), AVC (`avcC`), VP9 (`vpcC`), AV1 (`av1C`)

5. **Derived metrics**
   - Computes display aspect ratio (DAR) via `calculateDisplayAspectRatio(...)`.
   - Determines HDR format via `detectHDRFormat(...)`.
   - Estimates bits-per-pixel-per-frame from bitrate, resolution, and fps.
   - Estimates video stream size share from total file size and bitrate ratio.

6. **Audio tracks**
   - Delegates to `loadAudioInfo(asset:)` for per-track audio details.

7. **Aggregation**
   - Returns `ExtendedVideoInfo` with all available, formatted fields.

## Frame Analysis Flow

The app supports three sampling modes (configured via `MediaInspectorViewModel`):

- **auto** – Automatic downsampling based on duration.
- **everyFrame** – Sample every frame (up to `maxSamples`).
- **interval** – Sample at fixed time intervals.

### Progressive extraction via AsyncStream

```swift
for await update in extractFramesStream(asset: asset, options: options) {
    // update.appendedSamples: new BitrateSample batch
    // update.averageFPS, minInterval, maxInterval: running stats
    // update.isFinished: true when complete
}
```

### Keyframe extraction

```swift
let keyframes = await extractKeyframes(asset: asset, maxKeyframes: 20_000)
// Returns [KeyframeMarker] with time positions of sync samples
```

## Concurrency and performance

- Uses Swift Concurrency (`async`/`await`) throughout.
- `MediaInspectorViewModel` is `@MainActor` to safely update `@Published` properties.
- Heavy work runs on `.userInitiated` priority via `Task.detached`.
- Frame extraction uses `AsyncStream` for progressive UI updates.
- `AVAssetReaderTrackOutput.alwaysCopiesSampleData = false` for performance.
- Keyframe extraction avoids decoding by inspecting sample attachment flags.
- Tasks are cancellable – the ViewModel cancels in-flight tasks when loading a new file.

## Error handling and defaults

- Many lookups use `try? await` with `guard`/fallbacks to avoid throwing.
- Unknown or missing fields are left `nil` or filled with `"N/A"` / `"Unknown"`.
- Calculations are guarded by sanity checks (e.g., `> 0` values for dimensions, fps, bitrate).
- Task cancellation is checked via `Task.isCancelled` in extraction loops.

## Platform notes

- Built for **macOS 15.2+** (Sequoia) using SwiftUI and AppKit (`NSOpenPanel`, `NSImage`).
- Uses `AVURLAsset`, `AVAssetReader`, `AVAssetImageGenerator` from AVFoundation.
- Uses Swift Charts framework (macOS 15.0+) for interactive bitrate visualization.
- Sandboxed apps must have read access to selected file URLs (see `MediaInspector.entitlements`).
- Supported file types: `.mp4`, `.mov`, `.avi`, `.mpeg`, and other movie types via `UTType`.
- Minimum deployment target: macOS 15.2 (configured in Xcode project settings).

## Extending the inspector

### New container/format detection

- Update file extension handling or probe container via AVAsset metadata.
- Container format is currently derived from file extension in `VideoInfoLoader`.

### New codec parsing

- Add parser for the codec's configuration atom (e.g., in `VideoInfoLoader.swift`).
- Add FourCC → friendly name mapping in `FormatUtils.swift` (`videoCodecMappings`).
- See `AV1Parser.swift` for a reference implementation of atom parsing.

### Better chroma/bit depth detection

- Prefer authoritative fields from codec configs over heuristics.
- AV1 already extracts bit depth from `av1C` atom; similar approach works for HEVC/AVC.

### HDR detection rules

- Expand `detectHDRFormat(...)` in `ColorUtils.swift` for additional transfer functions/primaries.
- Currently supports: Dolby Vision, HDR10, HLG, PQ, Wide Color Gamut (BT.2020).

### Audio metadata enhancements

- Enhance `loadAudioInfo(asset:)` in `AudioInfoLoader.swift` to parse audio codec config atoms.
- Add Dolby Atmos detection, format profiles, etc.

### Additional frame analysis

- Add scene change detection using frame difference metrics.
- Compute GOP structure from keyframe intervals.
- Track frame types (I/P/B) if decodable from sample attachments.

### Placeholder fields to populate

- `containerFormatProfile` – could parse moov/mdat structure or ftyp atom.
- `maxBitrate` – requires parsing codec-specific config (e.g., VUI in AVC/HEVC).
- `frameRateMode` – detect CFR vs VFR from frame interval variance in `FrameAnalysis`.

## Code style and contribution rules

- Prefer Swift and Apple frameworks; use Swift Concurrency over GCD/Combine unless the surrounding code dictates otherwise.
- Keep parsing helpers pure and testable; isolate I/O at the orchestration layer.
- Use `@MainActor` for ViewModels and ensure UI updates happen on the main thread.
- Follow existing naming conventions: `load*`, `get*`, `parse*`, `extract*`, `detect*`.
- When proposing changes to an existing file, always include the entire file content in a single code block, prefixed with the filename:

```swift:SomeFile.swift
// Entire file content goes here.
```

## Testing

- Unit tests are located in `MediaInspectorTests/`.
- UI tests are in `MediaInspectorUITests/`.
- Parsing helpers should be pure functions for easy unit testing.
- Use sample media files with known properties for integration testing.
