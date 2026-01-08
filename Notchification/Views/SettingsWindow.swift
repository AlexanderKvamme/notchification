//
//  SettingsWindow.swift
//  Notchification
//
//  Window controller for Settings
//

import AppKit
import SwiftUI

/// Manages the Settings window
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showSettings() {
        // If window exists and is visible, just bring it to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Notchification Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating  // Ensure it appears above other windows

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let x = screenFrame.midX - windowSize.width / 2
            let y = screenFrame.midY - windowSize.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = window

        // Menu bar apps need to activate as regular app to show windows
        NSApp.setActivationPolicy(.accessory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
