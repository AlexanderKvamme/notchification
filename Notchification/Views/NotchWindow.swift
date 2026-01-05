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

    private var currentScreen: NSScreen? {
        StyleSettings.shared.selectedScreen
    }

    private var windowWidth: CGFloat {
        currentScreen?.frame.width ?? 1440
    }
    private var windowHeight: CGFloat {
        currentScreen?.frame.height ?? 900
    }
    let notchState = NotchState()

    private var screenObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        positionOnSelectedScreen()
        setupContent()
        observeScreenChanges()
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = selectionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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

    private func observeScreenChanges() {
        // Observe screen configuration changes (displays connected/disconnected)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionWindow()
        }

        // Observe screen selection changes from settings
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .screenSelectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionWindow()
        }
    }

    private func positionOnSelectedScreen() {
        guard let screen = currentScreen else { return }

        // Position window to cover the full screen
        // The NotchView inside will center the notch content at the top
        setFrame(screen.frame, display: true)
    }

    /// Reposition the window on the selected screen and rebuild content
    func repositionWindow() {
        positionOnSelectedScreen()
        setupContent()
    }

    private func setupContent() {
        let width = windowWidth
        let height = windowHeight
        let hostingView = NSHostingView(rootView:
            VStack(spacing: 0) {
                NotchView(notchState: notchState, screenWidth: width, screenHeight: height)
                Spacer()
            }
            .frame(width: width, height: height, alignment: .top)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
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
