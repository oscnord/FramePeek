# FramePeek

A professional macOS application for inspecting video and audio files with comprehensive metadata analysis, bitrate visualization, and keyframe detection.

## Overview

FramePeek is a native macOS application built with SwiftUI that leverages AVFoundation and CoreMedia to provide detailed analysis of media files. It offers an intuitive interface for examining video and audio properties, visualizing bitrate patterns, and exploring keyframe structures.

## Features

### Video Analysis
- **Comprehensive Metadata**: Container format, codec information, resolution, frame rate, pixel aspect ratio, and display aspect ratio
- **Color & HDR Information**: Color space, chroma subsampling, bit depth, color primaries, transfer functions, and HDR format detection (Dolby Vision, HDR10, HLG, PQ)
- **Codec Support**: HEVC (H.265), AVC (H.264), AV1, VP9, and more with detailed configuration parsing
- **Resolution Categories**: Automatic classification (4K UHD, Full HD, etc.)

### Audio Analysis
- **Multi-Track Support**: Detailed information for all audio tracks
- **Track Properties**: Codec, channel layout, sample rate, bitrate, and language information
- **Codec Detection**: AAC, AC-3, E-AC-3, MP3, Opus, and more

### Bitrate Analysis
- **Interactive Charts**: Bitrate visualization with Swift Charts
- **Flexible Sampling**: Automatic, fixed interval, or per-frame sampling modes
- **Visualization Modes**: Aggregate bitrate by second, frame, or GOP (Group of Pictures)
- **Progressive Updates**: Real-time bitrate analysis with streaming updates
- **Performance Optimized**: Efficient frame extraction with configurable accuracy settings and LTTB downsampling
- **Timeline Zoom**: Interactive timeline for zooming into specific time ranges

### Keyframe Detection
- **Thumbnail Strip**: Horizontal scrollable strip of keyframe thumbnails for quick navigation
- **Sync Sample Detection**: Identifies I-frames (intra-coded frames) without decoding
- **GOP Interval Display**: Shows Group of Pictures intervals for each keyframe

### Video Player
- **Built-in Player**: Play videos with AVPlayer integration
- **Statistics Overlay**: Real-time display of resolution, frame rate, current time, and bitrate
- **Customizable Controls**: Toggle controls, auto-play, and mute settings

## System Requirements

- **macOS**: 15.2 (Sequoia) or later
- **Xcode**: 15.0 or later (for building from source)
- **Swift**: 5.0 or later

## Installation

