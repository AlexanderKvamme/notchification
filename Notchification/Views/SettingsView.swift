//
//  SettingsView.swift
//  Notchification
//
//  CPU threshold settings for detectors
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = ThresholdSettings.shared
    @ObservedObject var styleSettings = StyleSettings.shared
    @State private var availableScreens: [NSScreen] = NSScreen.screens

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Screen Selection Section
            Text("Display")
                .font(.title2)
                .fontWeight(.semibold)

            HStack {
                Text("Screen:")
                Picker("Screen", selection: $styleSettings.selectedScreenIndex) {
                    Text("Main Screen").tag(-1)
                    ForEach(Array(availableScreens.enumerated()), id: \.offset) { index, screen in
                        Text(screenName(for: screen, at: index)).tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Text("Select which screen to show the notch indicator on")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Minimal Style", isOn: $styleSettings.minimalStyle)
            Text("Shows only a colored border around the notch (no icons or progress bars)")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // CPU Thresholds Section
            Text("CPU Thresholds")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Adjust when each detector triggers. Lower values = more sensitive.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Claude Settings
            ThresholdSection(
                title: "Claude",
                color: ProcessType.claude.color,
                lowValue: $settings.claudeLowThreshold,
                highValue: $settings.claudeHighThreshold,
                lowRange: 0...50,
                highRange: 0...100,
                defaultLow: ThresholdSettings.defaultClaudeLow,
                defaultHigh: ThresholdSettings.defaultClaudeHigh
            )

            Divider()

            // Opencode Settings
            ThresholdSection(
                title: "Opencode",
                color: ProcessType.opencode.color,
                lowValue: $settings.opencodeLowThreshold,
                highValue: $settings.opencodeHighThreshold,
                lowRange: 0...20,
                highRange: 0...50,
                defaultLow: ThresholdSettings.defaultOpencodeLow,
                defaultHigh: ThresholdSettings.defaultOpencodeHigh
            )

            Divider()

            // Xcode Settings
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(ProcessType.xcode.color)
                        .frame(width: 10, height: 10)
                    Text("Xcode")
                        .font(.headline)
                }

                HStack {
                    Text("Threshold:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.xcodeThreshold, in: 0...50, step: 1)
                    Text("\(Int(settings.xcodeThreshold))%")
                        .frame(width: 40)
                        .monospacedDigit()
                }
                .font(.caption)

                Text("Default: \(Int(ThresholdSettings.defaultXcode))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Button("Reset All to Defaults") {
                    settings.resetToDefaults()
                }

                Spacer()

                Button("Done") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct ThresholdSection: View {
    let title: String
    let color: Color
    @Binding var lowValue: Double
    @Binding var highValue: Double
    let lowRange: ClosedRange<Double>
    let highRange: ClosedRange<Double>
    let defaultLow: Double
    let defaultHigh: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.headline)
            }

            HStack {
                Text("Low (idle):")
                    .frame(width: 80, alignment: .leading)
                Slider(value: $lowValue, in: lowRange, step: 0.5)
                Text("\(String(format: "%.1f", lowValue))%")
                    .frame(width: 50)
                    .monospacedDigit()
            }
            .font(.caption)

            HStack {
                Text("High (active):")
                    .frame(width: 80, alignment: .leading)
                Slider(value: $highValue, in: highRange, step: 0.5)
                Text("\(String(format: "%.1f", highValue))%")
                    .frame(width: 50)
                    .monospacedDigit()
            }
            .font(.caption)

            Text("Defaults: Low \(String(format: "%.1f", defaultLow))%, High \(String(format: "%.1f", defaultHigh))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

extension SettingsView {
    /// Generate a descriptive name for a screen
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

#Preview {
    SettingsView()
}
