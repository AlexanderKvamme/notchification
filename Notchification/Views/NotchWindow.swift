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
    private var hasActiveProcesses = false  // Only capture mouse when processes are visible

    private var screenFrame: NSRect = .zero
    private weak var targetScreen: NSScreen?

    // Layout constants for normal mode (must match NotchView)
    private let normalNotchWidth: CGFloat = 300
    private let normalLogoSize: CGFloat = 24
    private let normalRowSpacing: CGFloat = 8
    private let normalTopPadding: CGFloat = 38

    // Layout constants for medium mode
    private let mediumLogoSize: CGFloat = 14
    private let mediumRowSpacing: CGFloat = 3
    private let mediumTopPadding: CGFloat = 34

    // Debug overlay window
    private var debugWindow: NSWindow?
    static var showDebugOverlay = false  // Set to true to debug click area

    init(window: NSWindow) {
        self.window = window
        startTracking()
    }

    func updateNotchRect(notchWidth: CGFloat, notchHeight: CGFloat, screenFrame: NSRect) {
        self.screenFrame = screenFrame
    }

    func setTargetScreen(_ screen: NSScreen) {
        self.targetScreen = screen
        self.screenFrame = screen.frame
    }

    /// Update the interactive area based on process count and current display mode
    func updateForProcessCount(_ count: Int) {
        guard screenFrame != .zero else { return }

        hasActiveProcesses = count > 0

        // When no processes, immediately disable mouse events and hide debug
        if count == 0 {
            window?.ignoresMouseEvents = true
            isMouseInNotch = false
            notchRect = .zero
            updateDebugOverlay()
            return
        }

        let settings = StyleSettings.shared
        let notchInfo = NotchInfo.forScreen(targetScreen)
        let horizontalOffset = settings.horizontalOffset

        let width: CGFloat
        let height: CGFloat

        switch settings.notchStyle {
        case .minimal:
            // Minimal mode: just the notch outline area
            width = notchInfo.width + 20  // Small padding
            height = notchInfo.height + 10

        case .medium:
            // Medium mode: notch width with smaller content
            width = notchInfo.width
            let contentHeight = CGFloat(count) * mediumLogoSize + CGFloat(count - 1) * mediumRowSpacing
            let effectiveTopPadding = (settings.trimTopOnNotchDisplay && notchInfo.hasNotch) ||
                                      (settings.trimTopOnExternalDisplay && !notchInfo.hasNotch) ? 8 : mediumTopPadding
            height = effectiveTopPadding + contentHeight + 13

        case .normal:
            // Normal mode: full width with icons and progress bars
            width = normalNotchWidth
            let contentHeight = CGFloat(count) * normalLogoSize + CGFloat(count - 1) * normalRowSpacing
            let effectiveTopPadding = (settings.trimTopOnNotchDisplay && notchInfo.hasNotch) ||
                                      (settings.trimTopOnExternalDisplay && !notchInfo.hasNotch) ? 8 : normalTopPadding
            height = effectiveTopPadding + contentHeight + 16
        }

        // Calculate position: center of screen + horizontal offset
        let x = screenFrame.minX + (screenFrame.width - width) / 2 + horizontalOffset
        let y = screenFrame.maxY - height
        notchRect = NSRect(x: x, y: y, width: width, height: height)
        updateDebugOverlay()
    }

    private func startTracking() {
        // Poll mouse position frequently
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func checkMousePosition() {
        guard let window = window else { return }

        // Don't capture mouse events when no processes are visible
        guard hasActiveProcesses else {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
                isMouseInNotch = false
            }
            return
        }

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
        debugWindow?.close()
        debugWindow = nil
    }

    private func updateDebugOverlay() {
        guard NotchMouseTracker.showDebugOverlay else {
            debugWindow?.close()
            debugWindow = nil
            return
        }

        if debugWindow == nil {
            let window = NSWindow(
                contentRect: notchRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
            window.backgroundColor = NSColor.red.withAlphaComponent(0.3)
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            debugWindow = window
        }

        debugWindow?.setFrame(notchRect, display: true)
        debugWindow?.orderFrontRegardless()
    }

    deinit {
        stopTracking()
    }
}

/// A borderless window that displays the notch indicator at the top of the screen
final class NotchWindow: NSWindow {

    private let targetScreen: NSScreen

    private var windowWidth: CGFloat {
        targetScreen.frame.width
    }
    private var windowHeight: CGFloat {
        targetScreen.frame.height
    }
    let notchState = NotchState()

    private var mouseTracker: NotchMouseTracker?

    init(screen: NSScreen) {
        self.targetScreen = screen
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        positionOnScreen()
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
        // Ignore mouse events by default - tracker will enable when cursor is in notch area
        ignoresMouseEvents = true

        // No title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }

    private func positionOnScreen() {
        // Position window to cover the full screen
        // The NotchView inside will center the notch content at the top
        setFrame(targetScreen.frame, display: true)
    }

    private func setupContent() {
        let width = windowWidth
        let height = windowHeight
        let hostingView = NSHostingView(rootView:
            VStack(spacing: 0) {
                NotchView(notchState: notchState, screenWidth: width, screenHeight: height, screen: targetScreen)
                Spacer()
            }
            .frame(width: width, height: height, alignment: .top)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentView = hostingView

        // Setup mouse tracker for the notch area
        mouseTracker = NotchMouseTracker(window: self)
        mouseTracker?.setTargetScreen(targetScreen)

        // Update mouse tracker when process count changes
        notchState.onProcessCountChanged = { [weak self] count in
            self?.mouseTracker?.updateForProcessCount(count)
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
    private var windows: [NSScreen: NotchWindow] = [:]
    private(set) var isShowing: Bool = false
    private var screenObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?

    init() {
        setupWindows()
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

    private func observeScreenChanges() {
        // Observe screen configuration changes
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupWindows()
        }

        // Observe screen selection changes from settings
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .screenSelectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupWindows()
        }
    }

    private func setupWindows() {
        let screensToShow = StyleSettings.shared.screensToShow

        // Remove windows for screens that shouldn't be shown anymore
        for screen in windows.keys {
            if !screensToShow.contains(screen) {
                windows[screen]?.close()
                windows.removeValue(forKey: screen)
            }
        }

        // Add windows for new screens
        for screen in screensToShow {
            if windows[screen] == nil {
                let window = NotchWindow(screen: screen)
                window.orderFrontRegardless()
                windows[screen] = window
            }
        }
    }

    func update(with processes: [ProcessType]) {
        isShowing = !processes.isEmpty
        for window in windows.values {
            window.updateProcesses(processes)
            window.orderFrontRegardless()
        }
    }
}
