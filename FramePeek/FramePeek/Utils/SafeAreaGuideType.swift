import SwiftUI

/// Defines the types of safe area guides available in the video player
enum SafeAreaGuideType: String, CaseIterable, Identifiable, Codable {
    // Broadcast Safe
    case titleSafe
    case actionSafe
    
    // Aspect Ratios - Cinema
    case aspect2_39  // 2.39:1 Cinemascope
    case aspect2_35  // 2.35:1 Anamorphic
    case aspect1_85  // 1.85:1 Flat
    
    // Aspect Ratios - TV/Standard
    case aspect16_9  // 1.78:1 (16:9)
    case aspect4_3   // 1.33:1 (4:3)
    
    // Social/Vertical
    case aspect9_16  // 9:16 Vertical
    case aspect1_1   // 1:1 Square
    case aspect4_5   // 4:5 Portrait
    
    // Utility
    case centerCrosshair
    
    var id: String { rawValue }
    
    /// Display name for the guide type
    var displayName: String {
        switch self {
        case .titleSafe:
            return String(localized: "Title Safe (90%)")
        case .actionSafe:
            return String(localized: "Action Safe (95%)")
        case .aspect2_39:
            return String(localized: "2.39:1 Cinemascope")
        case .aspect2_35:
            return String(localized: "2.35:1 Anamorphic")
        case .aspect1_85:
            return String(localized: "1.85:1 Flat")
        case .aspect16_9:
            return String(localized: "16:9 (1.78:1)")
        case .aspect4_3:
            return String(localized: "4:3 (1.33:1)")
        case .aspect9_16:
            return String(localized: "9:16 Vertical")
        case .aspect1_1:
            return String(localized: "1:1 Square")
        case .aspect4_5:
            return String(localized: "4:5 Portrait")
        case .centerCrosshair:
            return String(localized: "Center Crosshair")
        }
    }
    
    /// Short label for display on the guide overlay
    var shortLabel: String {
        switch self {
        case .titleSafe:
            return "Title Safe"
        case .actionSafe:
            return "Action Safe"
        case .aspect2_39:
            return "2.39:1"
        case .aspect2_35:
            return "2.35:1"
        case .aspect1_85:
            return "1.85:1"
        case .aspect16_9:
            return "16:9"
        case .aspect4_3:
            return "4:3"
        case .aspect9_16:
            return "9:16"
        case .aspect1_1:
            return "1:1"
        case .aspect4_5:
            return "4:5"
        case .centerCrosshair:
            return ""
        }
    }
    
    /// The aspect ratio for aspect-based guides (width / height)
    var aspectRatio: CGFloat? {
        switch self {
        case .aspect2_39:
            return 2.39
        case .aspect2_35:
            return 2.35
        case .aspect1_85:
            return 1.85
        case .aspect16_9:
            return 16.0 / 9.0
        case .aspect4_3:
            return 4.0 / 3.0
        case .aspect9_16:
            return 9.0 / 16.0
        case .aspect1_1:
            return 1.0
        case .aspect4_5:
            return 4.0 / 5.0
        default:
            return nil
        }
    }
    
    /// The inset percentage for broadcast safe guides (0.0 to 1.0)
    var safeAreaInset: CGFloat? {
        switch self {
        case .titleSafe:
            return 0.10  // 10% inset = 90% visible
        case .actionSafe:
            return 0.05  // 5% inset = 95% visible
        default:
            return nil
        }
    }
    
    /// Whether this guide is a broadcast safe type
    var isBroadcastSafe: Bool {
        switch self {
        case .titleSafe, .actionSafe:
            return true
        default:
            return false
        }
    }
    
    /// Whether this guide is an aspect ratio type
    var isAspectRatio: Bool {
        aspectRatio != nil
    }
    
    /// Category for grouping in UI
    var category: SafeAreaGuideCategory {
        switch self {
        case .titleSafe, .actionSafe:
            return .broadcastSafe
        case .aspect2_39, .aspect2_35, .aspect1_85:
            return .cinema
        case .aspect16_9, .aspect4_3:
            return .standard
        case .aspect9_16, .aspect1_1, .aspect4_5:
            return .social
        case .centerCrosshair:
            return .utility
        }
    }
    
    /// All guides grouped by category
    static var groupedByCategory: [(category: SafeAreaGuideCategory, guides: [SafeAreaGuideType])] {
        SafeAreaGuideCategory.allCases.map { category in
            (category, allCases.filter { $0.category == category })
        }
    }
}

/// Categories for grouping safe area guide types
enum SafeAreaGuideCategory: String, CaseIterable {
    case broadcastSafe
    case cinema
    case standard
    case social
    case utility
    
    var displayName: String {
        switch self {
        case .broadcastSafe:
            return String(localized: "Broadcast Safe")
        case .cinema:
            return String(localized: "Cinema")
        case .standard:
            return String(localized: "Standard")
        case .social:
            return String(localized: "Social / Vertical")
        case .utility:
            return String(localized: "Utility")
        }
    }
}

// MARK: - Set Serialization for AppStorage

extension Set where Element == SafeAreaGuideType {
    /// Converts the set to a comma-separated string for AppStorage
    var storageString: String {
        map { $0.rawValue }.sorted().joined(separator: ",")
    }
    
    /// Creates a set from a comma-separated storage string
    init(storageString: String) {
        if storageString.isEmpty {
            self = []
        } else {
            self = Set(
                storageString
                    .split(separator: ",")
                    .compactMap { SafeAreaGuideType(rawValue: String($0)) }
            )
        }
    }
}
