//
//  NotchWindow.swift
//  Notchification
//

import AppKit
import SwiftUI
import ConfettiSwiftUI

/// Shared confetti state - allows NotchView to trigger confetti in the separate ConfettiWindow
final class ConfettiState: ObservableObject {
    static let shared = ConfettiState()

    @Published var claudeTrigger: Int = 0
    @Published var xcodeTrigger: Int = 0
    @Published var androidTrigger: Int = 0
    @Published var finderTrigger: Int = 0
    @Published var opencodeTrigger: Int = 0
    @Published var codexTrigger: Int = 0
    @Published var dropboxTrigger: Int = 0
    @Published var googleDriveTrigger: Int = 0
    @Published var oneDriveTrigger: Int = 0
    @Published var icloudTrigger: Int = 0
    @Published var installerTrigger: Int = 0
    @Published var appStoreTrigger: Int = 0
    @Published var automatorTrigger: Int = 0
    @Published var scriptEditorTrigger: Int = 0
    @Published var downloadsTrigger: Int = 0
    @Published var davinciResolveTrigger: Int = 0
    @Published var teamsTrigger: Int = 0
    @Published var calendarTrigger: Int = 0

    func trigger(for process: ProcessType) {
        switch process {
        case .claudeCode, .claudeApp: claudeTrigger += 1
        case .xcode: xcodeTrigger += 1
        case .androidStudio: androidTrigger += 1
        case .finder: finderTrigger += 1
        case .opencode: opencodeTrigger += 1
        case .codex: codexTrigger += 1
        case .dropbox: dropboxTrigger += 1
        case .googleDrive: googleDriveTrigger += 1
        case .oneDrive: oneDriveTrigger += 1
        case .icloud: icloudTrigger += 1
        case .installer: installerTrigger += 1
        case .appStore: appStoreTrigger += 1
        case .automator: automatorTrigger += 1
        case .scriptEditor: scriptEditorTrigger += 1
        case .downloads: downloadsTrigger += 1
        case .davinciResolve: davinciResolveTrigger += 1
        case .teams: teamsTrigger += 1
        case .calendar: calendarTrigger += 1
        case .preview: break  // No confetti for preview
        }
    }
}

/// Observable state for the notch view
final class NotchState: ObservableObject {
    @Published var activeProcesses: [ProcessType] = [] {
        didSet {
            // Notify callback whenever processes change (including direct modifications)
            onProcessesChanged?(activeProcesses)
        }
    }
    /// Processes that were manually dismissed (skip confetti for these)
    var recentlyDismissed: Set<ProcessType> = []

    /// Callback when processes change (for updating mouse tracker and window size)
    var onProcessesChanged: (([ProcessType]) -> Void)?
}

/// Tracks mouse position and toggles window mouse events when cursor enters notch area
final class NotchMouseTracker {
    private var timer: Timer?
    private weak var window: NSWindow?
    private var notchRect: NSRect = .zero
    private var isMouseInNotch = false
    private var hasActiveProcesses = false  // Only capture mouse when processes are visible
    private var hasBeenUpdated = false  // Track if we've set the rect before (for delayed shrinking)
    private var pendingShrinkWorkItem: DispatchWorkItem?  // For delayed shrinking

    private var screenFrame: NSRect = .zero
    private weak var targetScreen: NSScreen?

    // Debug overlay window
    private var debugWindow: NSWindow?
    static var showDebugOverlay = false  // Set to true to debug click area

    init(window: NSWindow) {
        self.window = window
        // Timer starts only when processes become active
    }

    func updateNotchRect(notchWidth: CGFloat, notchHeight: CGFloat, screenFrame: NSRect) {
        self.screenFrame = screenFrame
    }

    func setTargetScreen(_ screen: NSScreen) {
        self.targetScreen = screen
        self.screenFrame = screen.frame
    }

    /// Update the interactive area based on active processes
    /// Uses shared NotchLayout.windowFrame for consistent sizing with NotchWindow
    func updateForProcesses(_ processes: [ProcessType]) {
        guard let screen = targetScreen else { return }

        // Cancel any pending shrink operation
        pendingShrinkWorkItem?.cancel()
        pendingShrinkWorkItem = nil

        hasActiveProcesses = !processes.isEmpty

        // When no processes, delay cleanup to let animation finish
        // Minimal mode needs longer (1.0s wave + 0.3s fade = 1.3s)
        if processes.isEmpty {
            let cleanupDelay: Double = StyleSettings.shared.notchStyle == .minimal ? 1.5 : 0.35
            let workItem = DispatchWorkItem { [weak self] in
                self?.timer?.invalidate()
                self?.timer = nil
                self?.window?.ignoresMouseEvents = true
                self?.isMouseInNotch = false
                self?.notchRect = .zero
                self?.updateDebugOverlay()
            }
            pendingShrinkWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay, execute: workItem)
            return
        }

