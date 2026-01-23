# AGENTS.md - AI Agent Instructions for FramePeek

This document provides essential context for AI coding agents working on the FramePeek codebase. For comprehensive documentation, see [`instructions.md`](instructions.md).

## Quick Reference

| Aspect | Details |
|--------|---------|
| **Language** | Swift 5.0+ |
| **UI Framework** | SwiftUI |
| **Platform** | macOS 15.2+ (Sequoia) |
| **Architecture** | MVVM with Swift Concurrency |
| **Dependencies** | Apple frameworks only (no external deps) |
| **Entry Point** | `FramePeek/FramePeekApp.swift` |

## Project Purpose

FramePeek is a professional macOS application for inspecting video and audio files. It extracts comprehensive metadata using AVFoundation and CoreMedia, providing:

- Video/audio metadata analysis
- Frame-by-frame bitrate visualization with interactive charts
- GOP (Group of Pictures) structure analysis
- Keyframe detection with thumbnails
- Audio waveform visualization
- Audio/video sync analysis

## Directory Structure

```
FramePeek/
├── FramePeekApp.swift              # @main entry point
├── FramePeek.swift                 # Main window with NavigationSplitView
├── fileUtils.swift                 # NSOpenPanel helper
│
├── Models/                         # Data models
│   ├── BitrateSample.swift         # Chart data point
│   ├── MediaModels.swift           # ExtendedVideoInfo, AudioTrackInfo
│   ├── GOPModels.swift             # GOP analysis models
│   └── WaveformSample.swift        # Audio waveform data
│
├── ViewModels/                     # MVVM ViewModels
│   ├── MediaInspectorViewModel.swift           # Main ViewModel
│   ├── MediaInspectorViewModel+FileHandling.swift
│   ├── MediaInspectorViewModel+Sampling.swift
│   ├── MediaInspectorViewModel+Thumbnails.swift
│   ├── MediaInspectorViewModel+GOP.swift
│   ├── MediaInspectorViewModel+Waveforms.swift
│   ├── MediaInspectorViewModel+Sync.swift
│   ├── MediaInspectorViewModel+ColorAnalysis.swift
│   ├── TabManager.swift            # Multi-tab management
│   └── PlayerViewModelManager.swift
│
├── Views/                          # SwiftUI Views
│   ├── Chart/                      # Bitrate/GOP/waveform charts
│   ├── Common/                     # Shared components
│   ├── Inspector/                  # Metadata inspector panel
│   ├── Keyframes/                  # Keyframe thumbnails
│   └── Player/                     # Video player
│
└── Utils/                          # Core utilities
    ├── Analysis/                   # Frame/bitrate/GOP analysis
    ├── Extraction/                 # Bitrate extraction (MP4, TS, fMP4)
    ├── Formatting/                 # Display formatting, color utils
    ├── Media/                      # VideoInfoLoader, AudioInfoLoader
    └── Parsing/                    # AV1Parser, VUIParser, KeyframeMarker
```

## Key Files

| File | Purpose |
|------|---------|
| `ViewModels/MediaInspectorViewModel.swift` | Central state manager with `@Published` properties |
| `Utils/Media/VideoInfoLoader.swift` | Metadata extraction orchestrator |
| `Utils/Extraction/FastBitrateExtractor.swift` | Bitrate analysis with `AsyncStream` |
| `Models/MediaModels.swift` | Core data structures (`ExtendedVideoInfo`, etc.) |
| `Utils/Parsing/KeyframeMarker.swift` | I-frame detection without decoding |

## Critical Rules

### DO

- Use **Swift Concurrency** (`async/await`, `@MainActor`) for all async work
- Mark ViewModels with `@MainActor` for thread safety
- Use `Task.detached` with `.userInitiated` priority for heavy work
- Use `String(localized:)` for all user-facing strings
- Keep parsing helpers **pure and testable** - isolate I/O at orchestration layer
- Follow naming conventions: `load*`, `get*`, `parse*`, `extract*`, `detect*`
- Use **existing design patterns** - check similar files before adding new code
- Prefer **editing existing files** over creating new ones

### DON'T

- Don't use GCD (`DispatchQueue`) for new code - use Swift Concurrency
- Don't use Combine unless surrounding code already uses it
- Don't add external dependencies - use Apple frameworks only
- Don't add unnecessary comments - code should be self-explanatory
- Don't use `print()` for error logging in production code
- Don't swallow errors silently - handle or propagate them appropriately
- Don't commit without user approval

