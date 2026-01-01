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
        case .claude: return Color(red: 0.91, green: 0.45, blue: 0.32) // Orange-red
        case .xcode: return Color(red: 0.95, green: 0.77, blue: 0.29) // Yellow
        case .androidStudio: return Color(red: 0.29, green: 0.56, blue: 0.31) // Green
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