        // Start timer if not already running
        if timer == nil {
            startTracking()
        }

        // Use shared calculation for exact match with NotchWindow
        let newRect = NotchLayout.windowFrame(
            for: processes,
            style: StyleSettings.shared.notchStyle,
            screen: screen,
            settings: StyleSettings.shared
        )

        // Check if we're shrinking - need to wait for animation to complete
        // But only delay if we've updated before (no animation on first update)
        let isShrinking = newRect.height < notchRect.height || newRect.width < notchRect.width
        let shouldDelayShrink = isShrinking && hasBeenUpdated && notchRect != .zero

        if shouldDelayShrink {
            // Delay shrinking to let the spring animation finish (~0.4s)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, let screen = self.targetScreen else { return }
                // Recalculate in case things changed
                self.notchRect = NotchLayout.windowFrame(
                    for: processes,
                    style: StyleSettings.shared.notchStyle,
                    screen: screen,
                    settings: StyleSettings.shared
                )
                self.updateDebugOverlay()
            }
            pendingShrinkWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
        } else {
            // Growing, same size, or first update - update immediately
            notchRect = newRect
            updateDebugOverlay()
            hasBeenUpdated = true
        }
    }

    private func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
/// Now sized to match content only - confetti is rendered in a separate ConfettiWindow
final class NotchWindow: NSWindow {

    private let targetScreen: NSScreen

    /// Dynamic window dimensions based on content
    private var currentWindowWidth: CGFloat = 300
    private var currentWindowHeight: CGFloat = 300
    private var hasBeenShown: Bool = false  // Track if window has been shown yet
    let notchState = NotchState()

    private var mouseTracker: NotchMouseTracker?
    private var styleObserver: NSObjectProtocol?

