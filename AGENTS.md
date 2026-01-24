# AGENTS.md - AI Agent Instructions for FramePeek

## Quick Reference

| Aspect | Details |
|--------|---------|
| **Language** | Swift 5.0+ |
| **UI Framework** | SwiftUI |
| **Platform** | macOS 15.2+ (Sequoia) |
| **Architecture** | MVVM with Swift Concurrency |
| **Dependencies** | Apple frameworks only |
| **Entry Point** | `FramePeek/FramePeekApp.swift` |

## Project Purpose

FramePeek is a professional macOS app for inspecting video/audio files. It provides metadata analysis, bitrate visualization, GOP structure analysis, keyframe detection, waveform visualization, and A/V sync analysis using AVFoundation and CoreMedia.

## Critical Rules

### DO
- Use **Swift Concurrency** (`async/await`, `@MainActor`) for all async work
- Mark ViewModels with `@MainActor` for thread safety
- Use `String(localized:)` for all user-facing strings
- Follow existing design patterns - check similar files first
- Prefer editing existing files over creating new ones

### DON'T
- Don't use GCD (`DispatchQueue`) - use Swift Concurrency
- Don't add external dependencies
- Don't use `print()` for production logging
- Don't swallow errors silently
- Don't commit without user approval

## Concurrency Pattern

```swift
@MainActor
class SomeViewModel: ObservableObject {
    @Published var data: [Item] = []
    
    func loadData() async {
        let result = await Task.detached(priority: .userInitiated) {
            return await someAsyncOperation()
        }.value
        self.data = result
    }
}
```

## Localization

```swift
Text("Settings")                                    // SwiftUI auto-localizes
Text(String(localized: "Settings"))                 // Explicit
.help(String(localized: "Open new tab"))            // Modifiers need explicit
```

## Build & Test

```bash
xcodebuild -project FramePeek/FramePeek.xcodeproj -scheme FramePeek build
xcodebuild -project FramePeek/FramePeek.xcodeproj -scheme FramePeek test
```

## Additional Resources

- [`instructions.md`](instructions.md) - Full documentation
- [`LOCALIZATION.md`](LOCALIZATION.md) - Localization guide