### Building from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/FramePeek.git
   cd FramePeek
   ```

2. **Open the project**:
   ```bash
   open FramePeek/FramePeek.xcodeproj
   ```

3. **Build and run**:
   - Select your target Mac in Xcode
   - Press `Cmd+R` to build and run, or use Product → Run

### Dependencies

The project uses the following Apple frameworks (included with macOS):
- **AVFoundation**: Media file inspection and frame extraction
- **CoreMedia**: Low-level media format handling
- **SwiftUI**: User interface
- **AppKit**: macOS-specific features (file dialogs, images)
- **Charts**: Interactive chart visualization (macOS 15.0+)

No external dependencies or package managers required.

## Usage

### Opening Files

1. **File Dialog**: Click the "Open…" button in the toolbar or press `Cmd+O`
2. **Drag and Drop**: Drag a video or audio file onto the main window
3. **Supported Formats**: MP4, MOV, AVI, MPEG, and other common media formats supported by AVFoundation

### Analysis Settings

Configure sampling options in Settings:

- **Automatic Mode**: Automatically determines optimal sampling based on video duration
- **Fixed Interval**: Sample at regular time intervals (configurable)
- **Per-Frame Mode**: Sample every frame (for high accuracy)
- **Visualization Mode**: Choose how to aggregate bitrate data (per second, per frame, or per GOP)
- **Accuracy Mode**: Balance between performance and accuracy (Performance, Balanced, Accuracy)

### Interface

- **Main Chart**: Interactive bitrate visualization over time with zoomable timeline
- **Inspector Panel**: Toggle with `Cmd+I` or the sidebar button
  - Quick summary card with key metrics
  - Collapsible sections for detailed metadata
  - Audio track information
  - Keyframe thumbnail strip
- **Video Player**: Separate window for video playback with statistics overlay
- **Tab Management**: Multiple tabs for analyzing different files simultaneously

### Keyboard Shortcuts

- `Cmd+O`: Open file dialog
- `Cmd+I`: Toggle inspector panel
- `Cmd+T`: New tab
- `Cmd+,`: Open settings
- `Esc`: Cancel ongoing analysis

## Project Structure

```
FramePeek/
├── FramePeekApp.swift          # App entry point
├── FramePeek.swift              # Main window and UI
├── fileUtils.swift              # File dialog utilities
│
├── Models/                      # Data models
│   ├── BitrateSample.swift      # Bitrate data model
│   └── MediaModels.swift       # ExtendedVideoInfo, AudioTrackInfo, etc.
│
├── ViewModels/                  # ViewModels and extensions
│   ├── MediaInspectorViewModel.swift           # ViewModel and state management
│   ├── MediaInspectorViewModel+FileHandling.swift
│   ├── MediaInspectorViewModel+Sampling.swift
│   ├── MediaInspectorViewModel+Thumbnails.swift
│   ├── PlayerViewModelManager.swift
│   └── TabManager.swift
│
├── Views/                       # UI components
│   ├── Chart/                   # Bitrate chart components
│   │   ├── BitrateChartView.swift
│   │   ├── BitrateChartComponents.swift
│   │   ├── BitrateChartDownsampling.swift
│   │   └── BitrateChartStatistics.swift
│   ├── Common/                  # Shared components
│   │   ├── AboutView.swift
│   │   ├── LiquidGlassToolbarButton.swift
│   │   ├── NoTopInsetScrollView.swift
│   │   ├── ResizeHandle.swift
│   │   ├── SafeProgressView.swift
│   │   ├── SettingsView.swift
│   │   ├── SidebarTabBarView.swift
│   │   ├── TabChoiceDialog.swift
│   │   └── TimelineView.swift
│   ├── Inspector/               # Inspector panel
│   │   ├── InfoInspectorView/
│   │   │   ├── InfoInspectorView.swift
│   │   │   ├── QuickSummaryCard.swift
│   │   │   ├── CollapsibleSection.swift
│   │   │   └── ...
│   │   ├── InfoInspectorView+Copy.swift
│   │   └── InfoInspectorView+Header.swift
│   ├── Keyframes/               # Keyframe visualization
│   │   └── KeyframeThumbnailStrip.swift
│   └── Player/                  # Video player
│       └── VideoPlayerView.swift
│
└── Utils/                       # Core utilities
    ├── Analysis/                # Frame and bitrate analysis
    │   ├── ExtractFramesStream.swift
    │   ├── FrameAggregation.swift
    │   └── FrameAnalysis.swift
    ├── Extraction/              # Bitrate extraction
    │   ├── FastBitrateExtractor.swift
    │   ├── FastBitrateExtractor+Cursor.swift
    │   ├── FastBitrateExtractor+Reader.swift
    │   ├── FormatDetector.swift
    │   ├── FragmentedMP4Extractor.swift
    │   └── TSBitrateExtractor.swift
    ├── Formatting/              # Formatting utilities
    │   ├── AspectRatioUtils.swift
    │   ├── ColorUtils.swift
    │   ├── DesignSystem.swift
    │   ├── FormatUtils.swift
    │   └── VideoUtils.swift
    ├── Media/                   # Media loading
    │   ├── AudioInfoLoader.swift
    │   ├── GenerateKeyframeThumbnails.swift
    │   ├── VideoInfoLoader.swift
    │   ├── VideoInfoLoader+AV1.swift
    │   ├── VideoInfoLoader+BasicInfo.swift
    │   ├── VideoInfoLoader+Codec.swift
    │   ├── VideoInfoLoader+Color.swift
    │   ├── VideoInfoLoader+Duration.swift
    │   ├── VideoInfoLoader+Metadata.swift
    │   └── VideoInfoLoader+VideoTrack.swift
    └── Parsing/                 # Codec parsing
        ├── AV1Parser.swift
        ├── KeyframeMarker.swift
        └── VUIParser.swift
```

## Architecture

FramePeek follows a clean architecture pattern:

- **UI Layer**: SwiftUI views with `@MainActor` ViewModels
- **Business Logic**: Pure utility functions for parsing and analysis
- **Data Layer**: AVFoundation and CoreMedia for media access
- **Concurrency**: Swift Concurrency (`async`/`await`) for all async operations

The app uses progressive loading with `AsyncStream` to provide real-time updates during analysis, ensuring a responsive user experience even with large files. Multiple tabs allow analyzing different files simultaneously, and the video player provides a separate window for playback with real-time statistics.

## Contributing

Contributions are welcome! Please see [instructions.md](instructions.md) for detailed information about the codebase structure and contribution guidelines.

## License

See [LICENSE](LICENSE) file for details.

## Author

Built by Oscar Nord in Stockholm, Sweden

---

For detailed technical documentation and contribution guidelines, see [instructions.md](instructions.md).
