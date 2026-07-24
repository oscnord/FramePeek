# FramePeek – Agent and Contributor Guide

A concise guide for AI agents and human contributors to understand, navigate, and extend the FramePeek codebase. For quick-reference rules, see [AGENTS.md](AGENTS.md).

## What FramePeek does

FramePeek is a macOS SwiftUI application that inspects local media files using AVFoundation and CoreMedia. All media work uses Apple frameworks (no FFmpeg); the only third-party dependency is Hummingbird, which powers the embedded HTTP server:

- Video metadata (container, codec, resolution, frame rate, HDR/color info, PAR/DAR, bitrate)
- Audio track details (codec, channels, sample rate, bitrate, language) and per-track waveforms
- Frame-by-frame bitrate analysis with interactive charts and timeline zoom
- GOP structure analysis (I/P/B frame types, GOP heatmap, per-frame details)
- Keyframe detection and thumbnail strip
- Color analysis (vectorscope, waveform scope, RGB histogram, CCT, brightness) and Dolby Vision details
- A/V sync analysis
- EBU R128 loudness (integrated LUFS, true peak, loudness range, short-term chart)
- HLS ladder inspection (RFC 8216 manifest parsing, declared vs measured bitrates, keyframe alignment, QC findings)
- Container/atom inspector for MP4/MOV
- Embedded REST API server with job queue and webhooks
- CLI tool (`framepeek-cli`) for batch analysis, plus an MCP server (`framepeek-cli mcp`) exposing analysis tools to AI agents over stdio

## Targets

| Target | Purpose |
|--------|---------|
| `FramePeek` | The macOS app, GitHub distribution channel (includes Sparkle auto-updates) |
| `FramePeek-AppStore` | Same app sources for App Store/TestFlight: no Sparkle, updates via the App Store |
| `FramePeekCore` | Shared framework: models, analysis engine, JSON/CSV exporters |
| `FramePeekCLI` | Command-line tool built on FramePeekCore |
| `FramePeekTests` / `FramePeekCoreTests` / `FramePeekUITests` | Test bundles |

### Distribution channels

- **GitHub** (`FramePeek` scheme): Developer ID signed DMG from `release.yml`. Sparkle 2 provides auto-updates; the `SPARKLE_UPDATES` compilation condition gates all updater code, and the appcast is generated per release and attached as a release asset (feed URL: `releases/latest/download/appcast.xml`).
- **App Store / TestFlight** (`FramePeek-AppStore` scheme): identical sources, same bundle ID, but Sparkle is neither linked nor compiled in - always archive TestFlight/App Store builds from this scheme.

## Project structure (directory level)

```text
FramePeek/
├── FramePeekApp.swift       # @main entry point
├── FramePeek.swift          # Main window, drag-and-drop, tab hosting
├── fileUtils.swift          # NSOpenPanel helper
├── Models/                  # App-side data models (BitrateSample, MediaModels, …)
├── ViewModels/              # @MainActor @Observable ViewModels
│                            #   MediaInspectorViewModel + feature extensions
│                            #   (+FileHandling, +Sampling, +Thumbnails, +GOP,
│                            #    +Waveforms, +ColorAnalysis, +Sync, +Container)
│                            #   TabManager, PlayerViewModelManager, ServerViewModel
├── Server/                  # Embedded HTTP server: ServerManager, JobQueue,
│                            #   AnalysisJob, WebhookService, RequestLog
├── Views/
│   ├── Chart/               # Bitrate/GOP/waveform/color charts and scopes
│   ├── Common/              # Shared components, TimelineView, Settings/
│   ├── Inspector/           # Metadata inspector panel
│   ├── Keyframes/           # Keyframe thumbnail strip
│   ├── Player/              # Video player with stats overlay
│   └── Server/              # Server tab UI
└── Utils/
    ├── Analysis/            # GOP, color, sync, waveform, frame-detail analyzers
    ├── Cache/               # CacheManager (disk cache for analysis results)
    ├── Extraction/          # Bitrate extractors (cursor/reader/TS/fMP4) + format detection
    ├── Formatting/          # FormatUtils, ColorUtils, DesignSystem, …
    ├── Logging/             # Unified os.Logger wrapper
    ├── Media/               # VideoInfoLoader/AudioInfoLoader (AVAsset metadata)
    └── Parsing/             # Container/bitstream parsers (atoms, VUI, AV1, frame types)

FramePeekCore/
├── Analysis/                # AnalysisEngine (shared with CLI/server)
├── Models/                  # Shared models (GOP, color, container, waveform, …)
└── Export/                  # JSONExporter, CSVExporter, AnalysisResult

FramePeekCLI/
└── CLI/                     # AnalyzeCommand, output formatting, progress
```

## Key flows

### Opening a file (app)

1. URL arrives via NSOpenPanel, drag-and-drop, or a new tab.
2. `MediaInspectorViewModel` (+FileHandling) creates an `AVURLAsset` and kicks off independent tasks: metadata (`VideoInfoLoader.getExtendedInfo`), bitrate extraction, keyframes, and (on demand) GOP/waveform/color/sync/container analysis.
3. Each analysis stores its `Task` handle on the ViewModel; loading a new file cancels in-flight tasks.

