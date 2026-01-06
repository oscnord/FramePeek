# FramePeek – Agent and Contributor Guide

This document is a concise guide for AI agents and human contributors to understand, navigate, and extend the FramePeek codebase efficiently.

## Goal of the project

FramePeek is a macOS SwiftUI application that inspects local media files and extracts rich, user-friendly metadata using AVFoundation and CoreMedia. It provides:

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
  - Frame Analysis: `extractBitratesFast(asset:options:)` provides progressive bitrate sampling.
  - Keyframe Detection: `extractKeyframes(asset:)` identifies sync samples (I-frames).
  - Output: `ExtendedVideoInfo` model and `[BitrateSample]` for UI consumption.

## Project structure

```text
FramePeek/
├── FramePeekApp.swift          # App entry point (@main)
├── FramePeek.swift             # Main window/view with drag-and-drop
├── fileUtils.swift                  # NSOpenPanel file dialog helper
├── FramePeek.entitlements      # App entitlements (sandbox, file access)
├── Localizable.xcstrings        # Localization strings (i18n)
│
├── Models/                          # Data models
│   ├── BitrateSample.swift          # Identifiable sample for charts
│   └── MediaModels.swift            # ExtendedVideoInfo, AudioTrackInfo, etc.
│
├── ViewModels/                      # ViewModels and extensions
│   ├── MediaInspectorViewModel.swift           # @MainActor ViewModel, coordinates all loading
│   ├── MediaInspectorViewModel+FileHandling.swift # File loading and tab choice handling
│   ├── MediaInspectorViewModel+Sampling.swift  # Frame sampling logic
│   ├── MediaInspectorViewModel+Thumbnails.swift # Thumbnail generation logic
│   ├── PlayerViewModelManager.swift  # Video player view model manager
│   └── TabManager.swift             # Multi-tab management
│
├── Views/                           # UI components organized by feature
│   ├── Chart/                       # Bitrate chart components
│   │   ├── BitrateChartView.swift           # Main chart view
│   │   ├── BitrateChartComponents.swift     # Chart sub-components
│   │   ├── BitrateChartDownsampling.swift   # LTTB downsampling algorithm
│   │   └── BitrateChartStatistics.swift     # Chart statistics display
│   │
│   ├── Common/                      # Shared UI components
│   │   ├── AboutView.swift                 # About dialog
│   │   ├── LiquidGlassToolbarButton.swift # Toolbar button styling
│   │   ├── NoTopInsetScrollView.swift      # Scroll view without top inset
│   │   ├── ResizeHandle.swift              # Resizable inspector handle
│   │   ├── SafeProgressView.swift          # Progress view component
│   │   ├── SettingsView.swift              # Settings/preferences view
│   │   ├── SidebarTabBarView.swift         # Sidebar tab bar UI component
│   │   ├── TabChoiceDialog.swift           # Dialog for choosing tab when file already open
│   │   └── TimelineView.swift              # Timeline zoom control for charts
│   │
│   ├── Inspector/                   # Inspector panel
│   │   ├── InfoInspectorView/              # Main inspector components
│   │   │   ├── InfoInspectorView.swift     # Main inspector view
│   │   │   ├── QuickSummaryCard.swift      # Summary card component
│   │   │   ├── CollapsibleSection.swift    # Collapsible metadata sections
│   │   │   ├── KeyValueComponents.swift    # Key-value display components
│   │   │   ├── ExtendedVideoInfo+Metadata.swift # Metadata display extensions
│   │   │   ├── AudioTrackInfo+Display.swift # Audio track display extensions
│   │   │   ├── CopiedBanner.swift          # Copy-to-clipboard feedback
│   │   │   ├── EmptyInspectorState.swift   # Empty state view
│   │   │   ├── SectionDivider.swift        # Section divider component
│   │   │   └── ViewHelpers.swift           # View helper utilities
│   │   ├── InfoInspectorView+Copy.swift    # Copy functionality extensions
│   │   └── InfoInspectorView+Header.swift  # Header component extensions
│   │
│   ├── Keyframes/                   # Keyframe visualization
│   │   └── KeyframeThumbnailStrip.swift    # Thumbnail strip component
│   └── Player/                      # Video player
│       └── VideoPlayerView.swift           # Video player view with statistics overlay
│
└── Utils/                           # Core utilities organized by category
    ├── Analysis/                    # Frame and bitrate analysis
    │   ├── ExtractFramesStream.swift       # AsyncStream-based frame extraction
    │   ├── FrameAggregation.swift          # Frame data aggregation utilities
    │   └── FrameAnalysis.swift             # Bitrate/FPS analysis utilities
    │
    ├── Extraction/                  # Bitrate extraction
    │   ├── FastBitrateExtractor.swift      # Optimized bitrate extraction
    │   ├── FastBitrateExtractor+Cursor.swift # Cursor-based extraction
    │   ├── FastBitrateExtractor+Reader.swift # Reader-based extraction
    │   ├── FormatDetector.swift            # Format detection utilities
    │   ├── FragmentedMP4Extractor.swift    # Fragmented MP4 extraction
    │   └── TSBitrateExtractor.swift        # Transport Stream extraction
    │
    ├── Formatting/                  # Formatting and display utilities
    │   ├── AspectRatioUtils.swift          # Aspect ratio calculations
    │   ├── ColorUtils.swift                # HDR detection, color metadata helpers
    │   ├── DesignSystem.swift              # Design system constants and utilities
    │   ├── FormatUtils.swift               # FourCC, duration, codec name utilities
    │   └── VideoUtils.swift                # File size and bitrate utilities
    │
    ├── Media/                       # Media loading and processing
    │   ├── AudioInfoLoader.swift           # Audio track loading
    │   ├── GenerateKeyframeThumbnails.swift # Thumbnail generation
    │   ├── VideoInfoLoader.swift           # Main metadata extraction orchestrator
    │   ├── VideoInfoLoader+AV1.swift       # AV1-specific parsing
    │   ├── VideoInfoLoader+BasicInfo.swift # Basic video info extraction
    │   ├── VideoInfoLoader+Codec.swift     # Codec configuration parsing
    │   ├── VideoInfoLoader+Color.swift     # Color and HDR info extraction
    │   ├── VideoInfoLoader+Duration.swift  # Duration extraction
    │   ├── VideoInfoLoader+Metadata.swift  # Metadata extraction
    │   └── VideoInfoLoader+VideoTrack.swift # Video track info extraction
    │
    └── Parsing/                     # Codec and format parsing
        ├── AV1Parser.swift                 # AV1 codec configuration parsing
        ├── KeyframeMarker.swift            # Keyframe detection
        └── VUIParser.swift                 # Video Usability Information parsing
```

