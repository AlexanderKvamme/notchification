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

    var body: some View {
        Form {
            Section {
                Picker("Screen:", selection: $styleSettings.screenMode) {
                    ForEach(ScreenMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Select which screen(s) to show the notch indicator on")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Picker("Display Style", selection: $styleSettings.notchStyle) {
                    ForEach(NotchStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch styleSettings.notchStyle {
                    case .normal:
                        Text("Full size with icons and progress bars")
                    case .medium:
                        Text("Compact view at notch width with smaller icons")
                    case .minimal:
                        Text("Only a colored border around the notch")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                Toggle("Trim top on notch displays", isOn: $styleSettings.trimTopOnNotchDisplay)
                Text("Remove extra padding above progress bars on MacBook displays")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Trim top on external displays", isOn: $styleSettings.trimTopOnExternalDisplay)
                Text("Remove extra padding above progress bars on displays without a notch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("Horizontal Position")
                    Slider(value: $styleSettings.horizontalOffset, in: -500...500, step: 1)
                        .onChange(of: styleSettings.horizontalOffset) { _, _ in
                            NotificationCenter.default.post(name: .showPositionPreview, object: nil)
                        }
                    Text("\(Int(styleSettings.horizontalOffset))")
                        .frame(width: 40)
                        .monospacedDigit()
                }
                Button("Reset to Center") {
                    styleSettings.horizontalOffset = 0
                }
                .disabled(styleSettings.horizontalOffset == 0)
                Text("Adjust horizontal position for external displays")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Manage License...") {
                    LicenseWindowController.shared.showLicenseWindow()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            NotificationCenter.default.post(name: .showSettingsPreview, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .hideSettingsPreview, object: nil)
        }
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