### Bitrate extraction

`extractBitratesFast(asset:options:)` returns an `AsyncStream<FrameAnalysisUpdate>` for progressive UI updates. It routes on `detectContainerFormat`:

- Fragmented MP4 / CMAF → `FragmentedMP4Extractor`
- MPEG-TS → `TSBitrateExtractor` (accounts for packet overhead)
- Otherwise → `AVSampleCursor` fast path, falling back to `AVAssetReader` (the reader path is also used when the user prefers accuracy)

Sampling behavior is configured via `FrameSamplingOptions` (mode auto/everyFrame/interval, `maxSamples`, batch size). Charts apply LTTB downsampling (`BitrateChartDownsampling.swift`) before rendering.

### Keyframes and GOP

- Keyframe detection inspects sample attachment flags (no decoding) via `KeyframeMarker`/`SyncSampleParser`; thumbnails are generated asynchronously afterwards.
- `GOPAnalyzer` builds GOP structures; frame types come from `FrameTypeParser` (H.264/HEVC NAL inspection). Per-GOP frame details load on demand and are LRU-cached.

### Server

`ServerManager` runs a Network.framework HTTP listener. Requests enqueue `AnalysisJob`s on `JobQueue`; results reuse `FramePeekCore.AnalysisEngine` and can trigger webhooks (`WebhookService`). The Server tab in the app controls lifecycle and shows request logs.

### Streaming (HLS)

`analyzeHLSLadder` (`Utils/Analysis/HLSLadderAnalyzer.swift`) parses manifests with `HLSPlaylistParser` (`Utils/Parsing/`), samples segments per variant in a bounded task group, and returns `StreamingLadderAnalysis` with severity-graded findings. The Streaming sidebar tab drives it; local playlists need folder-scoped open panel access (a file-scoped sandbox grant does not cover sibling segments).

### MCP server

The protocol layer lives in Core (`Utils/MCP/MCPServer.swift` + `MCPTools.swift`, tested in-process by `MCPServerTests`) and is transport-agnostic. Two transports expose it: `framepeek-cli mcp` (newline-delimited JSON-RPC 2.0 on stdio) and the app's HTTP server at `POST /mcp` (Streamable HTTP; requests → 200 + JSON, notifications → 202, GET → 405 since there is no SSE stream). Tools: `analyze_media`, `media_summary`, `inspect_container`, `inspect_hls_ladder`. Sandbox caveat: over HTTP (and the REST `/analyze/path`), path-based tools only reach files the sandboxed app can read (Downloads, previously opened files); the stdio CLI has no sandbox.

### Caching

`CacheManager` persists expensive analysis results (GOP, waveforms) to disk keyed by file identity, so reopening a file is fast.

## Conventions

- **Concurrency**: Swift Concurrency only (`async`/`await`, actors). ViewModels are `@MainActor @Observable`. Heavy work runs via `Task.detached(priority: .userInitiated)`; long loops check `Task.isCancelled`. No GCD.
- **Streaming**: analyses that can report progressively use `AsyncStream`.
- **Logging**: use the wrapper in `Utils/Logging/Logger.swift` (os.Logger categories). No `print()`.
- **Design**: use `DesignSystem` tokens for spacing, padding, colors, and corner radius.
- **Localization**: all user-facing strings are localized via `Localizable.xcstrings`. String literals in `Text()` auto-localize; computed strings and modifiers like `.help()` need `String(localized:)`.
- **Error handling**: don't swallow errors silently; missing metadata falls back to `nil`/"N/A"/"Unknown". Guard divisions and dimensions against zero.
- **Comments**: almost none — code should be self-explanatory; rationale goes in commit messages.
- **Naming**: `load*`, `get*`, `parse*`, `extract*`, `detect*` for the respective operation kinds.
- **Parsing helpers are pure** and unit-testable; I/O stays at the orchestration layer.

## Build & test

```bash
xcodebuild -project FramePeek/FramePeek.xcodeproj -scheme FramePeek build
xcodebuild -project FramePeek/FramePeek.xcodeproj -scheme FramePeek -destination 'platform=macOS' test
```

Unit tests live in `FramePeekTests/` and `FramePeekCoreTests/`, UI tests in `FramePeekUITests/`. The `bruno/` folder contains a Bruno collection for exercising the REST API.

## Extending

- **New codec parsing**: add a parser for the codec's configuration atom (see `Utils/Parsing/AV1Parser.swift` as reference) and a FourCC → name mapping in `Utils/Formatting/FormatUtils.swift`.
- **New container format**: extend `Utils/Extraction/FormatDetector.swift` and, if needed, add a specialized extractor next to the existing ones.
- **HDR detection rules**: extend `detectHDRFormat(...)` in `Utils/Formatting/ColorUtils.swift`.
- **New REST endpoints**: route in `Server/ServerManager.swift`, document in `Views/Server/APIDocumentationView.swift`, and add a Bruno request under `bruno/`.
- **New analysis**: follow the existing pattern — analyzer in `Utils/Analysis/`, results model in `FramePeekCore/Models/`, ViewModel extension owning the `Task`, chart view under `Views/Chart/`.