## Key modules and responsibilities

### UI Layer

- **FramePeekApp.swift** – App entry point with `@main`. Creates `TabManager` and provides it via `@EnvironmentObject`.
- **FramePeek.swift** – Main window layout and structure with drag-and-drop support. Manages inspector panel visibility via `@State`. Integrates with `TabManager` for multi-tab support.
- **ViewModels/MediaInspectorViewModel.swift** – `@MainActor` ViewModel that:
  - Manages file selection via `pickFile()`.
  - Coordinates async loading of metadata, frames, and keyframes.
  - Exposes published properties: `samples`, `extendedInfo`, `keyframeThumbs`, etc.
  - Supports configurable sampling modes (auto, everyFrame, interval).
  - Supports bitrate visualization modes (second, frame, GOP).
  - Handles analysis cancellation and progress tracking.
  - Extensions: `+Sampling.swift`, `+Thumbnails.swift`, `+FileHandling.swift` organize related functionality.
- **ViewModels/TabManager.swift** – `@MainActor` ObservableObject that manages multiple tabs:
  - Each tab has its own `MediaInspectorViewModel` instance.
  - Tracks tab selection, creation, and removal.
  - Updates tab display names based on loaded files.
  - Handles tab switching and cleanup when tabs are closed.
- **ViewModels/PlayerViewModelManager.swift** – Manages the active ViewModel for the video player window, allowing the player to sync with the currently selected tab.

