//
//  ColorTheme.swift
//  Notchification
//
//  Color theme system for the notch indicator
//

import SwiftUI

/// Available color themes for the notch indicator
enum ColorTheme: String, CaseIterable, Identifiable {
    case `default` = "default"
    case monochrome = "monochrome"
    case ocean = "ocean"
    case sunset = "sunset"
    case forest = "forest"
    case neon = "neon"
    case pastel = "pastel"
    case noir = "noir"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .monochrome: return "Monochrome"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        case .neon: return "Neon"
        case .pastel: return "Pastel"
        case .noir: return "Noir"
        }
    }

    /// Returns the color for a process type in this theme
    func color(for processType: ProcessType) -> Color {
        switch self {
        case .default:
            return processType.color
        case .noir:
            return processType.color.toGrayscale()
        case .monochrome:
            return monochromeColors[processType.themeIndex % monochromeColors.count]
        case .ocean:
            return oceanColors[processType.themeIndex % oceanColors.count]
        case .sunset:
            return sunsetColors[processType.themeIndex % sunsetColors.count]
        case .forest:
            return forestColors[processType.themeIndex % forestColors.count]
        case .neon:
            return neonColors[processType.themeIndex % neonColors.count]
        case .pastel:
            return pastelColors[processType.themeIndex % pastelColors.count]
        }
    }

    /// Returns the wave color for a process type in this theme
    func waveColor(for processType: ProcessType) -> Color {
        switch self {
        case .default:
            return processType.waveColor
        case .noir:
            return processType.waveColor.toGrayscale()
        case .monochrome:
            return monochromeWaveColors[processType.themeIndex % monochromeWaveColors.count]
        case .ocean:
            return oceanWaveColors[processType.themeIndex % oceanWaveColors.count]
        case .sunset:
            return sunsetWaveColors[processType.themeIndex % sunsetWaveColors.count]
        case .forest:
            return forestWaveColors[processType.themeIndex % forestWaveColors.count]
        case .neon:
            return neonWaveColors[processType.themeIndex % neonWaveColors.count]
        case .pastel:
            return pastelWaveColors[processType.themeIndex % pastelWaveColors.count]
        }
    }

    /// Preview colors shown in the theme picker UI (5 representative colors)
    /// Uses processes with themeIndex 0-4 to show all unique theme colors
    var previewColors: [Color] {
        switch self {
        case .default:
            // Show the same processes used in theme preview (themeIndex 0-4)
            return [
                ProcessType.claudeCode.color,     // themeIndex 0
                ProcessType.xcode.color,          // themeIndex 1
                ProcessType.androidStudio.color,  // themeIndex 2
                ProcessType.finder.color,         // themeIndex 3
                ProcessType.opencode.color        // themeIndex 4
            ]
        case .noir:
            return [
                Color(white: 0.75),
                Color(white: 0.60),
                Color(white: 0.45),
                Color(white: 0.55),
                Color(white: 0.65)
            ]
        case .monochrome:
            return monochromeColors
        case .ocean:
            return oceanColors
        case .sunset:
            return sunsetColors
        case .forest:
            return forestColors
        case .neon:
            return neonColors
        case .pastel:
            return pastelColors
        }
    }

    // MARK: - Theme Color Palettes

    /// Monochrome - Shades of blue/purple
    private var monochromeColors: [Color] {
        [
            Color(hex: "#7DD3FC"),  // Light sky blue
            Color(hex: "#93C5FD"),  // Light blue
            Color(hex: "#A5B4FC"),  // Lavender blue
            Color(hex: "#818CF8"),  // Indigo
            Color(hex: "#6366F1")   // Deep indigo
        ]
    }

    private var monochromeWaveColors: [Color] {
        [
            Color(hex: "#BAE6FD"),
            Color(hex: "#BFDBFE"),
            Color(hex: "#C7D2FE"),
            Color(hex: "#A5B4FC"),
            Color(hex: "#818CF8")
        ]
    }

    /// Ocean - Cyan/aqua tones
    private var oceanColors: [Color] {
        [
            Color(hex: "#22D3EE"),  // Cyan
            Color(hex: "#67E8F9"),  // Light cyan
            Color(hex: "#A5F3FC"),  // Pale cyan
            Color(hex: "#7DD3FC"),  // Sky blue
            Color(hex: "#38BDF8")   // Light blue
        ]
    }

    private var oceanWaveColors: [Color] {
        [
            Color(hex: "#67E8F9"),
            Color(hex: "#A5F3FC"),
            Color(hex: "#CFFAFE"),
            Color(hex: "#BAE6FD"),
            Color(hex: "#7DD3FC")
        ]
    }

    /// Sunset - Warm orange/yellow/coral tones
    private var sunsetColors: [Color] {
        [
            Color(hex: "#FDBA74"),  // Light orange
            Color(hex: "#FB923C"),  // Orange
            Color(hex: "#F59E0B"),  // Amber
            Color(hex: "#EAB308"),  // Yellow
            Color(hex: "#F97316")   // Deep orange
        ]
    }

    private var sunsetWaveColors: [Color] {
        [
            Color(hex: "#FED7AA"),
            Color(hex: "#FDBA74"),
            Color(hex: "#FCD34D"),
            Color(hex: "#FDE047"),
            Color(hex: "#FDBA74")
        ]
    }

    /// Forest - Greens and earth tones
    private var forestColors: [Color] {
        [
            Color(hex: "#86EFAC"),  // Light green
            Color(hex: "#4ADE80"),  // Green
            Color(hex: "#A3A380"),  // Olive
            Color(hex: "#6B8E4E"),  // Forest green
            Color(hex: "#65A30D")   // Lime
        ]
    }

    private var forestWaveColors: [Color] {
        [
            Color(hex: "#BBF7D0"),
            Color(hex: "#86EFAC"),
            Color(hex: "#C4C4A4"),
            Color(hex: "#8BAF6E"),
            Color(hex: "#84CC16")
        ]
    }

    /// Neon - Bright vibrant colors
    private var neonColors: [Color] {
        [
            Color(hex: "#E879F9"),  // Fuchsia
            Color(hex: "#60A5FA"),  // Blue
            Color(hex: "#FB923C"),  // Orange
            Color(hex: "#4ADE80"),  // Green
            Color(hex: "#F43F5E")   // Rose
        ]
    }

    private var neonWaveColors: [Color] {
        [
            Color(hex: "#F0ABFC"),
            Color(hex: "#93C5FD"),
            Color(hex: "#FDBA74"),
            Color(hex: "#86EFAC"),
            Color(hex: "#FB7185")
        ]
    }

    /// Pastel - Soft muted colors
    private var pastelColors: [Color] {
        [
            Color(hex: "#C4B5FD"),  // Lavender
            Color(hex: "#FDE68A"),  // Cream/yellow
            Color(hex: "#A7F3D0"),  // Mint
            Color(hex: "#FBCFE8"),  // Pink
            Color(hex: "#FCA5A5")   // Salmon
        ]
    }

    private var pastelWaveColors: [Color] {
        [
            Color(hex: "#DDD6FE"),
            Color(hex: "#FEF08A"),
            Color(hex: "#D1FAE5"),
            Color(hex: "#FCE7F3"),
            Color(hex: "#FECACA")
        ]
    }
}

// MARK: - ProcessType Extension for Theme Index

extension ProcessType {
    /// Stable index for theme color assignment
    /// Uses a deterministic mapping based on process type to ensure consistent colors
    var themeIndex: Int {
        switch self {
        case .claudeCode: return 0
        case .claudeApp: return 0
        case .xcode: return 1
        case .androidStudio: return 2
        case .finder: return 3
        case .opencode: return 4
        case .codex: return 0
        case .dropbox: return 1
        case .googleDrive: return 2
        case .oneDrive: return 3
        case .icloud: return 4
        case .installer: return 0
        case .appStore: return 1
        case .automator: return 2
        case .scriptEditor: return 3
        case .downloads: return 4
        case .davinciResolve: return 0
        case .teams: return 1
        case .calendar: return 2
        case .preview: return 3
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "#FF5733" or "FF5733")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
