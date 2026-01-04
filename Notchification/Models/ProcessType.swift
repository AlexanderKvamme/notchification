//
//  ProcessType.swift
//  Notchification
//

import SwiftUI

enum ProcessType: String, CaseIterable, Identifiable {
    case claude = "claude"
    case xcode = "xcode"
    case androidStudio = "android"
    case finder = "finder"
    case opencode = "opencode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .xcode: return "Xcode"
        case .androidStudio: return "Android Studio"
        case .finder: return "Finder"
        case .opencode: return "Opencode"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757 Claude orange
        case .xcode: return Color(red: 0.08, green: 0.49, blue: 0.98) // #147EFB Xcode blue
        case .androidStudio: return Color(red: 0.17, green: 0.63, blue: 0.38) // Darker Android green
        case .finder: return Color(red: 0.902, green: 0.910, blue: 0.937) // #e6e8ef Finder gray
        case .opencode: return Color(red: 0.847, green: 0.847, blue: 0.847) // #D8D8D8 Opencode gray
        }
    }

    var waveColor: Color {
        switch self {
        case .claude: return Color(red: 0.95, green: 0.60, blue: 0.48) // Lighter orange
        case .xcode: return Color(red: 0.30, green: 0.65, blue: 1.0) // Lighter blue
        case .androidStudio: return Color(red: 0.30, green: 0.85, blue: 0.55) // Brighter green
        case .finder: return .white // White wave on gray base
        case .opencode: return .white // White wave on gray base
        }
    }

    var grayscalePattern: GrayscalePattern {
        switch self {
        case .claude: return .solid
        case .xcode: return .horizontalStripes
        case .androidStudio: return .dots
        case .finder: return .diagonalStripes
        case .opencode: return .solid
        }
    }
}

enum GrayscalePattern {
    case solid
    case horizontalStripes
    case dots
    case diagonalStripes
}
