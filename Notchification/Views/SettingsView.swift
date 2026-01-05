//
//  SettingsView.swift
//  Notchification
//
//  Settings window with tabbed interface
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem {
                    Label("Display", systemImage: "display")
                }

            DetectionSettingsTab()
                .tabItem {
                    Label("Detection", systemImage: "eye")
                }

            ThresholdsSettingsTab()
                .tabItem {
                    Label("Thresholds", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - Display Tab

struct DisplaySettingsTab: View {
    @ObservedObject var styleSettings = StyleSettings.shared
    @State private var availableScreens: [NSScreen] = NSScreen.screens

    var body: some View {
        Form {
            Section {
                if availableScreens.count > 1 {
                    Picker("Screen:", selection: $styleSettings.selectedScreenIndex) {
                        Text("Main Screen").tag(-1)
                        ForEach(Array(availableScreens.enumerated()), id: \.offset) { index, screen in
                            Text(screenName(for: screen, at: index)).tag(index)
                        }
                    }
                    Text("Select which screen to show the notch indicator on")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Screen: Built-in Display")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Toggle("Minimal Style", isOn: $styleSettings.minimalStyle)
                Text("Shows only a colored border around the notch (no icons or progress bars)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    func screenName(for screen: NSScreen, at index: Int) -> String {
        let isMain = screen == NSScreen.main
        let hasNotch = NotchInfo.forScreen(screen).hasNotch
        let name = screen.localizedName
        var suffix = ""
        if isMain { suffix += " (Main)" }
        if hasNotch { suffix += " - Has Notch" }
        return name + suffix
    }
}

// MARK: - Detection Tab

struct DetectionSettingsTab: View {
    @ObservedObject var debugSettings = DebugSettings.shared

    var body: some View {
        Form {
            Section("Claude") {
                Toggle("Scan All Terminal Sessions", isOn: $debugSettings.claudeScanAllSessions)
                Text("When disabled (default), only scans the frontmost terminal session for faster detection. Enable to scan all windows/tabs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Thresholds Tab

struct ThresholdsSettingsTab: View {
    @ObservedObject var settings = ThresholdSettings.shared

    var body: some View {
        Form {
            Section {
                Text("Adjust when each detector triggers. Lower values = more sensitive.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Claude") {
                ThresholdSlider(label: "Low (idle)", value: $settings.claudeLowThreshold, range: 0...50, defaultValue: ThresholdSettings.defaultClaudeLow)
                ThresholdSlider(label: "High (active)", value: $settings.claudeHighThreshold, range: 0...100, defaultValue: ThresholdSettings.defaultClaudeHigh)
            }

            Section("Opencode") {
                ThresholdSlider(label: "Low (idle)", value: $settings.opencodeLowThreshold, range: 0...20, defaultValue: ThresholdSettings.defaultOpencodeLow)
                ThresholdSlider(label: "High (active)", value: $settings.opencodeHighThreshold, range: 0...50, defaultValue: ThresholdSettings.defaultOpencodeHigh)
            }

            Section("Xcode") {
                ThresholdSlider(label: "Threshold", value: $settings.xcodeThreshold, range: 0...50, defaultValue: ThresholdSettings.defaultXcode)
            }

            Section {
                Button("Reset All to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ThresholdSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Slider(value: $value, in: range, step: 0.5)
            Text("\(String(format: "%.1f", value))%")
                .frame(width: 50)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
}
