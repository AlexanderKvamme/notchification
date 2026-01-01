//
//  NotchWindow.swift
//  Notchification
//

import AppKit
import SwiftUI

/// Observable state for the notch view
final class NotchState: ObservableObject {
    @Published var activeProcesses: [ProcessType] = []
}

/// A borderless window that displays the notch indicator at the top of the screen
final class NotchWindow: NSWindow {

    private let windowWidth: CGFloat = 380  // Extra width for outward curves (40 each side)
    private let windowHeight: CGFloat = 130
    let notchState = NotchState()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        positionAtNotch()
        setupContent()
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

        // Center horizontally, flush with top of screen
        let x = fullFrame.midX - (windowWidth / 2)
        let y = fullFrame.maxY - windowHeight

        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    private func setupContent() {
        let hostingView = NSHostingView(rootView:
            VStack(spacing: 0) {
                NotchView(notchState: notchState)
                Spacer()
            }
            .frame(width: windowWidth, height: windowHeight)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        contentView = hostingView
    }

    /// Update the active processes
    func updateProcesses(_ processes: [ProcessType]) {
        notchState.activeProcesses = processes
    }
}

/// Controller to manage the notch window visibility
final class NotchWindowController: ObservableObject {
    private var window: NotchWindow?
    private(set) var isShowing: Bool = false

    init() {
        // Create window immediately and show it (animation happens inside)
        window = NotchWindow()
        window?.orderFrontRegardless()
    }

    func update(with processes: [ProcessType]) {
        isShowing = !processes.isEmpty
        window?.updateProcesses(processes)
        // Keep window always visible - the NotchView animates in/out
        window?.orderFrontRegardless()
    }
}
