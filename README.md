# MediaInspector

A professional macOS application for inspecting video and audio files with comprehensive metadata analysis, bitrate visualization, and keyframe detection.

![MediaInspector Screenshot](screenshot.png)

## Overview

MediaInspector is a native macOS application built with SwiftUI that leverages AVFoundation and CoreMedia to provide detailed analysis of media files. It offers an intuitive interface for examining video and audio properties, visualizing bitrate patterns, and exploring keyframe structures.

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
- **Interactive Charts**: Per-frame bitrate visualization with Swift Charts
- **Flexible Sampling**: Automatic, fixed interval, or per-frame sampling modes
- **Progressive Updates**: Real-time bitrate analysis with streaming updates
- **Performance Optimized**: Efficient frame extraction with configurable accuracy settings

### Keyframe Detection
- **Visual Timeline**: Timeline visualization of keyframe positions
- **Thumbnail Strip**: Horizontal strip of keyframe thumbnails for quick navigation
- **Sync Sample Detection**: Identifies I-frames (intra-coded frames) without decoding

## System Requirements

- **macOS**: 15.2 (Sequoia) or later
- **Xcode**: 15.0 or later (for building from source)
- **Swift**: 5.0 or later

## Installation

### Building from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/MediaInspector.git
   cd MediaInspector
   ```

2. **Open the project**:
   ```bash
   open MediaInspector/MediaInspector.xcodeproj
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
- **Metal**: Graphics acceleration

No external dependencies or package managers required.

## Usage

### Opening Files

1. **File Dialog**: Click the "Open…" button in the toolbar or press `Cmd+O`
2. **Drag and Drop**: Drag a video or audio file onto the main window
3. **Supported Formats**: MP4, MOV, AVI, MPEG, and other common media formats

### Analysis Settings

Before analyzing a file, you can configure sampling options:

- **Automatic Mode**: Automatically determines optimal sampling based on video duration
- **Fixed Interval**: Sample at regular time intervals (configurable)
- **High Accuracy**: Enable for more precise bitrate measurements (may be slower)

### Interface

- **Main Chart**: Interactive bitrate visualization over time
- **Inspector Panel**: Toggle with `Cmd+Option+I` or the sidebar button
  - Quick summary card with key metrics
  - Collapsible sections for detailed metadata
  - Audio track information
  - Keyframe timeline and thumbnails
- **Resizable Inspector**: Drag the left edge of the inspector to adjust width

### Keyboard Shortcuts

- `Cmd+O`: Open file dialog
- `Cmd+Option+I`: Toggle inspector panel
- `Esc`: Cancel ongoing analysis

## Project Structure

```
MediaInspector/
├── MediaInspectorApp.swift          # App entry point
├── MediaInspector.swift              # Main window and UI
├── MediaInspectorViewModel.swift     # ViewModel and state management
├── AboutView.swift                   # About dialog
├── BitrateChartView.swift            # Bitrate visualization
├── BitrateSample.swift               # Bitrate data model
├── KeyframeTimelineView.swift        # Keyframe timeline
├── KeyframeThumbnailStrip.swift      # Keyframe thumbnails
├── fileUtils.swift                   # File dialog utilities
└── InfoInspectorView/                # Inspector panel components
    ├── InfoInspectorView.swift
    ├── QuickSummaryCard.swift
    ├── CollapsibleSection.swift
    ├── KeyValueComponents.swift
    ├── ExtendedVideoInfo+Metadata.swift
    ├── AudioTrackInfo+Display.swift
    └── ...
└── Utils/                            # Core utilities
    ├── VideoInfoLoader.swift         # Video metadata extraction
    ├── AudioInfoLoader.swift         # Audio track loading
    ├── FormatUtils.swift             # Format and codec utilities
    ├── ColorUtils.swift              # HDR and color detection
    ├── AspectRatioUtils.swift        # Aspect ratio calculations
    ├── VideoUtils.swift              # File size and bitrate utilities
    ├── AV1Parser.swift               # AV1 codec parsing
    ├── FrameAnalysis.swift           # Frame rate analysis
    ├── ExtractFramesStream.swift     # AsyncStream frame extraction
    ├── FrameAggregation.swift        # Frame data aggregation
    ├── FastBitrateExtractor.swift    # Optimized bitrate extraction
    ├── KeyframeMarker.swift          # Keyframe detection
    ├── GenerateKeyframeThumbnails.swift # Thumbnail generation
    └── MediaModels.swift             # Data models
```

## Architecture

MediaInspector follows a clean architecture pattern:

- **UI Layer**: SwiftUI views with `@MainActor` ViewModels
- **Business Logic**: Pure utility functions for parsing and analysis
- **Data Layer**: AVFoundation and CoreMedia for media access
- **Concurrency**: Swift Concurrency (`async`/`await`) for all async operations

The app uses progressive loading with `AsyncStream` to provide real-time updates during analysis, ensuring a responsive user experience even with large files.

## Contributing

Contributions are welcome! Please see [instructions.md](instructions.md) for detailed information about the codebase structure and contribution guidelines.

## License

See [LICENSE](LICENSE) file for details.

## Author

Built by Oscar Nord in Stockholm, Sweden

---

For detailed technical documentation and contribution guidelines, see [instructions.md](instructions.md).