## Concurrency Patterns

```swift
// ViewModel updates (correct)
@MainActor
class SomeViewModel: ObservableObject {
    @Published var data: [Item] = []
    
    func loadData() async {
        let result = await Task.detached(priority: .userInitiated) {
            // Heavy work here
            return await someAsyncOperation()
        }.value
        self.data = result  // Safe - we're @MainActor
    }
}

// Progressive updates with AsyncStream
for await update in extractBitratesFast(asset: asset, options: options) {
    samples.append(contentsOf: update.appendedSamples)
    if update.isFinished { break }
}
```

## Localization

All user-facing strings must be localized:

```swift
// Text views - automatic localization
Text("Settings")

// Computed strings - explicit localization
Text(String(localized: "Settings"))
FeatureRow(title: String(localized: "Bitrate Analysis"))

// Help modifiers - always explicit
.help(String(localized: "Open new tab"))

// Format strings
Text(String(format: String(localized: "Version %@"), version))
```

## Testing

- **Unit tests**: `FramePeekTests/` - currently minimal, needs expansion
- **UI tests**: `FramePeekUITests/` - launch tests only
- Pure parsing functions should be unit tested
- Use sample media files with known properties for integration tests
- Run tests: `Cmd+U` in Xcode or `xcodebuild test`

## Common Tasks

### Adding a New Metadata Field

1. Add property to `ExtendedVideoInfo` in `Models/MediaModels.swift`
2. Extract value in appropriate `VideoInfoLoader+*.swift` extension
3. Display in `Views/Inspector/InfoInspectorView/`
4. Add localized string if user-facing

### Adding a New Analysis Type

1. Create analyzer in `Utils/Analysis/` (see `GOPAnalyzer.swift` as reference)
2. Add `@Published` properties to `MediaInspectorViewModel`
3. Create ViewModel extension `MediaInspectorViewModel+YourAnalysis.swift`
4. Create view in `Views/Chart/`
5. Integrate into main view in `FramePeek.swift`

### Adding a New Codec

1. Add FourCC mapping in `Utils/Formatting/FormatUtils.swift` (`videoCodecMappings`)
2. Add parser in `Utils/Parsing/` if config atom parsing needed
3. Update `VideoInfoLoader+Codec.swift` to extract codec-specific info
4. See `AV1Parser.swift` for reference implementation

## Known Technical Debt

| Issue | Location | Priority |
|-------|----------|----------|
| Empty test suite | `FramePeekTests/` | High |
| Unused singleton | `Services/FileCountTracker.swift` | Medium |
| 1000+ line file | `Views/Common/TimelineView.swift` | Medium |
| Duplicated interpolation logic | `Views/Player/VideoPlayerView.swift:346-432` | Medium |
| Mixed async patterns | Throughout (DispatchQueue vs @MainActor) | Medium |
| Empty catch blocks | Multiple files | Medium |
| Inconsistent file naming | `fileUtils.swift` (should be PascalCase) | Low |

## Error Handling Guidelines

```swift
// Preferred: Explicit error handling
do {
    let result = try await someOperation()
    // Use result
} catch {
    // Log appropriately or propagate
    logger.error("Operation failed: \(error)")
}

// Acceptable: Optional try with fallback
let result = try? await someOperation() ?? defaultValue

// AVOID: Silent error swallowing
do {
    try await someOperation()
} catch {
    // Empty - BAD!
}
```

## Build & Run

```bash
# Build from command line
xcodebuild -project FramePeek/FramePeek.xcodeproj -scheme FramePeek build

# Run tests
xcodebuild -project FramePeek/FramePeek.xcodeproj -scheme FramePeek test

# Or use Xcode: Cmd+B to build, Cmd+R to run, Cmd+U to test
```

## Additional Resources

- **Full documentation**: [`instructions.md`](instructions.md) - 600+ lines of detailed docs
- **Cursor AI context**: [`.cursorrules`](.cursorrules)
- **GitHub Copilot context**: [`.github/instructions/general-instructions.md`](.github/instructions/general-instructions.md)
- **Localization guide**: [`LOCALIZATION.md`](LOCALIZATION.md)
