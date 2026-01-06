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
    case codex = "codex"
    case dropbox = "dropbox"
    case googleDrive = "googledrive"
    case oneDrive = "onedrive"
    case icloud = "icloud"
    case installer = "installer"
    case appStore = "appstore"
    case automator = "automator"
    case scriptEditor = "scripteditor"
    case downloads = "downloads"
    case davinciResolve = "davinciresolve"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .xcode: return "Xcode"
        case .androidStudio: return "Android Studio"
        case .finder: return "Finder"
        case .opencode: return "Opencode"
        case .codex: return "Codex"
        case .dropbox: return "Dropbox"
        case .googleDrive: return "Google Drive"
        case .oneDrive: return "OneDrive"
        case .icloud: return "iCloud"
        case .installer: return "Installer"
        case .appStore: return "App Store"
        case .automator: return "Automator"
        case .scriptEditor: return "Script Editor"
        case .downloads: return "Downloads"
        case .davinciResolve: return "DaVinci Resolve"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757 Claude orange
        case .xcode: return Color(red: 0.08, green: 0.49, blue: 0.98) // #147EFB Xcode blue
        case .androidStudio: return Color(red: 0.17, green: 0.63, blue: 0.38) // Darker Android green
        case .finder: return Color(red: 0.902, green: 0.910, blue: 0.937) // #e6e8ef Finder gray
        case .opencode: return Color(red: 0.847, green: 0.847, blue: 0.847) // #D8D8D8 Opencode gray
        case .codex: return Color(red: 0.976, green: 0.976, blue: 0.976) // #F9F9F9 OpenAI light gray
        case .dropbox: return Color(red: 0.0, green: 0.38, blue: 1.0) // #0061FF Dropbox blue
        case .googleDrive: return Color(red: 0.26, green: 0.52, blue: 0.96) // #4285F4 Google blue
        case .oneDrive: return Color(red: 0.0, green: 0.47, blue: 0.83) // #0078D4 Microsoft blue
        case .icloud: return Color(red: 0.2, green: 0.6, blue: 1.0) // iCloud blue
        case .installer: return Color(red: 0.6, green: 0.4, blue: 0.8) // Purple for system installer
        case .appStore: return Color(red: 0.0, green: 0.48, blue: 1.0) // #007AFF App Store blue
        case .automator: return Color(red: 0.75, green: 0.75, blue: 0.78) // Light gray like Automator robot
        case .scriptEditor: return .white // White for Script Editor
        case .downloads: return Color(red: 0.757, green: 0.765, blue: 1.0) // #c1c3ff Light purple
        case .davinciResolve: return Color(red: 0.176, green: 0.294, blue: 0.416) // #2d4b6a DaVinci blue
        }
    }

    var waveColor: Color {
        switch self {
        case .claude: return Color(red: 0.95, green: 0.60, blue: 0.48) // Lighter orange
        case .xcode: return Color(red: 0.30, green: 0.65, blue: 1.0) // Lighter blue
        case .androidStudio: return Color(red: 0.30, green: 0.85, blue: 0.55) // Brighter green
        case .finder: return .white // White wave on gray base
        case .opencode: return .white // White wave on gray base
        case .codex: return .white // White wave on light gray base
        case .dropbox: return Color(red: 0.4, green: 0.6, blue: 1.0) // Lighter Dropbox blue
        case .googleDrive: return Color(red: 0.5, green: 0.7, blue: 1.0) // Lighter Google blue
        case .oneDrive: return Color(red: 0.4, green: 0.65, blue: 0.95) // Lighter Microsoft blue
        case .icloud: return Color(red: 0.5, green: 0.8, blue: 1.0) // Lighter iCloud blue
        case .installer: return Color(red: 0.75, green: 0.55, blue: 0.9) // Lighter purple
        case .appStore: return Color(red: 0.4, green: 0.7, blue: 1.0) // Lighter App Store blue
        case .automator: return .white // White wave on gray base
        case .scriptEditor: return Color(red: 0.85, green: 0.85, blue: 0.85) // Light gray wave on white
        case .downloads: return Color(red: 0.85, green: 0.86, blue: 1.0) // Lighter purple
        case .davinciResolve: return Color(red: 0.35, green: 0.5, blue: 0.7) // Lighter DaVinci blue
        }
    }

    var grayscalePattern: GrayscalePattern {
        switch self {
        case .claude: return .solid
        case .xcode: return .horizontalStripes
        case .androidStudio: return .dots
        case .finder: return .diagonalStripes
        case .opencode: return .solid
        case .codex: return .solid
        case .dropbox: return .solid
        case .googleDrive: return .solid
        case .oneDrive: return .solid
        case .icloud: return .solid
        case .installer: return .solid
        case .appStore: return .solid
        case .automator: return .solid
        case .scriptEditor: return .solid
        case .downloads: return .solid
        case .davinciResolve: return .solid
        }
    }
}

enum GrayscalePattern {
    case solid
    case horizontalStripes
    case dots
    case diagonalStripes
}
