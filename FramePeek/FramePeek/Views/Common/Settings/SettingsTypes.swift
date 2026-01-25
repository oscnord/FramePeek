import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SamplingModeSetting: String, CaseIterable, Identifiable, Codable {
    case auto
    case interval
    case everyFrame

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Automatic")
        case .interval: return String(localized: "Fixed Interval")
        case .everyFrame: return String(localized: "Every Frame")
        }
    }
}

enum FileOpeningBehavior: String, CaseIterable, Identifiable, Codable {
    case prompt
    case newTab
    case currentTab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prompt: return String(localized: "Prompt")
        case .newTab: return String(localized: "Always Open in New Tab")
        case .currentTab: return String(localized: "Always Overwrite Current Tab")
        }
    }
}

enum ThumbnailSize: String, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }

    var cgSize: CGSize {
        switch self {
        case .small: return CGSize(width: 128, height: 80)
        case .medium: return CGSize(width: 192, height: 120)
        case .large: return CGSize(width: 256, height: 160)
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case analysis
    case playbackDisplay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return String(localized: "General")
        case .analysis: return String(localized: "Analysis")
        case .playbackDisplay: return String(localized: "Playback & Display")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .analysis: return "chart.line.uptrend.xyaxis"
        case .playbackDisplay: return "play.display"
        }
    }
}
