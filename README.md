# FramePeek

[![Release](https://github.com/oscnord/FramePeek/actions/workflows/release.yml/badge.svg)](https://github.com/oscnord/FramePeek/actions/workflows/release.yml)

A macOS application for inspecting video and audio files with metadata analysis, bitrate visualization, GOP structure analysis, color analysis, and keyframe detection.

https://github.com/user-attachments/assets/bbd946b5-e3d0-4659-8169-be47a73d1ab8

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

### GOP Structure Analysis
- **Frame-Type Timeline**: I/P/B frame visualization with per-GOP details
- **GOP Heatmap**: Size and structure heatmap with viewport culling for large files
- **On-Demand Frame Details**: Per-frame size and type extraction with LRU caching

### Keyframe Detection
- **Thumbnail Strip**: Horizontal scrollable strip of keyframe thumbnails for quick navigation
- **Sync Sample Detection**: Identifies I-frames (intra-coded frames) without decoding
- **GOP Interval Display**: Shows Group of Pictures intervals for each keyframe

### Color & Exposure Analysis
- **Scopes**: Vectorscope, waveform scope, and RGB histogram
- **Color Temperature & Brightness**: CCT and brightness charts over time
- **HDR Analysis**: Dolby Vision configuration details and HDR content classification

### Audio Waveforms & A/V Sync
- **Per-Track Waveforms**: Peak waveform visualization for every audio track
- **Sync Analysis**: Audio/video timestamp drift detection

### Loudness (EBU R128)
- **Integrated Loudness**: ITU-R BS.1770-4 gated measurement in LUFS with R128 compliance badge
- **True Peak**: 4x-oversampled inter-sample peak detection in dBTP
- **Loudness Range**: EBU Tech 3342 LRA plus momentary/short-term maxima
- **Short-Term Chart**: 3-second loudness over time with the -23 LUFS target line

### HLS Ladder Inspection
- **Manifest Parsing**: RFC 8216 multivariant and media playlists, local folders or remote URLs
- **Declared vs Measured**: Per-variant peak/average segment bitrate compared against BANDWIDTH and AVERAGE-BANDWIDTH
- **QC Findings**: Segment duration compliance, cross-variant keyframe alignment, codec verification, ladder shape checks, and DRM detection, grouped by severity

### Container Inspector
- **Atom/Box Tree**: Browse MP4/MOV container structure with size breakdowns

### Video Player
- **Built-in Player**: Play videos with AVPlayer integration
- **Statistics Overlay**: Real-time display of resolution, frame rate, current time, and bitrate
- **Customizable Controls**: Toggle controls, auto-play, and mute settings

### CLI Tool
- **Command-line interface** for batch processing and automation
- JSON, text, and CSV output formats
- All analysis capabilities available via CLI

### MCP Server
- **AI agent integration**: `framepeek-cli mcp` runs a Model Context Protocol server on stdio
- Tools: `analyze_media` (structured results), `media_summary` (cheap metadata call), `inspect_container` (atom tree), `inspect_hls_ladder` (streaming QC findings)

### REST API
- **Embedded HTTP server** for remote analysis
- Start/stop from the Server tab in the app
- Job queue with progress tracking

## System Requirements

- **macOS**: 15.2 (Sequoia) or later
- **Xcode**: 16.2 or later (for building from source)

## Installation

### Download (recommended)

Grab the latest signed `.dmg` from the [Releases page](https://github.com/oscnord/FramePeek/releases/latest), open it, and drag **FramePeek** to `/Applications`. The CLI is published as a separate `framepeek-cli-<version>.tar.gz` on the same release.

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

# EBU R128 loudness
framepeek-cli video.mp4 --loudness --pretty

# Multiple files
framepeek-cli *.mp4 --info --parallel
```

### MCP Server (AI agents)

Two ways to connect:

```bash
# stdio: the client spawns the CLI itself
claude mcp add framepeek -- framepeek-cli mcp

# HTTP: connect to the running app (start the server in the Server tab)
claude mcp add --transport http framepeek http://127.0.0.1:8080/mcp
```

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "framepeek": { "command": "framepeek-cli", "args": ["mcp"] }
  }
}
```

Agents can then call `media_summary` for a quick look at any local file, `analyze_media` for full structured results (bitrate, GOP, loudness, …), `inspect_container` for the MP4/MOV atom tree, and `inspect_hls_ladder` to QC an HLS ladder by path or URL.

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