    // Prevent window from being selected in screenshot window picker
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        self.targetScreen = screen
        // Start with a reasonable default size - will be updated by updateWindowSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        // Skip positionOnScreen() - let updateWindowSize handle all sizing
        setupContent()
    }

    // Debug mode to visualize window bounds
    static var showDebugBackground = false

    private func configureWindow() {
        // Make it float above everything
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

        // Debug: show window bounds with semi-transparent background
        if NotchWindow.showDebugBackground {
            backgroundColor = NSColor.blue.withAlphaComponent(0.2)
        } else {
            backgroundColor = .clear
        }
        isOpaque = false
        hasShadow = false

        // Don't show in mission control, don't take focus, don't appear in window picker
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary, .transient]
        // Ignore mouse events by default - tracker will enable when cursor is in notch area
        ignoresMouseEvents = true

        // Exclude from window menus and lists
        isExcludedFromWindowsMenu = true

        // Allow screenshots
        sharingType = .readOnly

        // No title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }

    private func positionOnScreen() {
        // Position window at top center of screen - start small, will resize when processes change
        let horizontalOffset = StyleSettings.shared.horizontalOffset
        let x = targetScreen.frame.origin.x + (targetScreen.frame.width - currentWindowWidth) / 2 + horizontalOffset
        let frame = NSRect(
            x: x,
            y: targetScreen.frame.origin.y + targetScreen.frame.height - currentWindowHeight,
            width: currentWindowWidth,
            height: currentWindowHeight
        )
        setFrame(frame, display: true)
    }

    private func setupContent() {
        // Hosting view matches window size exactly
        let hostingView = NSHostingView(rootView:
            NotchView(notchState: notchState, screenWidth: currentWindowWidth, screenHeight: currentWindowHeight, screen: targetScreen)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: currentWindowWidth, height: currentWindowHeight)
        contentView = hostingView

        // Setup mouse tracker for the notch area
        mouseTracker = NotchMouseTracker(window: self)
        mouseTracker?.setTargetScreen(targetScreen)

        // Update mouse tracker and window size when processes change
        notchState.onProcessesChanged = { [weak self] processes in
            print("🪟 onProcessesChanged triggered with \(processes.count) processes")
            self?.mouseTracker?.updateForProcesses(processes)
            // Also update window size (deferred to next run loop)
            RunLoop.main.perform {
                self?.updateWindowSize(for: processes)
            }
        }

        // Observe style changes to resize window
        styleObserver = NotificationCenter.default.addObserver(
            forName: .notchStyleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let processes = self.notchState.activeProcesses
            self.mouseTracker?.updateForProcesses(processes)
            RunLoop.main.perform {
                self.updateWindowSize(for: processes)
            }
        }
    }

    /// Update the active processes
    func updateProcesses(_ processes: [ProcessType]) {
        // Setting activeProcesses triggers didSet which calls onProcessesChanged
        // onProcessesChanged updates both mouse tracker and window size
        notchState.activeProcesses = processes
    }

    /// Resize window to fit content - uses shared NotchLayout.windowFrame for exact match with clickable area
    private func updateWindowSize(for processes: [ProcessType]) {
        print("🪟 updateWindowSize called with \(processes.count) processes: \(processes.map { $0.displayName })")

        // Hide window when no processes - prevents it from appearing in screenshot picker
        guard !processes.isEmpty else {
            // Delay hiding to let the collapse animation finish
            // Minimal mode needs longer (1.0s wave + 0.3s fade = 1.3s)
            // Normal/Medium mode needs 0.35s
            let hideDelay: Double = StyleSettings.shared.notchStyle == .minimal ? 1.5 : 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) { [weak self] in
                // Only hide if still empty (processes might have been added back)
                if self?.notchState.activeProcesses.isEmpty == true {
                    self?.orderOut(nil)
                }
            }
            return
        }

        // Use shared calculation for exact match with clickable area
        let newFrame = NotchLayout.windowFrame(
            for: processes,
            style: StyleSettings.shared.notchStyle,
            screen: targetScreen,
            settings: StyleSettings.shared
        )

        guard newFrame != .zero else {
            orderOut(nil)
            return
        }

        // Check if we're shrinking - need to wait for animation to complete
        // But only delay if window has been shown before (no animation on first show)
        let isShrinking = newFrame.height < currentWindowHeight || newFrame.width < currentWindowWidth
        let shouldDelayShrink = isShrinking && hasBeenShown

        if shouldDelayShrink {
            // Delay shrinking to let the spring animation finish (~0.4s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                // Recalculate in case processes changed during the delay
                let currentProcesses = self.notchState.activeProcesses
                guard !currentProcesses.isEmpty else { return }

                let finalFrame = NotchLayout.windowFrame(
                    for: currentProcesses,
                    style: StyleSettings.shared.notchStyle,
                    screen: self.targetScreen,
                    settings: StyleSettings.shared
                )
                guard finalFrame != .zero else { return }

                self.currentWindowWidth = finalFrame.width
                self.currentWindowHeight = finalFrame.height
                self.setFrame(finalFrame, display: true, animate: false)

                if let hostingView = self.contentView {
                    hostingView.frame = NSRect(x: 0, y: 0, width: finalFrame.width, height: finalFrame.height)
                }
            }
        } else {
            // Growing, same size, or first show - update immediately
            currentWindowWidth = newFrame.width
            currentWindowHeight = newFrame.height
            setFrame(newFrame, display: true, animate: false)

            // Update hosting view to match new window size
            if let hostingView = contentView {
                hostingView.frame = NSRect(x: 0, y: 0, width: newFrame.width, height: newFrame.height)
            }
        }

        // Show the window and mark as shown
        print("🪟 Calling orderFrontRegardless() for window, frame: \(self.frame)")
        orderFrontRegardless()
        hasBeenShown = true
    }
}

// MARK: - Confetti Window

/// Separate window for confetti effects - large, transparent, completely non-interactive
final class ConfettiWindow: NSWindow {
    private let targetScreen: NSScreen

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        self.targetScreen = screen
        // Full screen to allow confetti to spread anywhere
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        positionOnScreen()
        setupContent()
    }

    private func configureWindow() {
        // Same level as NotchWindow
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

        // Completely transparent
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // Same behavior as NotchWindow but always ignores mouse
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        sharingType = .readOnly

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }

    private func positionOnScreen() {
        // Full screen coverage
        setFrame(targetScreen.frame, display: true)
    }

    private func setupContent() {
        let hostingView = NSHostingView(rootView: ConfettiOverlayView())
        hostingView.frame = NSRect(x: 0, y: 0, width: targetScreen.frame.width, height: targetScreen.frame.height)
        contentView = hostingView
    }
}

