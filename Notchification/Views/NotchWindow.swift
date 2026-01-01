//
//  NotchWindow.swift
//  Notchification
//

import AppKit
import SwiftUI

/// A borderless window that displays the notch indicator at the top of the screen
final class NotchWindow: NSWindow {

    private let windowWidth: CGFloat = 280
    private let windowHeight: CGFloat = 100

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

        let screenFrame = screen.visibleFrame
        let fullFrame = screen.frame

        // Center horizontally, position at the absolute top of screen (above menu bar)
        let x = fullFrame.midX - (windowWidth / 2)
        let y = fullFrame.maxY - windowHeight  // Flush with top of screen

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
        // Create window immediately so it's ready
        window = NotchWindow()
    }

    func show(with processes: [ProcessType]) {
        window?.updateContent(with: processes)
        window?.orderFrontRegardless()
    }

    func hide() {
        // Don't actually hide - just show empty state
        window?.updateContent(with: [])
    }

    func update(with processes: [ProcessType]) {
        if processes.isEmpty {
            hide()
        } else {
            show(with: processes)
        }
    }
}
