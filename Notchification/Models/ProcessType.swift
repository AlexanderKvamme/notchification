//
//  ProcessType.swift
//  Notchification
//

import SwiftUI

enum ProcessType: String, CaseIterable, Identifiable {
    case claude = "claude"
    case xcode = "xcode"
    case androidStudio = "android"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .xcode: return "Xcode"
        case .androidStudio: return "Android Studio"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757 Claude orange
        case .xcode: return Color(red: 0.08, green: 0.49, blue: 0.98) // #147EFB Xcode blue
        case .androidStudio: return Color(red: 0.17, green: 0.63, blue: 0.38) // Darker Android green
        }
    }

    var waveColor: Color {
        switch self {
        case .claude: return Color(red: 0.95, green: 0.60, blue: 0.48) // Lighter orange
        case .xcode: return Color(red: 0.30, green: 0.65, blue: 1.0) // Lighter blue
        case .androidStudio: return Color(red: 0.30, green: 0.85, blue: 0.55) // Brighter green
        }
    }

    var grayscalePattern: GrayscalePattern {
        switch self {
        case .claude: return .solid
        case .xcode: return .horizontalStripes
        case .androidStudio: return .dots
        }
    }
}

enum GrayscalePattern {
    case solid
    case horizontalStripes
    case dots
    case diagonalStripes
}
