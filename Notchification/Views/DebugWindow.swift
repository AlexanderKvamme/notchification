//
//  DebugWindow.swift
//  Notchification
//
//  Debug panel window (DEBUG builds only)
//

import AppKit
import SwiftUI

#if DEBUG
/// Manages the Debug window
final class DebugWindowController {
    static let shared = DebugWindowController()

    private var window: NSWindow?

    private init() {}

    func showDebugPanel() {
        // If window exists and is visible, just bring it to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let debugView = DebugPanelView()
        let hostingController = NSHostingController(rootView: debugView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Debug Panel"
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.setFrameAutosaveName("DebugWindow")
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.window = window

        NSApp.setActivationPolicy(.accessory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DebugPanelView: View {
    @ObservedObject var debugSettings = DebugSettings.shared
    @ObservedObject var licenseManager = LicenseManager.shared

    // Mock settings stored in UserDefaults
    @AppStorage("mockOnLaunchType") private var mockOnLaunchTypeRaw: String = "None"
    @AppStorage("mockRepeat") private var mockRepeat: Bool = false

    private var mockOnLaunchType: Binding<MockProcessType> {
        Binding(
            get: { MockProcessType(rawValue: mockOnLaunchTypeRaw) ?? .none },
            set: { mockOnLaunchTypeRaw = $0.rawValue }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left column: Mock on Launch
            VStack(alignment: .leading, spacing: 12) {
                Text("Mock on Launch")
                    .font(.headline)

                Picker("Mock Type", selection: mockOnLaunchType) {
                    ForEach(MockProcessType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 180)

                Toggle("Repeat", isOn: $mockRepeat)

                Text("Restart app to apply")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 200)

            Divider()

            // Right column: Debug Logging
            VStack(alignment: .leading, spacing: 12) {
                Text("Debug Logging")
                    .font(.headline)

                Toggle("Claude Code", isOn: $debugSettings.debugClaudeCode)
                Toggle("Claude App", isOn: $debugSettings.debugClaudeApp)
                Toggle("Android Studio", isOn: $debugSettings.debugAndroid)
                Toggle("Xcode", isOn: $debugSettings.debugXcode)
                Toggle("Finder", isOn: $debugSettings.debugFinder)
                Toggle("Opencode", isOn: $debugSettings.debugOpencode)
                Toggle("Codex", isOn: $debugSettings.debugCodex)

                Divider()

                Text("License Debug")
                    .font(.headline)

                HStack {
                    Button("Reset Trial") {
                        licenseManager.resetTrial()
                    }
                    Button("Expire Trial") {
                        licenseManager.expireTrial()
                    }
                }
            }
            .frame(minWidth: 180)
        }
        .padding(20)
        .frame(minWidth: 450, minHeight: 300)
    }
}
#endif
