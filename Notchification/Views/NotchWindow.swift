//
//  NotchWindow.swift
//  Notchification
//

import AppKit
import SwiftUI

/// A borderless window that displays the notch indicator at the top of the screen
final class NotchWindow: NSWindow {

    private let windowWidth: CGFloat = 300
    private let windowHeight: CGFloat = 130

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        positionAtNotch()
    }

    private func configureWindow() {
        // Make it float above everything
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

        // Transparent background
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // Don't show in mission control, don't take focus
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true

        // No title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }

    private func positionAtNotch() {
        guard let screen = NSScreen.main else { return }

        let fullFrame = screen.frame

        // Center horizontally, position 10 pixels down from top so entire shape is visible
        let x = fullFrame.midX - (windowWidth / 2)
        let y = fullFrame.maxY - windowHeight - 10

        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    /// Update the content view with new active processes
    func updateContent(with processes: [ProcessType]) {
        let hostingView = NSHostingView(rootView:
            VStack(spacing: 0) {
                NotchView(activeProcesses: processes)
                Spacer()
            }
            .frame(width: windowWidth, height: windowHeight)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        contentView = hostingView
    }
}

/// Controller to manage the notch window visibility
final class NotchWindowController: ObservableObject {
    private var window: NotchWindow?

    init() {
        // Create window immediately and show it (animation happens inside)
        window = NotchWindow()
        window?.updateContent(with: [])
        window?.orderFrontRegardless()
    }

    func update(with processes: [ProcessType]) {
        window?.updateContent(with: processes)
        // Keep window always visible - the NotchView animates in/out
        window?.orderFrontRegardless()
    }
}
