//
//  AspectRatioUtils.swift
//  MediaInspector
//
//  Utilities for aspect ratio calculations.
//

import Foundation

// MARK: - Math Helpers

/// Calculates the greatest common divisor for aspect ratio simplification
func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
}

// MARK: - Aspect Ratio Calculation

/// Common aspect ratios for matching
private let commonAspectRatios: [(Double, String)] = [
    (16.0/9.0, "16:9"),
    (4.0/3.0, "4:3"),
    (21.0/9.0, "21:9"),
    (2.39, "2.39:1 (Scope)"),
    (2.35, "2.35:1 (Scope)"),
    (1.85, "1.85:1"),
    (1.78, "16:9"),
    (1.33, "4:3"),
    (1.0, "1:1"),
    (9.0/16.0, "9:16 (Vertical)"),
]

/// Calculates display aspect ratio from resolution and pixel aspect ratio
/// - Parameters:
///   - width: Coded width in pixels
///   - height: Coded height in pixels
///   - parH: Pixel aspect ratio horizontal spacing (default 1)
///   - parV: Pixel aspect ratio vertical spacing (default 1)
/// - Returns: Human-readable aspect ratio string
func calculateDisplayAspectRatio(width: Int, height: Int, parH: Int = 1, parV: Int = 1) -> String {
    guard width > 0, height > 0, parH > 0, parV > 0 else { return "N/A" }
    
    // Calculate display dimensions accounting for non-square pixels
    let displayWidth = width * parH
    let displayHeight = height * parV
    
    let divisor = gcd(displayWidth, displayHeight)
    let ratioW = displayWidth / divisor
    let ratioH = displayHeight / divisor
    
    // Calculate numeric ratio for comparison
    let ratio = Double(displayWidth) / Double(displayHeight)
    
    // Check against common aspect ratios
    for (targetRatio, name) in commonAspectRatios {
        if abs(ratio - targetRatio) < 0.02 {
            return name
        }
    }
    
    // Return simplified ratio if no common match
    return "\(ratioW):\(ratioH)"
}

/// Determines if the resolution is considered "vertical" (portrait)
func isVerticalResolution(width: Int, height: Int) -> Bool {
    height > width
}

/// Returns a descriptive resolution category
func resolutionCategory(width: Int, height: Int) -> String {
    let maxDim = max(width, height)
    
    switch maxDim {
    case 0..<720: return "SD"
    case 720..<1080: return "HD (720p)"
    case 1080..<1440: return "Full HD (1080p)"
    case 1440..<2160: return "QHD (1440p)"
    case 2160..<4320: return "4K UHD"
    case 4320...: return "8K UHD"
    default: return "Unknown"
    }
}