/// SwiftUI view that renders confetti emitters based on shared ConfettiState
struct ConfettiOverlayView: View {
    @ObservedObject private var confettiState = ConfettiState.shared

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            // Confetti emitters positioned at top center
            VStack {
                ZStack {
                    ConfettiEmitterView(trigger: $confettiState.claudeTrigger, color: ProcessType.claudeCode.color)
                    ConfettiEmitterView(trigger: $confettiState.xcodeTrigger, color: ProcessType.xcode.color)
                    ConfettiEmitterView(trigger: $confettiState.androidTrigger, color: ProcessType.androidStudio.color)
                    ConfettiEmitterView(trigger: $confettiState.finderTrigger, color: ProcessType.finder.color)
                    ConfettiEmitterView(trigger: $confettiState.opencodeTrigger, color: ProcessType.opencode.color)
                    ConfettiEmitterView(trigger: $confettiState.codexTrigger, color: ProcessType.codex.color)
                    ConfettiEmitterView(trigger: $confettiState.dropboxTrigger, color: ProcessType.dropbox.color)
                    ConfettiEmitterView(trigger: $confettiState.googleDriveTrigger, color: ProcessType.googleDrive.color)
                    ConfettiEmitterView(trigger: $confettiState.oneDriveTrigger, color: ProcessType.oneDrive.color)
                    ConfettiEmitterView(trigger: $confettiState.icloudTrigger, color: ProcessType.icloud.color)
                    ConfettiEmitterView(trigger: $confettiState.installerTrigger, color: ProcessType.installer.color)
                    ConfettiEmitterView(trigger: $confettiState.appStoreTrigger, color: ProcessType.appStore.color)
                    ConfettiEmitterView(trigger: $confettiState.automatorTrigger, color: ProcessType.automator.color)
                    ConfettiEmitterView(trigger: $confettiState.scriptEditorTrigger, color: ProcessType.scriptEditor.color)
                    ConfettiEmitterView(trigger: $confettiState.downloadsTrigger, color: ProcessType.downloads.color)
                    ConfettiEmitterView(trigger: $confettiState.davinciResolveTrigger, color: ProcessType.davinciResolve.color)
                    ConfettiEmitterView(trigger: $confettiState.teamsTrigger, color: ProcessType.teams.color)
                    ConfettiEmitterView(trigger: $confettiState.calendarTrigger, color: ProcessType.calendar.color)
                }
                .padding(.top, 40)  // Position below the notch

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Individual confetti emitter view
struct ConfettiEmitterView: View {
    @Binding var trigger: Int
    let color: Color

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 300, height: 50)
            .confettiCannon(
                counter: $trigger,
                num: 40,
                colors: [color],
                confettiSize: 12,
                rainHeight: 200,
                openingAngle: Angle(degrees: 180),
                closingAngle: Angle(degrees: 360),
                radius: 300
            )
    }
}

/// Controller to manage the notch window visibility
final class NotchWindowController: ObservableObject {
    private var windows: [NSScreen: NotchWindow] = [:]
    private var confettiWindows: [NSScreen: ConfettiWindow] = [:]
    private(set) var isShowing: Bool = false
    private var screenObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var lastProcesses: [ProcessType] = []  // Track last processes to restore after screen changes

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
                confettiWindows[screen]?.close()
                confettiWindows.removeValue(forKey: screen)
            }
        }

        // Add windows for new screens
        for screen in screensToShow {
            if windows[screen] == nil {
                let window = NotchWindow(screen: screen)
                // Don't show window yet - updateWindowSize will show it when processes are set
                // This prevents the window appearing at wrong position initially
                windows[screen] = window

                // Create confetti window for this screen
                let confettiWindow = ConfettiWindow(screen: screen)
                confettiWindow.orderFrontRegardless()
                confettiWindows[screen] = confettiWindow
            }
        }

        // Restore processes to newly created windows (fixes collapse on screen change)
        if !lastProcesses.isEmpty {
            for window in windows.values {
                window.updateProcesses(lastProcesses)
            }
        }
    }

    func update(with processes: [ProcessType]) {
        print("🎛️ WindowController.update called with: \(processes.map { $0.displayName })")
        lastProcesses = processes  // Store for restoring after screen changes
        isShowing = !processes.isEmpty

        for window in windows.values {
            window.updateProcesses(processes)
        }

        // Show/hide confetti windows based on whether there are processes
        for confettiWindow in confettiWindows.values {
            if processes.isEmpty {
                // Delay hiding confetti window to let the confetti animation play (~3 seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    // Only hide if still no processes (a new one might have started)
                    if self?.isShowing == false {
                        confettiWindow.orderOut(nil)
                    }
                }
            } else {
                confettiWindow.orderFrontRegardless()
            }
        }
    }
}