### Views Organization

- **Views/Chart/** – Bitrate visualization:
  - **BitrateChartView.swift** – Main interactive chart using Swift Charts.
  - **BitrateChartComponents.swift** – Chart sub-components and styling.
  - **BitrateChartDownsampling.swift** – LTTB (Largest-Triangle-Three-Buckets) downsampling algorithm for performance.
  - **BitrateChartStatistics.swift** – Statistics overlay for chart.
- **Views/Common/** – Shared components:
  - **AboutView.swift** – About dialog with app information and features.
  - **LiquidGlassToolbarButton.swift** – Toolbar button with liquid glass styling.
  - **NoTopInsetScrollView.swift** – Scroll view without top inset.
  - **ResizeHandle.swift** – Drag handle for resizing inspector width.
  - **SafeProgressView.swift** – Progress view component.
  - **SettingsView.swift** – Settings/preferences view with appearance, inspector, and sampling mode options.
  - **SidebarTabBarView.swift** – Sidebar tab bar UI component for displaying and managing multiple tabs.
  - **TabChoiceDialog.swift** – Dialog shown when attempting to open a file in a tab that already has a file loaded.
  - **TimelineView.swift** – Interactive timeline for zooming into specific time ranges in the chart.
- **Views/Inspector/** – Inspector panel:
  - **InfoInspectorView/InfoInspectorView.swift** – Main inspector view orchestrating all metadata display.
  - **InfoInspectorView/QuickSummaryCard.swift** – Summary card with key metrics.
  - **InfoInspectorView/CollapsibleSection.swift** – Reusable collapsible section component.
  - **InfoInspectorView/KeyValueComponents.swift** – Key-value pair display components.
  - **InfoInspectorView/ExtendedVideoInfo+Metadata.swift** – Metadata display extensions.
  - **InfoInspectorView/AudioTrackInfo+Display.swift** – Display extensions for audio track info.
  - **InfoInspectorView/CopiedBanner.swift** – Copy-to-clipboard feedback banner.
  - **InfoInspectorView/EmptyInspectorState.swift** – Empty state when no file is loaded.
  - **InfoInspectorView/SectionDivider.swift** – Visual section divider component.
  - **InfoInspectorView/ViewHelpers.swift** – Helper utilities for views.
  - **InfoInspectorView+Copy.swift** – Copy functionality extensions.
  - **InfoInspectorView+Header.swift** – Header component extensions.
- **Views/Keyframes/** – Keyframe visualization:
  - **KeyframeThumbnailStrip.swift** – Horizontal scrollable strip of keyframe thumbnails with GOP interval display.
- **Views/Player/** – Video player:
  - **VideoPlayerView.swift** – Video player view using AVPlayer with statistics overlay showing resolution, frame rate, current time, and bitrate.

### Core Utilities (Utils/)

Utilities are organized into subdirectories by category:

#### Utils/Media/ – Media loading and processing

- **VideoInfoLoader.swift**
  - Orchestrates metadata extraction from AVAsset via `getExtendedInfo(url:asset:)`.
  - Loads duration, video track, format descriptions, color/HDR info, PAR/DAR, bitrates.
  - Parses codec configuration atoms (hvcC, avcC, vpcC, av1C, dvcC/dvvC).
  - Returns `ExtendedVideoInfo`.

- **AudioInfoLoader.swift**
  - `loadAudioInfo(asset:)` → returns `[AudioTrackInfo]` with codec, channels, sample rate, bitrate, language.

- **GenerateKeyframeThumbnails.swift** – Thumbnail generation:
  - `GenerateKeyframeThumbnails(asset:keyframeTimes:maxThumbnails:thumbHeight:)` → `[KeyframeThumbnail]`

#### Utils/Analysis/ – Frame and bitrate analysis

- **ExtractFramesStream.swift** – AsyncStream-based frame extraction utilities (used internally by FastBitrateExtractor).

- **FrameAnalysis.swift** – Frame rate statistics and extraction utilities:
  - `frameRateStats(from:)` → average FPS, min/max intervals
  - Frame extraction helpers for progressive updates

- **FrameAggregation.swift** – Frame data aggregation utilities:
  - `aggregateFrames(rawFrames:mode:averageFPS:maxSamples:)` → aggregates raw frames into BitrateSamples
  - Supports different visualization modes (second, frame, GOP)
  - Converts raw frame data to `BitrateSample` arrays for charting

#### Utils/Extraction/ – Bitrate extraction

- **FastBitrateExtractor.swift** – Main bitrate extraction orchestrator:
  - `extractBitratesFast(asset:options:)` → `AsyncStream<FrameAnalysisUpdate>`
  - Routes to format-specific extractors based on detected container format
  - High-performance bitrate extraction with configurable accuracy
  - Supports both cursor-based and reader-based extraction paths
  - Format-specific optimizations for MP4, fragmented MP4, and Transport Stream

- **FastBitrateExtractor+Cursor.swift** – Cursor-based extraction implementation (fast path).

- **FastBitrateExtractor+Reader.swift** – Reader-based extraction implementation (more accurate, slower).

- **FormatDetector.swift** – Detects media format for format-specific extraction optimizations.

- **FragmentedMP4Extractor.swift** – Specialized extraction for fragmented MP4 files.

- **TSBitrateExtractor.swift** – Specialized extraction for Transport Stream files with packet overhead accounting.

#### Utils/Formatting/ – Formatting and display utilities

- **VideoUtils.swift** – File size and bitrate utilities:
  - `getFileSizeString(for: URL)` → formatted size (e.g., "123.45 MiB")
  - `getFileSizeBytes(for: URL)` → raw bytes
  - `getOverallBitrateString(asset:fileURL:)` → overall bitrate in kb/s

- **FormatUtils.swift** – Formatting and codec mapping:
  - `fourCCToString(_:)` → FourCC code to string
  - `formatDuration(seconds:)` → human-readable duration
  - `channelLayoutDescription(channels:)` → "Stereo", "5.1", etc.
  - `audioCodecName(_:)` / `videoCodecName(_:)` → human-readable codec names
  - `parseVP9Profile(_:)` → VP9 profile parsing

- **ColorUtils.swift** – HDR and color metadata:
  - `detectHDRFormat(transferFunction:colorPrimaries:hasDolbyVisionConfig:)`
  - `colorPrimariesDescription(_:)`, `transferFunctionDescription(_:)`, `matrixDescription(_:)`

- **AspectRatioUtils.swift** – Aspect ratio calculations:
  - `calculateDisplayAspectRatio(width:height:parH:parV:)`
  - `resolutionCategory(width:height:)` → "4K UHD", "Full HD", etc.
  - `gcd(_:_:)` – helper for ratio simplification

- **DesignSystem.swift** – Design system constants:
  - Colors, spacing, padding, corner radius, border widths
  - Centralized design tokens for consistent UI styling

#### Utils/Parsing/ – Codec and format parsing

- **AV1Parser.swift** – AV1 codec configuration:
  - `parseAV1C(_:)` → `AV1ConfigSummary` (profile, level, bitDepth, chroma, fullRange)
  - `av1LevelDescription(_:)`, `av1ProfileDescription(_:)`

- **KeyframeMarker.swift** – Keyframe detection:
  - `extractKeyframes(asset:maxKeyframes:minSpacingSeconds:)` → `[KeyframeMarker]`
  - Uses `kCMSampleAttachmentKey_NotSync` to identify sync samples (I-frames).

- **VUIParser.swift** – Video Usability Information parsing:
  - Parses VUI parameters from codec configuration for additional metadata.

### Models

- **Models/MediaModels.swift** – Core data models:
  - **ExtendedVideoInfo** – All video metadata fields (see Data model section).
  - **AudioTrackInfo** – Per-track audio info (index, codec, channels, sampleRate, bitrate, language).
  - **FrameAnalysisResult** – Batch result with samples and FPS stats.
  - **FrameSamplingOptions** – Configures sampling behavior (interval, maxSamples, emitEveryNSamples, visualizationMode, formatAccuracyMode).
  - **BitrateVisualizationMode** – Enum for bitrate aggregation: `.second`, `.frame`, `.gop`.
  - **FormatAccuracyMode** – Enum for format-specific accuracy: `.performance`, `.balanced`, `.accuracy`.
  - **AV1ConfigSummary** – Parsed AV1 configuration.
  - **KeyframeMarker** – Keyframe position and metadata.
  - **KeyframeThumbnail** – Thumbnail image with associated time.
  - **RawFrame** – Raw frame data for aggregation.

- **Models/BitrateSample.swift** – `Identifiable` struct with `time` and `bitrate` for chart data.

### Other Files

- **fileUtils.swift** – `openFileDialog(completion:)` using NSOpenPanel for file selection.
- **FramePeek.entitlements** – App entitlements for sandboxing and file access permissions.

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

### Bitrate Visualization Modes

The app supports three visualization modes for aggregating bitrate data:

- **second** – Aggregate bitrate per second (default).
- **frame** – Show bitrate per individual frame.
- **gop** – Aggregate by Group of Pictures (GOP) boundaries.

Visualization mode is configured via `MediaInspectorViewModel.visualizationMode` and affects how `FrameAggregation` processes raw frame data into `BitrateSample` arrays.

### Progressive extraction via AsyncStream

```swift
for await update in extractBitratesFast(asset: asset, options: options) {
    // update.appendedSamples: new BitrateSample batch
    // update.rawFrames: raw frame data for re-aggregation
    // update.averageFPS, minInterval, maxInterval: running stats
    // update.isFinished: true when complete
}
```

The `options` parameter includes `FrameSamplingOptions` which specifies:
- Sampling mode (auto/everyFrame/interval)
- Visualization mode (second/frame/gop)
- Accuracy preference (cursor vs reader-based extraction)
- Format accuracy mode (performance/balanced/accuracy)
- Maximum samples and batch sizes
- Format-specific options (TS overhead accounting, segment boundary smoothing)

### Keyframe extraction

```swift
let keyframes = await extractKeyframes(asset: asset, maxKeyframes: 20_000)
// Returns [KeyframeMarker] with time positions of sync samples
```

Keyframe extraction runs independently of frame analysis and can be triggered separately. Thumbnails are generated asynchronously after keyframes are detected.

## New Features and Improvements

### Multi-Tab Support

- **TabManager** – Manages multiple tabs, each with its own `MediaInspectorViewModel` instance.
- **SidebarTabBarView** – Sidebar-style tab bar UI for switching between tabs.
- **TabChoiceDialog** – Prompts users to choose between opening a file in the current tab or a new tab when a file is already loaded.
- Tabs can be created, closed, and switched independently.
- Each tab maintains its own analysis state, samples, and keyframes.

### Settings and Preferences

- **SettingsView** – Comprehensive settings interface accessible via `Cmd+,`.
- **Appearance Settings** – Choose between System, Light, or Dark appearance.
- **Inspector Settings** – Control inspector visibility and default state.
- **Sampling Settings** – Configure default sampling mode and preferences.
- Settings persist via `UserDefaults` and are shared across tabs.

### Chart Performance Optimizations

- **LTTB Downsampling** (`BitrateChartDownsampling.swift`) – Largest-Triangle-Three-Buckets algorithm preserves visual shape while reducing point count for large datasets.
- Chart automatically downsamples when displaying more than a threshold number of points.
- Separate chart components for better organization and maintainability.

### Inspector Panel Enhancements

- **Resizable Inspector** – Inspector width is configurable via SwiftUI's inspector modifier.
- Inspector visibility can be toggled via `Cmd+I` keyboard shortcut.
- Inspector uses native SwiftUI inspector panel with collapsible sections.

### Bitrate Visualization Modes

- Support for different aggregation strategies: per-second, per-frame, or per-GOP.
- Configurable via `MediaInspectorViewModel.visualizationMode`.
- Affects how raw frame data is aggregated into chart samples.
- Can be changed dynamically and samples are re-aggregated from raw frames.

### Video Player

- **VideoPlayerView** – Separate window for video playback using AVPlayer.
- **Statistics Overlay** – Real-time display of resolution, frame rate, current time, and bitrate at playback position.
- **PlayerViewModelManager** – Manages synchronization between player window and active tab.
- Customizable settings: auto-play, show controls, mute, statistics overlay position.
- Statistics overlay is draggable and remembers position.

### ViewModel Organization

- ViewModel logic split into extensions for better maintainability:
  - `+Sampling.swift` – Frame sampling and analysis coordination.
  - `+Thumbnails.swift` – Thumbnail generation logic.
  - `+FileHandling.swift` – File loading, tab choice handling, and state management.

### Localization (i18n)

- **Localizable.xcstrings** – Centralized localization file using SwiftUI's built-in localization system.
- **Automatic Localization** – All `Text()` views with string literals automatically localize.
- **Explicit Localization** – For computed strings and `.help()` modifiers, use `String(localized:)`.
- **System Language** – App automatically follows the user's macOS system language preference.
- See [LOCALIZATION.md](LOCALIZATION.md) for detailed localization guide.

## Concurrency and performance

- Uses Swift Concurrency (`async`/`await`) throughout.
- `MediaInspectorViewModel` is `@MainActor` to safely update `@Published` properties.
- Heavy work runs on `.userInitiated` priority via `Task.detached`.
- Frame extraction uses `AsyncStream` for progressive UI updates.
- `AVAssetReaderTrackOutput.alwaysCopiesSampleData = false` for performance.
- Keyframe extraction avoids decoding by inspecting sample attachment flags.
- Tasks are cancellable – the ViewModel cancels in-flight tasks when loading a new file.
- Chart downsampling ensures smooth rendering even with thousands of data points.
- Format-specific optimizations for different container formats (MP4, fragmented MP4, TS).

## Error handling and defaults

- Many lookups use `try? await` with `guard`/fallbacks to avoid throwing.
- Unknown or missing fields are left `nil` or filled with `"N/A"` / `"Unknown"`.
- Calculations are guarded by sanity checks (e.g., `> 0` values for dimensions, fps, bitrate).
- Task cancellation is checked via `Task.isCancelled` in extraction loops.

## Platform notes

- Built for **macOS 15.2+** (Sequoia) using SwiftUI and AppKit (`NSOpenPanel`, `NSImage`).
- Uses `AVURLAsset`, `AVAssetReader`, `AVAssetImageGenerator` from AVFoundation.
- Uses Swift Charts framework (macOS 15.0+) for interactive bitrate visualization.
- Sandboxed apps must have read access to selected file URLs (see `FramePeek.entitlements`).
- Supported file types: `.mp4`, `.mov`, `.avi`, `.mpeg`, and other movie types via `UTType`.
- Minimum deployment target: macOS 15.2 (configured in Xcode project settings).

## Extending the inspector

### New container/format detection

- Update file extension handling or probe container via AVAsset metadata.
- Container format is currently derived from file extension in `Utils/Media/VideoInfoLoader.swift`.

### New codec parsing

- Add parser for the codec's configuration atom (e.g., in `Utils/Media/VideoInfoLoader.swift`).
- Add FourCC → friendly name mapping in `Utils/Formatting/FormatUtils.swift` (`videoCodecMappings`).
- See `Utils/Parsing/AV1Parser.swift` for a reference implementation of atom parsing.

### Better chroma/bit depth detection

- Prefer authoritative fields from codec configs over heuristics.
- AV1 already extracts bit depth from `av1C` atom; similar approach works for HEVC/AVC.

### HDR detection rules

- Expand `detectHDRFormat(...)` in `Utils/Formatting/ColorUtils.swift` for additional transfer functions/primaries.
- Currently supports: Dolby Vision, HDR10, HLG, PQ, Wide Color Gamut (BT.2020).

### Audio metadata enhancements

- Enhance `loadAudioInfo(asset:)` in `Utils/Media/AudioInfoLoader.swift` to parse audio codec config atoms.
- Add Dolby Atmos detection, format profiles, etc.

### Additional frame analysis

- Add scene change detection using frame difference metrics in `Utils/Analysis/FrameAnalysis.swift`.
- Compute GOP structure from keyframe intervals.
- Track frame types (I/P/B) if decodable from sample attachments.
- Add new visualization modes in `Models/MediaModels.swift` (`BitrateVisualizationMode`).

### Placeholder fields to populate

- `containerFormatProfile` – could parse moov/mdat structure or ftyp atom in `Utils/Media/VideoInfoLoader.swift`.
- `maxBitrate` – requires parsing codec-specific config (e.g., VUI in AVC/HEVC).
- `frameRateMode` – detect CFR vs VFR from frame interval variance in `Utils/Analysis/FrameAnalysis.swift`.

## Localization Guidelines

FramePeek supports localization (i18n) using SwiftUI's built-in localization system. When adding or modifying user-facing strings:

1. **Text() Views**: Use string literals directly – they automatically localize when present in `Localizable.xcstrings`.
   ```swift
   Text("Settings")  // Automatically localized
   ```

2. **Computed Strings**: Use `String(localized:)` for strings passed as parameters or computed properties.
   ```swift
   Text(String(localized: "Settings"))
   FeatureRow(title: String(localized: "Bitrate Analysis"), ...)
   ```

3. **Help Modifiers**: Always use `String(localized:)` for `.help()` modifiers.
   ```swift
   .help(String(localized: "New Tab"))
   ```

4. **String Interpolation**: Use format strings with `String(localized:)`.
   ```swift
   Text(String(format: String(localized: "Version %@"), version))
   ```

5. **Adding New Strings**: When adding new user-facing strings:
   - Use the string literal in your code.
   - Xcode will automatically extract it to `Localizable.xcstrings` when you build.
   - Or manually add entries to `Localizable.xcstrings` following the existing format.

6. **Enum Display Names**: For enum `displayName` properties, use `String(localized:)`.
   ```swift
   var displayName: String {
       switch self {
       case .auto: return String(localized: "Automatic")
       case .interval: return String(localized: "Fixed Interval")
       }
   }
   ```

See [LOCALIZATION.md](LOCALIZATION.md) for complete localization documentation.

## Code style and contribution rules

- Prefer Swift and Apple frameworks; use Swift Concurrency over GCD/Combine unless the surrounding code dictates otherwise.
- Keep parsing helpers pure and testable; isolate I/O at the orchestration layer.
- Use `@MainActor` for ViewModels and ensure UI updates happen on the main thread.
- Follow existing naming conventions: `load*`, `get*`, `parse*`, `extract*`, `detect*`.
- **Always use localization** for user-facing strings (see Localization Guidelines above).
- **Do not add unnecessary comments** - code should be self-explanatory. Only add comments when they provide essential context that cannot be inferred from the code itself.
- When proposing changes to an existing file, always include the entire file content in a single code block, prefixed with the filename:

```swift:SomeFile.swift
// Entire file content goes here.
```

## Testing

- Unit tests are located in `FramePeekTests/`.
- UI tests are in `FramePeekUITests/`.
- Parsing helpers should be pure functions for easy unit testing.
- Use sample media files with known properties for integration testing.
