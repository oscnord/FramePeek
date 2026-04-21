# FramePeek

A macOS application for inspecting video and audio files with metadata analysis, bitrate visualization, and keyframe detection.

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

### CLI Tool
- **Command-line interface** for batch processing and automation
- JSON, text, and CSV output formats
- All analysis capabilities available via CLI

### REST API
- **Embedded HTTP server** for remote analysis
- Start/stop from the Server tab in the app
- Job queue with progress tracking

## System Requirements

- **macOS**: 15.2 (Sequoia) or later
- **Xcode**: 15.0 or later (for building from source)
- **Swift**: 5.0 or later

## Installation

### Building from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/oscnord/FramePeek.git
   cd FramePeek
   ```

2. **Open the project**:
   ```bash
   open FramePeek/FramePeek.xcodeproj
   ```

3. **Build and run**:
   - Select your target Mac in Xcode
   - Press `Cmd+R` to build and run

## Usage

### Opening Files

1. **File Dialog**: Click the "Open…" button in the toolbar or press `Cmd+O`
2. **Drag and Drop**: Drag a video or audio file onto the main window
3. **Supported Formats**: MP4, MOV, AVI, MPEG, and other common media formats supported by AVFoundation

### CLI Usage

```bash
# Basic metadata
framepeek-cli video.mp4 --info --pretty

# All analyses
framepeek-cli video.mp4 --all --pretty

# Bitrate as CSV
framepeek-cli video.mp4 --bitrate --format csv

# Multiple files
framepeek-cli *.mp4 --info --parallel
```

### REST API

1. Click "Server" in the sidebar
2. Click "Start Server"
3. Use the API at `http://127.0.0.1:8080`

See `bruno/` folder for a Bruno collection to test the API.

### Keyboard Shortcuts

- `Cmd+O`: Open file dialog
- `Cmd+I`: Toggle inspector panel
- `Cmd+T`: New tab
- `Cmd+,`: Open settings

## Architecture

FramePeek follows a clean architecture pattern:

- **UI Layer**: SwiftUI views with `@MainActor` ViewModels
- **Business Logic**: Pure utility functions for parsing and analysis
- **Data Layer**: AVFoundation and CoreMedia for media access
- **Concurrency**: Swift Concurrency (`async`/`await`) for all async operations

## Contributing

Contributions are welcome! Please see [instructions.md](instructions.md) for detailed information about the codebase structure and contribution guidelines.

## License

This project is licensed under the [MIT License](LICENSE).

## Author

Built by Oscar Nord in Stockholm, Sweden
