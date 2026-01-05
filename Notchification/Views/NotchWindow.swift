//
//  NotchWindow.swift
//  Notchification
//

import AppKit
import SwiftUI

/// Observable state for the notch view
final class NotchState: ObservableObject {
    @Published var activeProcesses: [ProcessType] = []
    /// Processes that were manually dismissed (skip confetti for these)
    var recentlyDismissed: Set<ProcessType> = []

    /// Callback when processes change (for updating mouse tracker)
    var onProcessCountChanged: ((Int) -> Void)?
}

/// Tracks mouse position and toggles window mouse events when cursor enters notch area
final class NotchMouseTracker {
    private var timer: Timer?
    private weak var window: NSWindow?
    private var notchRect: NSRect = .zero
    private var isMouseInNotch = false

    private var notchWidth: CGFloat = 320
    private var screenFrame: NSRect = .zero

    // Layout constants (must match NotchView)
    private let logoSize: CGFloat = 24
    private let rowSpacing: CGFloat = 8
    private let topPadding: CGFloat = 38
    private let baseHeight: CGFloat = 50

    init(window: NSWindow) {
        self.window = window
        startTracking()
    }

    func updateNotchRect(notchWidth: CGFloat, notchHeight: CGFloat, screenFrame: NSRect) {
        self.notchWidth = notchWidth
        self.screenFrame = screenFrame
        // Notch area at top center of screen (in screen coordinates)
        let x = screenFrame.minX + (screenFrame.width - notchWidth) / 2
        let y = screenFrame.maxY - notchHeight
        notchRect = NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    /// Update the interactive height based on process count
    func updateForProcessCount(_ count: Int) {
        guard screenFrame != .zero else { return }

        let height: CGFloat
        if count == 0 {
            height = baseHeight
        } else {
            let contentHeight = CGFloat(count) * logoSize + CGFloat(count - 1) * rowSpacing
            let expandedHeight = topPadding + contentHeight + 16
            height = max(baseHeight, expandedHeight + 20)
        }

        let x = screenFrame.minX + (screenFrame.width - notchWidth) / 2
        let y = screenFrame.maxY - height
        notchRect = NSRect(x: x, y: y, width: notchWidth, height: height)
    }

    private func startTracking() {
        // Poll mouse position frequently
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func checkMousePosition() {
        guard let window = window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let isInNotch = notchRect.contains(mouseLocation)

        if isInNotch != isMouseInNotch {
            isMouseInNotch = isInNotch
            window.ignoresMouseEvents = !isInNotch
        }
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopTracking()
    }
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
    private var mouseTracker: NotchMouseTracker?

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
        // Ignore mouse events by default - tracker will enable when cursor is in notch area
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

        // Setup mouse tracker for the notch area
        let notchWidth: CGFloat = 320
        let initialHeight: CGFloat = 50  // Base height, will expand dynamically
        if let screen = currentScreen {
            mouseTracker = NotchMouseTracker(window: self)
            mouseTracker?.updateNotchRect(
                notchWidth: notchWidth,
                notchHeight: initialHeight,
                screenFrame: screen.frame
            )

            // Update mouse tracker when process count changes
            notchState.onProcessCountChanged = { [weak self] count in
                self?.mouseTracker?.updateForProcessCount(count)
            }
        }
    }

    /// Update the active processes
    func updateProcesses(_ processes: [ProcessType]) {
        notchState.activeProcesses = processes
        notchState.onProcessCountChanged?(processes.count)
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
