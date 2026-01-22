//
//  NotchView.swift
//  Notchification
//

import SwiftUI
import ConfettiSwiftUI
import AppKit

// Shared sound instance for completion sound
private let completionSound = NSSound(named: "Glass")

// Pure black color to match the physical notch - using NSColor for accurate color
private let notchBlack = Color(nsColor: .black)

struct NotchView: View {
    @ObservedObject var notchState: NotchState
    @ObservedObject var licenseManager = LicenseManager.shared
    @ObservedObject var styleSettings = StyleSettings.shared
    @ObservedObject var cameraManager = CameraManager.shared  // For checking hasFirstFrame
    @ObservedObject var debugSettings = DebugSettings.shared
    var screenWidth: CGFloat = 1440
    var screenHeight: CGFloat = 900
    var screen: NSScreen? = nil  // The screen this view is displayed on

    // Animation state
    @State private var isExpanded: Bool = false
    @State private var previousProcesses: Set<ProcessType> = []
    @State private var strokeProgress: CGFloat = 0  // For minimal mode stroke drawing
    @State private var waveProgress: CGFloat = 0  // For wave pulse animation (0 to 1 = fills the stroke)
    @State private var waveOpacity: CGFloat = 1.0  // Wave fades out as it sweeps
    @State private var currentWaveIndex: Int = 0  // Which process wave is currently animating
    @State private var previousWaveIndex: Int = -1  // Previous color (shown as background while next animates)
    @State private var isPendingDismiss: Bool = false  // Wait for animation to complete before hiding
    @State private var isCameraHovered: Bool = false  // Track camera hover for frame expansion
    @State private var morningOverviewMouseEntered: Bool = false  // Track if mouse entered morning overview
    @State private var welcomeMessageMouseEntered: Bool = false  // Track if mouse entered welcome message
    @State private var welcomeMessageContentHeight: CGFloat = 200  // Dynamic height for welcome message

    // Confetti is now rendered in a separate ConfettiWindow
    // Triggers are sent to ConfettiState.shared

    // Dimensions (used for normal mode)
    private let notchWidth: CGFloat = 300
    private let notchFrameWidth: CGFloat = 380  // Extra 80 for outward curves
    private let calendarWidth: CGFloat = 340  // Base calendar width
    private let calendarWidthWithAllDay: CGFloat = 380  // Wider when showing "All day" events

    // Real notch dimensions from system APIs (for minimal mode)
    // Uses the screen this view is displayed on
    private var notchInfo: NotchInfo {
        NotchInfo.forScreen(screen)
    }

    // Content dimensions
    // Normal mode dimensions
    private let logoSize: CGFloat = 24
    private let progressBarHeight: CGFloat = 12
    private let horizontalPadding: CGFloat = 20
    private let rowSpacing: CGFloat = 8
    private let topPadding: CGFloat = 38  // Space below physical notch cutout (~34px)

    // Medium mode dimensions (smaller, fits notch width)
    private let mediumLogoSize: CGFloat = 14
    private let mediumProgressBarHeight: CGFloat = 6
    private let mediumHorizontalPadding: CGFloat = 13
    private let mediumRowSpacing: CGFloat = 3
    private let mediumTopPaddingBase: CGFloat = 34

    /// Effective top padding for normal mode - can be reduced based on settings
    private var effectiveTopPadding: CGFloat {
        // Check trim setting based on whether display has notch
        if notchInfo.hasNotch {
            if styleSettings.trimTopOnNotchDisplay {
                // On notch displays, must stay below the notch + small buffer
                return notchInfo.height + 4
            }
        } else {
            if styleSettings.trimTopOnExternalDisplay {
                return 8  // Minimal padding on external display (no notch to avoid)
            }
        }
        return topPadding
    }

    /// Effective top padding for medium mode - can be reduced based on settings
    private var effectiveMediumTopPadding: CGFloat {
        // Check trim setting based on whether display has notch
        if notchInfo.hasNotch {
            if styleSettings.trimTopOnNotchDisplay {
                // On notch displays, must stay below the notch + small buffer
                return notchInfo.height + 4
            }
        } else {
            if styleSettings.trimTopOnExternalDisplay {
                return 8  // Minimal padding on external display (no notch to avoid)
            }
        }
        return mediumTopPaddingBase
    }

    // Minimal mode stroke width (from settings)
    private var minimalStrokeWidth: CGFloat { styleSettings.minimalStrokeWidth }

    // Dynamic height based on number of processes (normal mode)
    private var expandedHeight: CGFloat {
        let processCount = max(1, notchState.activeProcesses.count)
        let contentHeight = CGFloat(processCount) * logoSize + CGFloat(processCount - 1) * rowSpacing
        let trialTextHeight: CGFloat = licenseManager.state == .expired ? 20 : 0
        return effectiveTopPadding + contentHeight + trialTextHeight + 16  // 16 bottom padding
    }

    // Dynamic height for medium mode (smaller, but full camera size)
    private var mediumExpandedHeight: CGFloat {
        let hasTeams = notchState.activeProcesses.contains(.teams)
        let teamsOnly = notchState.activeProcesses == [.teams]
        let cameraHeight: CGFloat = 150  // Same as normal mode

        if teamsOnly {
            // Camera starts below notch, so use notchInfo.height as top offset
            return notchInfo.height + 5 + cameraHeight + 16
        } else if hasTeams {
            let otherCount = notchState.activeProcesses.count - 1
            let otherHeight = CGFloat(otherCount) * mediumLogoSize + CGFloat(max(0, otherCount - 1)) * mediumRowSpacing
            return notchInfo.height + 5 + cameraHeight + 8 + otherHeight + 13
        } else {
            let processCount = max(1, notchState.activeProcesses.count)
            let contentHeight = CGFloat(processCount) * mediumLogoSize + CGFloat(processCount - 1) * mediumRowSpacing
            return effectiveMediumTopPadding + contentHeight + 13  // 13 bottom padding
        }
    }

    /// Base color for minimal mode - first active process color
    private var baseStrokeColor: Color {
        let color = notchState.activeProcesses.first?.color ?? .white
        return styleSettings.grayscaleMode ? color.toGrayscale() : color
    }

    /// Current highlight color based on which process is animating
    /// - Single process: uses the lighter waveColor (like the regular progress bar)
    /// - Multiple processes: cycles through each process's actual color
    private var currentHighlightColor: Color {
        let processes = notchState.activeProcesses
        guard !processes.isEmpty else { return .white }
        let index = currentWaveIndex % processes.count

        // For multiple processes, use actual colors to cycle between them
        // For single process, use the lighter wave color like the regular progress bar
        let color: Color
        if processes.count > 1 {
            color = processes[index].color
        } else {
            color = processes[index].waveColor
        }
        return styleSettings.grayscaleMode ? color.toGrayscale() : color
    }

    /// Whether to show the base stroke layer (only for single process)
    private var showBaseStroke: Bool {
        notchState.activeProcesses.count == 1
    }

    /// Determinate progress from any active process (0.0-1.0), or nil if all are indeterminate
    private var determinateProgress: Double? {
        for process in notchState.activeProcesses {
            if let progress = ProcessMonitor.shared.progress(for: process) {
                return progress
            }
        }
        return nil
    }

    /// Previous highlight color (background layer for multiple processes)
    private var previousHighlightColor: Color {
        let processes = notchState.activeProcesses
        guard !processes.isEmpty, previousWaveIndex >= 0 else { return .clear }
        let index = previousWaveIndex % processes.count
        let color = processes[index].color
        return styleSettings.grayscaleMode ? color.toGrayscale() : color
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Check for welcome message debug mode first
            if debugSettings.showWelcomeMessage {
                welcomeMessageModeView
            // Check for morning overview debug mode
            } else if debugSettings.showMorningOverview {
                morningOverviewModeView
            } else {
                switch styleSettings.notchStyle {
                case .minimal:
                    // MINIMAL MODE: Base stroke + highlight pulses
                    minimalModeView

                case .medium:
                    // MEDIUM MODE: Notch-width with smaller icons and progress bars
                    mediumModeView

                case .normal:
                    // NORMAL MODE: Filled shape with icons and progress bars
                    normalModeView
                }
            }
        }
        // Fill available space and center content horizontally
        // This ensures scaled content (like Teams hover) stays centered in the larger window
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .drawingGroup()  // GPU acceleration for smoother animations
        .onChange(of: notchState.activeProcesses.isEmpty) { _, isEmpty in
            switch styleSettings.notchStyle {
            case .minimal:
                // Minimal mode: animate stroke drawing around the notch
                if isEmpty {
                    isPendingDismiss = true
                    startWaveAnimation()
                } else {
                    isPendingDismiss = false
                    currentWaveIndex = 0
                    previousWaveIndex = -1
                    waveProgress = 0
                    waveOpacity = 1.0
                    strokeProgress = 0
                    // Small delay to let layout stabilize before animating
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                        isExpanded = true
                        withAnimation(.easeInOut(duration: 0.5)) {
                            strokeProgress = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            startWaveAnimation()
                        }
                    }
                }

            case .medium, .normal:
                // Medium and Normal mode: bouncy scale animation
                let animation: Animation = isEmpty
                    ? .easeOut(duration: 0.3)
                    : .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)
                withAnimation(animation) {
                    isExpanded = !isEmpty
                }
            }
        }
        .onChange(of: notchState.activeProcesses) { oldValue, newValue in
            // Check if a process was removed (completed)
            let oldSet = Set(oldValue)
            let newSet = Set(newValue)
            let removed = oldSet.subtracting(newSet)

            // Trigger effects for each removed process
            for removedProcess in removed {
                // Skip confetti/sound for dismissed processes (user clicked X)
                let wasDismissed = ProcessMonitor.shared.dismissedProcesses.contains(removedProcess) ||
                                   notchState.recentlyDismissed.contains(removedProcess)
                if wasDismissed {
                    print("🚫 Skipping confetti for dismissed process: \(removedProcess)")
                    notchState.recentlyDismissed.remove(removedProcess)  // Clear the flag
                    continue
                }

                // Skip confetti/sound for calendar and preview (they're informational, not completions)
                if removedProcess == .calendar || removedProcess == .preview {
                    continue
                }

                // Confetti (if enabled) - triggers in separate ConfettiWindow
                if TrackingSettings.shared.confettiEnabled {
                    ConfettiState.shared.trigger(for: removedProcess)
                    print("🎉 Confetti triggered for \(removedProcess)")
                }

                // Sound (if enabled)
                if TrackingSettings.shared.soundEnabled {
                    // Stop if already playing, then play fresh
                    completionSound?.stop()
                    completionSound?.play()
                }
            }

            previousProcesses = newSet
        }
        .onChange(of: styleSettings.notchStyle) { _, newStyle in
            // Reinitialize animation state when switching modes
            guard !notchState.activeProcesses.isEmpty else { return }

            switch newStyle {
            case .minimal:
                // Initialize minimal mode animation
                isExpanded = true
                strokeProgress = 1  // Start with full stroke for determinate, or animate for indeterminate
                waveProgress = 0
                waveOpacity = 1.0
                currentWaveIndex = 0
                previousWaveIndex = -1
                // Start wave animation if indeterminate
                if determinateProgress == nil || notchState.activeProcesses.count > 1 {
                    startWaveAnimation()
                }
            case .medium, .normal:
                // Initialize medium/normal mode
                isExpanded = true
            }
        }
        .onChange(of: debugSettings.showMorningOverview) { _, showOverview in
            if showOverview {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
                    isExpanded = true
                }
            }
        }
        .onAppear {
            previousProcesses = Set(notchState.activeProcesses)
            if !notchState.activeProcesses.isEmpty {
                if styleSettings.minimalStyle {
                    // Minimal mode: animate stroke drawing
                    isExpanded = true
                    withAnimation(.easeInOut(duration: 0.5)) {
                        strokeProgress = 1
                    }
                    // Start wave animation after stroke completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        startWaveAnimation()
                    }
                } else {
                    // Normal mode: bouncy scale
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
                        isExpanded = true
                    }
                }
            }
        }
    }

    // MARK: - Mode Views

    /// Minimal mode: Just a colored stroke around the notch
    /// Shows camera preview when Teams is active
    @ViewBuilder
    private var minimalModeView: some View {
        let hasTeams = notchState.activeProcesses.contains(.teams)
        let cameraHeight: CGFloat = 150
        let cameraWidth: CGFloat = 280  // Same as normal mode

        ZStack(alignment: .top) {
            // When Teams is active, show expanded background with camera
            if hasTeams {
                MinimalNotchShape(cornerRadius: 16)
                    .fill(notchBlack)
                    .frame(width: cameraWidth + 20, height: notchInfo.height + 5 + cameraHeight + 16)
                    .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)

                // Camera preview - positioned below the notch (only show when first frame ready)
                if cameraManager.hasFirstFrame && !cameraManager.noCameraAvailable {
                    CameraPreviewView(onDismiss: {
                        ProcessMonitor.shared.dismissProcess(.teams)
                        notchState.recentlyDismissed.insert(.teams)
                        notchState.activeProcesses.removeAll { $0 == .teams }
                        CameraManager.shared.stopSession()
                        isCameraHovered = false
                        #if DEBUG
                        NotificationCenter.default.post(name: .teamsMockDismissed, object: nil)
                        #endif
                    }, isHoveredExternal: $isCameraHovered)
                    .frame(
                        width: isCameraHovered ? cameraWidth * CameraPreviewView.scaleFactor : cameraWidth,
                        height: isCameraHovered ? cameraHeight * CameraPreviewView.scaleFactor : cameraHeight
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCameraHovered)
                    .offset(y: notchInfo.height + 5)
                    .opacity(isExpanded ? 1 : 0)
                    .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)
                }
            } else {
                // Normal minimal mode - stroke border around notch
                let cornerRadius: CGFloat = 8
                let debugColors = debugSettings.debugViewColors

                ZStack(alignment: .top) {
                    // DEBUG: Outer frame indicator (bright green) - MUST have frame to avoid filling screen
                    if debugColors {
                        Color.green
                            .frame(width: notchInfo.width + minimalStrokeWidth + 8, height: notchInfo.height + minimalStrokeWidth + 8)
                    }

                    // Fill - the black notch shape
                    MinimalNotchShape(cornerRadius: cornerRadius)
                        .fill(debugColors ? Color.red : notchBlack)
                        .frame(width: notchInfo.width, height: notchInfo.height)

                    // Stroke shapes - SAME frame as fill, stroke extends outward naturally
                    Group {
                        if let progress = determinateProgress, notchState.activeProcesses.count == 1 {
                            // Determinate mode
                            MinimalNotchShape(cornerRadius: cornerRadius)
                                .trim(from: 1 - progress, to: 1)
                                .stroke(debugColors ? Color.yellow : baseStrokeColor, style: StrokeStyle(lineWidth: minimalStrokeWidth, lineCap: .round))
                                .animation(.easeInOut(duration: 0.5), value: progress)
                        } else {
                            // Indeterminate mode
                            if showBaseStroke {
                                MinimalNotchShape(cornerRadius: cornerRadius)
                                    .trim(from: 1 - strokeProgress, to: 1)
                                    .stroke(debugColors ? Color.yellow : baseStrokeColor, style: StrokeStyle(lineWidth: minimalStrokeWidth, lineCap: .round))
                            }

                            if !showBaseStroke && previousWaveIndex >= 0 {
                                MinimalNotchShape(cornerRadius: cornerRadius)
                                    .stroke(debugColors ? Color.orange : previousHighlightColor, style: StrokeStyle(lineWidth: minimalStrokeWidth, lineCap: .round))
                            }

                            if !notchState.activeProcesses.isEmpty {
                                MinimalNotchShape(cornerRadius: cornerRadius)
                                    .trim(from: 1 - waveProgress, to: 1)
                                    .stroke(debugColors ? Color.pink : currentHighlightColor, style: StrokeStyle(lineWidth: minimalStrokeWidth, lineCap: .round))
                                    .opacity(showBaseStroke ? (strokeProgress >= 1 ? waveOpacity : 0) : 1)
                            }
                        }
                    }
                    // Same frame as fill - stroke naturally extends strokeWidth/2 beyond
                    .frame(width: notchInfo.width, height: notchInfo.height)
                }
            }
        }
        // Frame sized to content - stroke extends strokeWidth/2 on each side
        .frame(width: hasTeams ? cameraWidth + 20 : notchInfo.width + minimalStrokeWidth, height: hasTeams ? notchInfo.height + 5 + cameraHeight + 16 : notchInfo.height + minimalStrokeWidth / 2)
        .opacity(isExpanded ? 1 : 0)
    }

    /// Medium mode: Notch-width with smaller icons and progress bars
    @ViewBuilder
    private var mediumModeView: some View {
        let hasTeams = notchState.activeProcesses.contains(.teams)
        let teamsOnly = notchState.activeProcesses == [.teams]
        let cameraHeight: CGFloat = 150
        let cameraWidth: CGFloat = 280  // Same as normal mode
        let debugColors = debugSettings.debugViewColors
        // Calculate expanded dimensions when camera is hovered
        let scaledCameraWidth = cameraWidth * CameraPreviewView.scaleFactor
        let scaledCameraHeight = cameraHeight * CameraPreviewView.scaleFactor
        let expandedWidth = scaledCameraWidth + 20

        MinimalNotchShape(cornerRadius: 16)
            .fill(debugColors ? Color.red : notchBlack)
            .frame(width: hasTeams ? cameraWidth + 20 : notchInfo.width, height: mediumExpandedHeight)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mediumExpandedHeight)
            .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)

        if !notchState.activeProcesses.isEmpty {
            // Use ZStack so camera can float above progress bars when hovered
            ZStack(alignment: .top) {
                // Progress bars layer
                VStack(alignment: .center, spacing: mediumRowSpacing) {
                    // Spacer for camera area when Teams is active
                    if hasTeams && cameraManager.hasFirstFrame && !cameraManager.noCameraAvailable {
                        Color.clear
                            .frame(width: cameraWidth, height: cameraHeight)
                            .padding(.bottom, teamsOnly ? 0 : 8)
                    }

                    // Show other processes (not Teams)
                    ForEach(notchState.activeProcesses.filter { $0 != .teams }) { process in
                        ProcessRow(
                            process: process,
                            isExpanded: isExpanded,
                            logoSize: mediumLogoSize,
                            progressBarHeight: mediumProgressBarHeight,
                            onDismiss: { dismissedProcess in
                                ProcessMonitor.shared.dismissProcess(dismissedProcess)
                                notchState.recentlyDismissed.insert(dismissedProcess)
                                notchState.activeProcesses.removeAll { $0 == dismissedProcess }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.top, hasTeams ? 0 : 4)
                .padding(.bottom, 8)

                // Camera layer (on top) - frame expands when hovered
                if hasTeams && cameraManager.hasFirstFrame && !cameraManager.noCameraAvailable {
                    CameraPreviewView(onDismiss: {
                        ProcessMonitor.shared.dismissProcess(.teams)
                        notchState.recentlyDismissed.insert(.teams)
                        notchState.activeProcesses.removeAll { $0 == .teams }
                        CameraManager.shared.stopSession()
                        isCameraHovered = false
                        #if DEBUG
                        NotificationCenter.default.post(name: .teamsMockDismissed, object: nil)
                        #endif
                    }, isHoveredExternal: $isCameraHovered)
                    .frame(
                        width: isCameraHovered ? scaledCameraWidth : cameraWidth,
                        height: isCameraHovered ? scaledCameraHeight : cameraHeight
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCameraHovered)
                }
            }
            .frame(width: hasTeams ? (isCameraHovered ? expandedWidth : cameraWidth + 20) : notchInfo.width)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCameraHovered)
            .offset(y: hasTeams ? notchInfo.height + 5 : effectiveMediumTopPadding)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: notchState.activeProcesses.count)
        }
    }

    /// Normal mode: Full size with icons and progress bars
    /// Shows camera preview when Teams is active
    @ViewBuilder
    private var normalModeView: some View {
        // Check if only Teams is active - show camera-only view
        let teamsOnly = notchState.activeProcesses == [.teams]
        let hasTeams = notchState.activeProcesses.contains(.teams)
        let cameraHeight: CGFloat = 150
        let cameraWidth: CGFloat = notchWidth - 20  // Fill notch width with small padding
        let debugColors = debugSettings.debugViewColors
        // Calculate expanded dimensions when camera is hovered
        let scaledCameraWidth = cameraWidth * CameraPreviewView.scaleFactor
        let scaledCameraHeight = cameraHeight * CameraPreviewView.scaleFactor
        let expandedWidth = scaledCameraWidth + 20

        // Calculate height: if teams is active, include camera height
        let teamsExpandedHeight: CGFloat = {
            if teamsOnly {
                return effectiveTopPadding + cameraHeight + 16  // No extra padding when Teams only
            } else if hasTeams {
                // Camera + other processes (add spacing between camera and bars)
                let otherCount = notchState.activeProcesses.count - 1
                let otherHeight = CGFloat(otherCount) * logoSize + CGFloat(max(0, otherCount - 1)) * rowSpacing
                return effectiveTopPadding + cameraHeight + 8 + otherHeight + 16  // 8px between camera and bars
            } else {
                return expandedHeight
            }
        }()

        NotchShape()
            .fill(debugColors ? Color.red : notchBlack)
            .frame(width: notchWidth, height: teamsExpandedHeight)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: teamsExpandedHeight)
            .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)

        if !notchState.activeProcesses.isEmpty {
            // Use ZStack so camera can float above progress bars when hovered
            ZStack(alignment: .top) {
                // Progress bars layer
                VStack(alignment: .center, spacing: rowSpacing) {
                    // Spacer for camera area when Teams is active
                    if hasTeams && cameraManager.hasFirstFrame && !cameraManager.noCameraAvailable {
                        Color.clear
                            .frame(width: cameraWidth, height: cameraHeight)
                            .padding(.bottom, teamsOnly ? 0 : 8)
                    }

                    // Show other processes (not Teams)
                    ForEach(notchState.activeProcesses.filter { $0 != .teams }) { process in
                        ProcessRow(
                            process: process,
                            isExpanded: isExpanded,
                            logoSize: logoSize,
                            progressBarHeight: progressBarHeight,
                            onDismiss: { dismissedProcess in
                                ProcessMonitor.shared.dismissProcess(dismissedProcess)
                                notchState.recentlyDismissed.insert(dismissedProcess)
                                notchState.activeProcesses.removeAll { $0 == dismissedProcess }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if licenseManager.state == .expired {
                        Text("Thanks for trying! Please upgrade")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }

                // Camera layer (on top) - frame expands when hovered
                if hasTeams && cameraManager.hasFirstFrame && !cameraManager.noCameraAvailable {
                    CameraPreviewView(onDismiss: {
                        ProcessMonitor.shared.dismissProcess(.teams)
                        notchState.recentlyDismissed.insert(.teams)
                        notchState.activeProcesses.removeAll { $0 == .teams }
                        CameraManager.shared.stopSession()
                        isCameraHovered = false
                        #if DEBUG
                        NotificationCenter.default.post(name: .teamsMockDismissed, object: nil)
                        #endif
                    }, isHoveredExternal: $isCameraHovered)
                    .frame(
                        width: isCameraHovered ? scaledCameraWidth : cameraWidth,
                        height: isCameraHovered ? scaledCameraHeight : cameraHeight
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCameraHovered)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(width: hasTeams ? (isCameraHovered ? expandedWidth : notchWidth) : notchWidth)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCameraHovered)
            .offset(y: effectiveTopPadding)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: notchState.activeProcesses.count)
        }
    }

    // MARK: - Welcome Message Mode

    /// Welcome message mode: Shows the CEO's "What's New" message
    /// Uses the same NotchShape as normal mode - just with different height
    @ViewBuilder
    private var welcomeMessageModeView: some View {
        let message = WelcomeMessage.current
        let debugColors = debugSettings.debugViewColors
        let contentWidth: CGFloat = 340

        // NotchShape background - uses dynamic height
        NotchShape()
            .fill(debugColors ? Color.red : notchBlack)
            .frame(width: contentWidth + 40, height: effectiveTopPadding + welcomeMessageContentHeight)
            .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)

        // Content positioned below the physical notch
        WelcomeMessageContent(
            message: message,
            onDismiss: {
                WelcomeMessageManager.shared.markAsSeen()
                DebugSettings.shared.showWelcomeMessage = false
            }
        )
        .frame(width: contentWidth)
        .padding(.horizontal, 20)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: WelcomeMessageHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(WelcomeMessageHeightKey.self) { height in
            welcomeMessageContentHeight = height
        }
        .offset(y: effectiveTopPadding)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)
        .onHover { hovering in
            if hovering {
                welcomeMessageMouseEntered = true
            } else if welcomeMessageMouseEntered {
                // Mouse left after having entered - dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    WelcomeMessageManager.shared.markAsSeen()
                    DebugSettings.shared.showWelcomeMessage = false
                    welcomeMessageMouseEntered = false
                }
            }
        }
    }

    // MARK: - Morning Overview Mode

    /// Morning overview mode: Shows today's calendar with all-day events and meetings
    /// Uses the same NotchShape as normal mode - just with different height
    @ViewBuilder
    private var morningOverviewModeView: some View {
        let data = ProcessMonitor.shared.getMorningOverviewData()
        let debugColors = debugSettings.debugViewColors

        // Calculate height based on content
        // All-day events: ~20pt each (single line + padding)
        // Timed events: ~32pt each (two lines: 14pt + 2pt spacing + 12pt)
        // Spacing between items: 14pt
        // Separator: 1pt + spacing
        let allDayCount = data.allDayEvents.count
        let timedCount = data.timedEvents.count
        let hasAllDay = allDayCount > 0

        // Use wider width when there are all-day events (to fit "All day" label)
        let effectiveCalendarWidth = hasAllDay ? calendarWidthWithAllDay : calendarWidth

        let allDayHeight = CGFloat(allDayCount) * 20
        let timedHeight = CGFloat(timedCount) * 32
        let allDaySpacing = allDayCount > 1 ? CGFloat(allDayCount - 1) * 14 : 0
        let timedSpacing = timedCount > 1 ? CGFloat(timedCount - 1) * 14 : 0
        let separatorHeight: CGFloat = (allDayCount > 0 && timedCount > 0) ? 12 : 0  // 1pt line + spacing
        let emptyHeight: CGFloat = data.isEmpty ? 30 : 0  // "No events today" message
        let bottomPadding: CGFloat = 30  // Bottom padding
        let contentHeight = allDayHeight + allDaySpacing + separatorHeight + timedHeight + timedSpacing + emptyHeight + bottomPadding
        let calendarExpandedHeight = effectiveTopPadding + contentHeight

        // NotchShape background - wider when showing all-day events
        NotchShape()
            .fill(debugColors ? Color.red : notchBlack)
            .frame(width: effectiveCalendarWidth, height: calendarExpandedHeight)
            .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)

        // Content positioned below the physical notch
        MorningOverviewContent(
            data: data,
            onDismiss: {
                DebugSettings.shared.showMorningOverview = false
                DebugSettings.shared.useMockCalendarData = false
            }
        )
        .frame(width: effectiveCalendarWidth - 40)  // Content width with padding
        .padding(.horizontal, 20)
        .offset(y: effectiveTopPadding)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(x: isExpanded ? 1 : 0.3, y: isExpanded ? 1 : 0, anchor: .top)
        .onHover { hovering in
            if hovering {
                // Mouse entered the calendar area
                morningOverviewMouseEntered = true
            } else if morningOverviewMouseEntered {
                // Mouse left after having entered - dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    DebugSettings.shared.showMorningOverview = false
                    DebugSettings.shared.useMockCalendarData = false
                    morningOverviewMouseEntered = false
                }
            }
        }
    }

    /// Starts the highlight animation that cycles through active process colors
    /// - Single process: highlight sweeps and fades out (like AnimatedProgressBar)
    /// - Multiple processes: each color sweeps around fully, then next color starts
    private func startWaveAnimation() {
        guard isExpanded && styleSettings.minimalStyle else { return }
        guard !notchState.activeProcesses.isEmpty else { return }

        let isSingleProcess = notchState.activeProcesses.count == 1

        // If pending dismiss, complete the current wave and then hide
        if isPendingDismiss {
            // Animate wave to completion (full stroke)
            withAnimation(.easeInOut(duration: 1.0)) {
                waveProgress = 1.0
                if isSingleProcess {
                    waveOpacity = 0.0
                }
            }
            // After wave completes, fade out the whole thing and reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isExpanded = false
                }
                // Reset state after hiding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    strokeProgress = 0
                    waveProgress = 0
                    waveOpacity = 1.0
                    currentWaveIndex = 0
                    previousWaveIndex = -1
                    isPendingDismiss = false
                }
            }
            return
        }

        // Reset wave for new animation cycle (instant reset)
        // For multiple processes, waveProgress is reset in the dispatch callback
        if isSingleProcess {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                waveProgress = 0
                waveOpacity = 1.0
            }
        }

        // Animate wave sweeping around the notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if isSingleProcess {
                // Single process: sweep and fade out
                withAnimation(.easeInOut(duration: 3.0)) {
                    waveProgress = 1.0
                    waveOpacity = 0.0
                }
                // Restart after a pause
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    startWaveAnimation()
                }
            } else {
                // Multiple processes: sweep fully, then switch to next color
                withAnimation(.easeInOut(duration: 2.0)) {
                    waveProgress = 1.0
                }
                // Move to next process color and restart
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // Save current as previous (for background layer)
                    previousWaveIndex = currentWaveIndex
                    // Move to next color
                    currentWaveIndex += 1
                    // Reset progress instantly (previous color stays visible as background)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        waveProgress = 0
                    }
                    // Start new animation
                    startWaveAnimation()
                }
            }
        }
    }
}

// MARK: - Process Row (with hover dismiss)

struct ProcessRow: View {
    let process: ProcessType
    let isExpanded: Bool
    let logoSize: CGFloat
    let progressBarHeight: CGFloat
    var onDismiss: ((ProcessType) -> Void)?

    @ObservedObject private var processMonitor = ProcessMonitor.shared
    @ObservedObject private var styleSettings = StyleSettings.shared
    @State private var isHovering: Bool = false

    /// The process color, converted to grayscale if grayscale mode is enabled
    private var effectiveColor: Color {
        styleSettings.grayscaleMode ? process.color.toGrayscale() : process.color
    }

    /// The process wave color, converted to grayscale if grayscale mode is enabled
    private var effectiveWaveColor: Color {
        styleSettings.grayscaleMode ? process.waveColor.toGrayscale() : process.waveColor
    }

    /// Get progress for processes that support it (reactive via processMonitor observation)
    private var progress: Double? {
        processMonitor.progress(for: process)
    }

    /// Get calendar event info if this is a calendar process
    private var calendarEvent: CalendarEventInfo? {
        processMonitor.calendarEventInfo()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Show X icon on hover, otherwise show logo
            ZStack {
                if isHovering {
                    Image(systemName: "xmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .fontWeight(.bold)
                        .foregroundColor(effectiveColor)
                        .padding(1)
                } else {
                    ProcessLogo(processType: process, color: effectiveColor)
                }
            }
            .frame(width: logoSize, height: logoSize)

            // Calendar gets special treatment - show event info
            if process == .calendar {
                calendarContent
            } else if let progress = progress {
                // Show percentage text for determinate progress
                let displayPercent = min(99, Int(progress * 100))

                HStack(spacing: 2) {
                    AnimatedProgressBar(
                        isActive: isExpanded,
                        baseColor: effectiveColor,
                        waveColor: effectiveWaveColor,
                        progress: progress
                    )
                    .frame(height: progressBarHeight)

                    Text("\(displayPercent)")
                        .font(.system(size: max(11, progressBarHeight * 1.8), weight: .bold, design: .monospaced))
                        .foregroundColor(effectiveColor)
                        .fixedSize()
                }
            } else {
                AnimatedProgressBar(
                    isActive: isExpanded,
                    baseColor: effectiveColor,
                    waveColor: effectiveWaveColor,
                    progress: progress
                )
                .frame(height: progressBarHeight)
            }
        }
        .padding(.trailing, 4)
        .contentShape(Rectangle())  // Make entire row tappable
        .onTapGesture {
            onDismiss?(process)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    /// Calendar-specific content: shows countdown to meeting
    @ViewBuilder
    private var calendarContent: some View {
        if let event = calendarEvent {
            // Show countdown and animated progress bar
            HStack(spacing: 4) {
                AnimatedProgressBar(
                    isActive: isExpanded,
                    baseColor: effectiveColor,
                    waveColor: effectiveWaveColor,
                    progress: nil
                )
                .frame(height: progressBarHeight)

                // Time countdown (e.g., "15m", "1h")
                Text(event.formattedTimeUntil)
                    .font(.system(size: max(11, progressBarHeight * 1.8), weight: .bold, design: .monospaced))
                    .foregroundColor(effectiveColor)
                    .fixedSize()
            }
        } else {
            // Fallback - just show animated progress bar
            AnimatedProgressBar(
                isActive: isExpanded,
                baseColor: effectiveColor,
                waveColor: effectiveWaveColor,
                progress: nil
            )
            .frame(height: progressBarHeight)
        }
    }
}

// MARK: - Process Logo

struct ProcessLogo: View {
    let processType: ProcessType
    var color: Color? = nil  // Optional override color (for grayscale mode)

    /// The effective color to use - override if provided, otherwise process default
    private var effectiveColor: Color {
        color ?? processType.color
    }

    var body: some View {
        switch processType {
        case .claudeCode, .claudeApp:
            ClaudeLogo(color: effectiveColor)
        case .androidStudio:
            AndroidStudioLogo(color: effectiveColor)
        case .xcode:
            XcodeLogo(color: effectiveColor)
        case .finder:
            FinderLogo(color: effectiveColor)
        case .opencode:
            OpencodeLogo(color: effectiveColor)
        case .codex:
            CodexLogo(color: effectiveColor)
        case .dropbox:
            DropboxLogo(color: effectiveColor)
        case .googleDrive:
            GoogleDriveLogo(color: effectiveColor)
        case .oneDrive:
            OneDriveLogo(color: effectiveColor)
        case .icloud:
            iCloudLogo(color: effectiveColor)
        case .installer:
            InstallerLogo(color: effectiveColor)
        case .appStore:
            AppStoreLogo(color: effectiveColor)
        case .automator:
            AutomatorLogo(color: effectiveColor)
        case .scriptEditor:
            ScriptEditorLogo(color: effectiveColor)
        case .downloads:
            DownloadsLogo(color: effectiveColor)
        case .davinciResolve:
            DaVinciResolveLogo(color: effectiveColor)
        case .teams:
            TeamsLogo(color: effectiveColor)
        case .calendar:
            CalendarLogo(color: effectiveColor)
        case .preview:
            PreviewLogo()
        }
    }
}

// MARK: - Calendar Logo

struct CalendarLogo: View {
    var color: Color = ProcessType.calendar.color

    var body: some View {
        Image(systemName: "calendar")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fontWeight(.medium)
            .foregroundColor(color)
    }
}

// MARK: - Preview Logo (Settings preview 'X')

struct PreviewLogo: View {
    var body: some View {
        Image(systemName: "xmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fontWeight(.bold)
            .foregroundColor(.gray)
            .padding(2)
    }
}

// MARK: - Teams Logo

struct TeamsLogo: View {
    var color: Color = .white

    var body: some View {
        Image(systemName: "video.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.monochrome)
            .foregroundColor(color)
    }
}

// MARK: - DaVinci Resolve Logo

struct DaVinciResolveLogo: View {
    var color: Color = ProcessType.davinciResolve.color

    var body: some View {
        Image("davinciresolve")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Downloads Logo

struct DownloadsLogo: View {
    var color: Color = ProcessType.downloads.color

    var body: some View {
        Image(systemName: "arrow.down")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fontWeight(.bold)
            .foregroundColor(color)
    }
}

// MARK: - Android Studio Logo

struct AndroidStudioLogo: View {
    var color: Color = ProcessType.androidStudio.color

    var body: some View {
        AndroidStudioLogoShape()
            .fill(color)
    }
}

struct AndroidStudioLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 32.0
        var path = Path()

        path.move(to: p(13.8, 4, s))
        path.addLine(to: p(18.3, 4, s))
        path.addLine(to: p(18.3, 6.2, s))
        path.addLine(to: p(19.5, 6.2, s))
        path.addCurve(to: p(20.5, 7.2, s), control1: p(20.1, 6.2, s), control2: p(20.5, 6.6, s))
        path.addLine(to: p(20.5, 11.8, s))
        path.addLine(to: p(19.9, 12.6, s))
        path.addLine(to: p(26.1, 23.4, s))
        path.addLine(to: p(27, 27.3, s))
        path.addCurve(to: p(26.1, 27.8, s), control1: p(27.1, 27.8, s), control2: p(26.5, 28.2, s))
        path.addLine(to: p(23.2, 25.1, s))
        path.addLine(to: p(21.2, 21.6, s))
        path.addCurve(to: p(16, 23, s), control1: p(19.6, 22.5, s), control2: p(17.9, 23, s))
        path.addCurve(to: p(10.9, 21.6, s), control1: p(14.1, 23, s), control2: p(12.4, 22.5, s))
        path.addLine(to: p(8.9, 25.1, s))
        path.addLine(to: p(6, 27.8, s))
        path.addCurve(to: p(5.1, 27.3, s), control1: p(5.6, 28.2, s), control2: p(5, 27.8, s))
        path.addLine(to: p(6, 23.4, s))
        path.addLine(to: p(8.3, 19.3, s))
        path.addCurve(to: p(6, 12.9, s), control1: p(6.8, 17.6, s), control2: p(6, 15.3, s))
        path.addCurve(to: p(6.1, 11.8, s), control1: p(6, 12.5, s), control2: p(6, 12.1, s))
        path.addLine(to: p(9.1, 11.8, s))
        path.addCurve(to: p(9, 12.9, s), control1: p(9, 12.2, s), control2: p(9, 12.5, s))
        path.addCurve(to: p(10, 16.5, s), control1: p(9, 14.2, s), control2: p(9.4, 15.4, s))
        path.addLine(to: p(12.3, 12.6, s))
        path.addLine(to: p(11.7, 11.8, s))
        path.addLine(to: p(11.7, 7.2, s))
        path.addCurve(to: p(12.7, 6.2, s), control1: p(11.7, 6.6, s), control2: p(12.1, 6.2, s))
        path.addLine(to: p(13.9, 6.2, s))
        path.closeSubpath()

        // Inner details
        path.move(to: p(14.4, 15.4, s))
        path.addLine(to: p(12.4, 19, s))
        path.addCurve(to: p(16, 20, s), control1: p(13.5, 19.6, s), control2: p(14.7, 20, s))
        path.addCurve(to: p(19.6, 19, s), control1: p(17.3, 20, s), control2: p(18.6, 19.6, s))
        path.addLine(to: p(17.5, 15.4, s))
        path.addLine(to: p(16.7, 16.4, s))
        path.addCurve(to: p(15.1, 16.4, s), control1: p(16.3, 16.9, s), control2: p(15.5, 16.9, s))
        path.closeSubpath()

        // Eye area
        path.move(to: p(14.1, 11.8, s))
        path.addCurve(to: p(16, 12.9, s), control1: p(14.5, 12.5, s), control2: p(15.2, 12.9, s))
        path.addCurve(to: p(17.9, 11.8, s), control1: p(16.8, 12.9, s), control2: p(17.5, 12.5, s))
        path.addCurve(to: p(18.2, 10.7, s), control1: p(18.1, 11.5, s), control2: p(18.2, 11.1, s))
        path.addCurve(to: p(16, 8.5, s), control1: p(18.2, 9.5, s), control2: p(17.2, 8.5, s))
        path.addCurve(to: p(13.8, 10.7, s), control1: p(14.8, 8.5, s), control2: p(13.8, 9.5, s))
        path.addCurve(to: p(14.1, 11.8, s), control1: p(13.8, 11.1, s), control2: p(13.9, 11.5, s))
        path.closeSubpath()

        let bounds = path.boundingRect
        let xOffset = (rect.width - bounds.width) / 2 - bounds.minX
        let yOffset = (rect.height - bounds.height) / 2 - bounds.minY
        return path.offsetBy(dx: xOffset, dy: yOffset)
    }

    private func p(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }
}

// MARK: - Xcode Logo

struct XcodeLogo: View {
    var color: Color = ProcessType.xcode.color

    var body: some View {
        XcodeLogoShape()
            .fill(color)
    }
}

struct XcodeLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var path = Path()

        path.move(to: p(20, 4.8, s))
        path.addCurve(to: p(20.9, 4.4, s), control1: p(20.4, 4.6, s), control2: p(20.6, 4.4, s))
        path.addCurve(to: p(21.8, 4.9, s), control1: p(21.4, 4.4, s), control2: p(21.6, 4.7, s))
        path.addCurve(to: p(23, 5.4, s), control1: p(22, 5.2, s), control2: p(22.7, 5.4, s))
        path.addCurve(to: p(23.7, 4.1, s), control1: p(23.2, 5.4, s), control2: p(23.5, 4.7, s))
        path.addCurve(to: p(23.8, 2.7, s), control1: p(23.9, 3.5, s), control2: p(23.9, 2.8, s))
        path.addCurve(to: p(22.7, 2.4, s), control1: p(23.7, 2.6, s), control2: p(22.9, 2.4, s))
        path.addCurve(to: p(22, 2.6, s), control1: p(22.6, 2.5, s), control2: p(22.4, 2.6, s))
        path.addCurve(to: p(20.9, 2, s), control1: p(21.6, 2.6, s), control2: p(21.2, 2.3, s))
        path.addCurve(to: p(19.2, 1.1, s), control1: p(20.4, 1.5, s), control2: p(19.8, 1.3, s))
        path.addCurve(to: p(17.3, 0.9, s), control1: p(18.6, 0.9, s), control2: p(17.9, 0.9, s))
        path.addCurve(to: p(14.5, 1.1, s), control1: p(16.4, 0.8, s), control2: p(15.4, 0.8, s))
        path.addCurve(to: p(13.4, 1.5, s), control1: p(14.1, 1.2, s), control2: p(13.8, 1.4, s))
        path.addCurve(to: p(12.9, 1.7, s), control1: p(13.3, 1.6, s), control2: p(13, 1.7, s))
        path.addCurve(to: p(12.9, 1.9, s), control1: p(12.8, 1.8, s), control2: p(12.8, 1.9, s))
        path.addLine(to: p(13.4, 1.8, s))
        path.addCurve(to: p(12.9, 2.2, s), control1: p(13.4, 1.8, s), control2: p(12.9, 2, s))
        path.addLine(to: p(13, 2.3, s))
        path.addCurve(to: p(13.5, 2.2, s), control1: p(13, 2.3, s), control2: p(13.3, 2.2, s))
        path.addCurve(to: p(15, 2, s), control1: p(13.9, 2.2, s), control2: p(14.5, 2, s))
        path.addCurve(to: p(16.8, 2.8, s), control1: p(15.6, 2, s), control2: p(16.2, 2.2, s))
        path.addCurve(to: p(17.6, 5.6, s), control1: p(17.7, 3.9, s), control2: p(17.6, 5.3, s))
        path.addCurve(to: p(12.5, 21.4, s), control1: p(17.4, 7.7, s), control2: p(12.7, 20.5, s))
        path.addCurve(to: p(13.4, 23.1, s), control1: p(12.3, 22.3, s), control2: p(12.3, 23.1, s))
        path.addCurve(to: p(15.1, 22.7, s), control1: p(14.5, 23.4, s), control2: p(14.9, 23.1, s))
        path.addCurve(to: p(20, 4.8, s), control1: p(15.2, 22, s), control2: p(18.2, 6.2, s))
        path.closeSubpath()

        path.move(to: p(16.1, 3.8, s))
        path.addLine(to: p(0, 6.3, s))
        path.addLine(to: p(2.6, 23, s))
        path.addLine(to: p(11.2, 21.6, s))
        path.addCurve(to: p(13.8, 13.8, s), control1: p(11.1, 20.9, s), control2: p(13.4, 15.1, s))
        path.addLine(to: p(9.4, 14.5, s))
        path.addLine(to: p(10, 12.7, s))
        path.addLine(to: p(13.1, 12.2, s))
        path.addLine(to: p(13.9, 13.2, s))
        path.addCurve(to: p(14.1, 12.5, s), control1: p(14.1, 12.7, s), control2: p(14.1, 12.5, s))
        path.addLine(to: p(9.8, 7.2, s))
        path.addCurve(to: p(9.9, 6.3, s), control1: p(9.6, 6.9, s), control2: p(9.6, 6.5, s))
        path.addLine(to: p(10.1, 6.1, s))
        path.addCurve(to: p(11, 6.2, s), control1: p(10.4, 5.9, s), control2: p(10.8, 5.9, s))
        path.addLine(to: p(14.8, 10.6, s))
        path.addCurve(to: p(16.3, 5.4, s), control1: p(15.6, 8.2, s), control2: p(16.3, 6.1, s))
        path.addCurve(to: p(16.1, 3.8, s), control1: p(16.4, 5.2, s), control2: p(16.4, 4.5, s))
        path.closeSubpath()

        path.move(to: p(4.1, 13.7, s))
        path.addLine(to: p(6.8, 13.2, s))
        path.addLine(to: p(6.1, 15, s))
        path.addLine(to: p(4.3, 15.3, s))
        path.closeSubpath()

        path.move(to: p(9.9, 8.6, s))
        path.addLine(to: p(10.2, 8.7, s))
        path.addCurve(to: p(10.6, 9.6, s), control1: p(10.6, 8.8, s), control2: p(10.7, 9.1, s))
        path.addLine(to: p(7.6, 17.6, s))
        path.addLine(to: p(5.8, 20, s))
        path.addLine(to: p(6, 17, s))
        path.addLine(to: p(9, 9, s))
        path.addCurve(to: p(9.9, 8.6, s), control1: p(9.1, 8.6, s), control2: p(9.5, 8.4, s))
        path.closeSubpath()

        path.move(to: p(20.7, 5.8, s))
        path.addCurve(to: p(18.8, 11.3, s), control1: p(20.3, 6.2, s), control2: p(19.8, 7.5, s))
        path.addLine(to: p(18.9, 11.3, s))
        path.addLine(to: p(19.2, 12.9, s))
        path.addLine(to: p(18.4, 13, s))
        path.addCurve(to: p(18, 14.6, s), control1: p(18.3, 13.5, s), control2: p(18.2, 14, s))
        path.addCurve(to: p(18.7, 17.7, s), control1: p(19.7, 15.5, s), control2: p(18.8, 17.7, s))
        path.addLine(to: p(18.6, 17.6, s))
        path.addCurve(to: p(18.4, 17.1, s), control1: p(18.6, 17.6, s), control2: p(18.7, 17.2, s))
        path.addCurve(to: p(17.5, 16.7, s), control1: p(18.2, 17, s), control2: p(17.8, 16.9, s))
        path.addCurve(to: p(16.6, 20.8, s), control1: p(17.2, 17.9, s), control2: p(16.9, 19.3, s))
        path.addLine(to: p(22.9, 19.8, s))
        path.addLine(to: p(20.8, 5.7, s))
        path.closeSubpath()

        let bounds = path.boundingRect
        let xOffset = (rect.width - bounds.width) / 2 - bounds.minX
        let yOffset = (rect.height - bounds.height) / 2 - bounds.minY
        return path.offsetBy(dx: xOffset, dy: yOffset)
    }

    private func p(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }
}

// MARK: - Finder Logo

struct FinderLogo: View {
    var color: Color = ProcessType.finder.color

    var body: some View {
        Image("findericon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Opencode Logo

struct OpencodeLogo: View {
    var color: Color = ProcessType.opencode.color

    var body: some View {
        Image("opencodeicon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Codex Logo

struct CodexLogo: View {
    var color: Color = ProcessType.codex.color

    var body: some View {
        Image("codexicon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Dropbox Logo

struct DropboxLogo: View {
    var color: Color = ProcessType.dropbox.color

    var body: some View {
        Image("dropboxicon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Google Drive Logo

struct GoogleDriveLogo: View {
    var color: Color = ProcessType.googleDrive.color

    var body: some View {
        Image(systemName: "externaldrive.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - OneDrive Logo

struct OneDriveLogo: View {
    var color: Color = ProcessType.oneDrive.color

    var body: some View {
        Image(systemName: "cloud.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - iCloud Logo

struct iCloudLogo: View {
    var color: Color = ProcessType.icloud.color

    var body: some View {
        Image("icloudlogo")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Installer Logo

struct InstallerLogo: View {
    var color: Color = ProcessType.installer.color

    var body: some View {
        // Package/box icon using SF Symbol
        Image(systemName: "shippingbox.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - App Store Logo

struct AppStoreLogo: View {
    var color: Color = ProcessType.appStore.color

    var body: some View {
        Image("appstoreicon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

// MARK: - Automator Logo

struct AutomatorLogo: View {
    var color: Color = ProcessType.automator.color

    var body: some View {
        Text("A")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(color)
    }
}

// MARK: - Script Editor Logo

struct ScriptEditorLogo: View {
    var color: Color = .white

    var body: some View {
        Image("codeicon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
    }
}

struct FrigginAppStoreIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var path = Path()

        // The "A" document shape (without the hammer)
        path.move(to: p(16.1, 3.8, s))
        path.addLine(to: p(0, 6.3, s))
        path.addLine(to: p(2.6, 23, s))
        path.addLine(to: p(11.2, 21.6, s))
        path.addCurve(to: p(13.8, 13.8, s), control1: p(11.1, 20.9, s), control2: p(13.4, 15.1, s))
        path.addLine(to: p(9.4, 14.5, s))
        path.addLine(to: p(10, 12.7, s))
        path.addLine(to: p(13.1, 12.2, s))
        path.addLine(to: p(13.9, 13.2, s))
        path.addCurve(to: p(14.1, 12.5, s), control1: p(14.1, 12.7, s), control2: p(14.1, 12.5, s))
        path.addLine(to: p(9.8, 7.2, s))
        path.addCurve(to: p(9.9, 6.3, s), control1: p(9.6, 6.9, s), control2: p(9.6, 6.5, s))
        path.addLine(to: p(10.1, 6.1, s))
        path.addCurve(to: p(11, 6.2, s), control1: p(10.4, 5.9, s), control2: p(10.8, 5.9, s))
        path.addLine(to: p(14.8, 10.6, s))
        path.addCurve(to: p(16.3, 5.4, s), control1: p(15.6, 8.2, s), control2: p(16.3, 6.1, s))
        path.addCurve(to: p(16.1, 3.8, s), control1: p(16.4, 5.2, s), control2: p(16.4, 4.5, s))
        path.closeSubpath()

        // Small detail inside
        path.move(to: p(4.1, 13.7, s))
        path.addLine(to: p(6.8, 13.2, s))
        path.addLine(to: p(6.1, 15, s))
        path.addLine(to: p(4.3, 15.3, s))
        path.closeSubpath()

        // Another detail
        path.move(to: p(9.9, 8.6, s))
        path.addLine(to: p(10.2, 8.7, s))
        path.addCurve(to: p(10.6, 9.6, s), control1: p(10.6, 8.8, s), control2: p(10.7, 9.1, s))
        path.addLine(to: p(7.6, 17.6, s))
        path.addLine(to: p(5.8, 20, s))
        path.addLine(to: p(6, 17, s))
        path.addLine(to: p(9, 9, s))
        path.addCurve(to: p(9.9, 8.6, s), control1: p(9.1, 8.6, s), control2: p(9.5, 8.4, s))
        path.closeSubpath()

        let bounds = path.boundingRect
        let xOffset = (rect.width - bounds.width) / 2 - bounds.minX
        let yOffset = (rect.height - bounds.height) / 2 - bounds.minY
        return path.offsetBy(dx: xOffset, dy: yOffset)
    }

    private func p(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }
}

// MARK: - Animated Progress Bar

struct AnimatedProgressBar: View {
    let isActive: Bool
    var baseColor: Color = Color(red: 0.85, green: 0.47, blue: 0.34)
    var waveColor: Color = Color(red: 0.95, green: 0.60, blue: 0.48)
    /// Optional determinate progress (0.0 to 1.0). If nil, shows indeterminate animation.
    var progress: Double? = nil

    @State private var baseWidth: CGFloat = 0
    @State private var waveWidth: CGFloat = 0
    @State private var waveOpacity: CGFloat = 1.0

    private let animationDuration: Double = 3.0

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let totalWidth = geometry.size.width

            if let progress = progress {
                // Determinate progress bar with percentage label
                determinateProgressView(progress: progress, width: totalWidth, height: height)
            } else {
                // Indeterminate animated progress bar
                indeterminateProgressView(width: totalWidth, height: height)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func determinateProgressView(progress: Double, width: CGFloat, height: CGFloat) -> some View {
        let fillWidth = max(height, min(width, width * progress))

        // Simple progress fill bar (text is rendered separately in ProcessRow)
        Capsule()
            .fill(baseColor)
            .frame(width: fillWidth, height: height)
            .animation(.easeInOut(duration: 0.5), value: progress)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func indeterminateProgressView(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Base layer (solid, stays filled)
            Capsule()
                .fill(baseColor)
                .frame(width: baseWidth, height: height)

            // Wave layer (sweeps across and fades out)
            Capsule()
                .fill(waveColor)
                .frame(width: waveWidth, height: height)
                .opacity(waveOpacity)
        }
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation(width: width)
            } else {
                stopAnimation()
            }
        }
        .onAppear {
            if isActive {
                startAnimation(width: width)
            }
        }
    }

    private func startAnimation(width: CGFloat) {
        // Reset
        baseWidth = 0
        waveWidth = 0
        waveOpacity = 1.0

        // Animate base to full
        withAnimation(.easeOut(duration: animationDuration)) {
            baseWidth = width
        }

        // Start wave loop after base fills
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            self.startWaveLoop(width: width)
        }
    }

    private func startWaveLoop(width: CGFloat) {
        guard isActive, progress == nil else { return }

        // Reset wave instantly (no animation)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            waveWidth = 0
            waveOpacity = 1.0
        }

        // Small delay to let reset apply, then animate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard self.isActive, self.progress == nil else { return }

            // Animate wave: sweep across while fading out
            withAnimation(.easeInOut(duration: self.animationDuration)) {
                self.waveWidth = width
                self.waveOpacity = 0.0  // Fade to fully invisible
            }

            // Schedule next wave with 1 second pause
            DispatchQueue.main.asyncAfter(deadline: .now() + self.animationDuration + 1.0) {
                self.startWaveLoop(width: width)
            }
        }
    }

    private func stopAnimation() {
        // Reset instantly - parent handles the fade/scale animation
        // Using Transaction to avoid conflicting with parent's animation
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            baseWidth = 0
            waveWidth = 0
            waveOpacity = 1.0
        }
    }
}

// MARK: - Claude Logo Shape

struct ClaudeLogo: View {
    var color: Color = ProcessType.claudeCode.color

    var body: some View {
        ClaudeLogoShape()
            .fill(color)
    }
}

struct ClaudeLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        return createClaudePath(in: rect)
    }

    private func createClaudePath(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var path = Path()

        path.move(to: p(4.709, 15.955, s))
        path.addLine(to: p(9.429, 13.308, s))
        path.addLine(to: p(9.509, 13.078, s))
        path.addLine(to: p(9.429, 12.95, s))
        path.addLine(to: p(9.2, 12.95, s))
        path.addLine(to: p(8.41, 12.902, s))
        path.addLine(to: p(5.712, 12.829, s))
        path.addLine(to: p(3.373, 12.732, s))
        path.addLine(to: p(1.107, 12.61, s))
        path.addLine(to: p(0.536, 12.489, s))
        path.addLine(to: p(0, 11.784, s))
        path.addLine(to: p(0.055, 11.432, s))
        path.addLine(to: p(0.535, 11.111, s))
        path.addLine(to: p(1.221, 11.171, s))
        path.addLine(to: p(2.741, 11.274, s))
        path.addLine(to: p(5.019, 11.432, s))
        path.addLine(to: p(6.671, 11.529, s))
        path.addLine(to: p(9.12, 11.784, s))
        path.addLine(to: p(9.509, 11.784, s))
        path.addLine(to: p(9.564, 11.627, s))
        path.addLine(to: p(9.43, 11.529, s))
        path.addLine(to: p(9.327, 11.432, s))
        path.addLine(to: p(6.969, 9.836, s))
        path.addLine(to: p(4.417, 8.148, s))
        path.addLine(to: p(3.081, 7.176, s))
        path.addLine(to: p(2.357, 6.685, s))
        path.addLine(to: p(1.993, 6.223, s))
        path.addLine(to: p(1.835, 5.215, s))
        path.addLine(to: p(2.491, 4.493, s))
        path.addLine(to: p(3.372, 4.553, s))
        path.addLine(to: p(3.597, 4.614, s))
        path.addLine(to: p(4.49, 5.3, s))
        path.addLine(to: p(6.398, 6.776, s))
        path.addLine(to: p(8.889, 8.609, s))
        path.addLine(to: p(9.254, 8.913, s))
        path.addLine(to: p(9.399, 8.81, s))
        path.addLine(to: p(9.418, 8.737, s))
        path.addLine(to: p(9.254, 8.463, s))
        path.addLine(to: p(7.899, 6.017, s))
        path.addLine(to: p(6.453, 3.527, s))
        path.addLine(to: p(5.809, 2.495, s))
        path.addLine(to: p(5.639, 1.876, s))
        path.addCurve(to: p(5.535, 1.147, s), control1: p(5.639, 1.876, s), control2: p(5.535, 1.39, s))
        path.addLine(to: p(6.283, 0.134, s))
        path.addLine(to: p(6.696, 0, s))
        path.addLine(to: p(7.692, 0.134, s))
        path.addLine(to: p(8.112, 0.498, s))
        path.addLine(to: p(8.732, 1.912, s))
        path.addLine(to: p(9.734, 4.141, s))
        path.addLine(to: p(11.289, 7.171, s))
        path.addLine(to: p(11.745, 8.069, s))
        path.addLine(to: p(11.988, 8.901, s))
        path.addLine(to: p(12.079, 9.156, s))
        path.addLine(to: p(12.237, 9.156, s))
        path.addLine(to: p(12.237, 9.01, s))
        path.addLine(to: p(12.365, 7.304, s))
        path.addLine(to: p(12.602, 5.209, s))
        path.addLine(to: p(12.832, 2.514, s))
        path.addLine(to: p(12.912, 1.754, s))
        path.addLine(to: p(13.288, 0.844, s))
        path.addLine(to: p(14.035, 0.352, s))
        path.addLine(to: p(14.619, 0.632, s))
        path.addLine(to: p(15.099, 1.317, s))
        path.addLine(to: p(15.032, 1.761, s))
        path.addLine(to: p(14.746, 3.612, s))
        path.addLine(to: p(14.187, 6.515, s))
        path.addLine(to: p(13.823, 8.457, s))
        path.addLine(to: p(14.035, 8.457, s))
        path.addLine(to: p(14.278, 8.215, s))
        path.addLine(to: p(15.263, 6.909, s))
        path.addLine(to: p(16.915, 4.845, s))
        path.addLine(to: p(17.645, 4.025, s))
        path.addLine(to: p(18.495, 3.121, s))
        path.addLine(to: p(19.042, 2.69, s))
        path.addLine(to: p(20.075, 2.69, s))
        path.addLine(to: p(20.835, 3.819, s))
        path.addLine(to: p(20.495, 4.985, s))
        path.addLine(to: p(19.431, 6.332, s))
        path.addLine(to: p(18.55, 7.474, s))
        path.addLine(to: p(17.286, 9.174, s))
        path.addLine(to: p(16.496, 10.534, s))
        path.addLine(to: p(16.569, 10.644, s))
        path.addLine(to: p(16.757, 10.624, s))
        path.addLine(to: p(19.613, 10.018, s))
        path.addLine(to: p(21.156, 9.738, s))
        path.addLine(to: p(22.997, 9.423, s))
        path.addLine(to: p(23.83, 9.811, s))
        path.addLine(to: p(23.921, 10.206, s))
        path.addLine(to: p(23.593, 11.013, s))
        path.addLine(to: p(21.624, 11.499, s))
        path.addLine(to: p(19.315, 11.961, s))
        path.addLine(to: p(15.876, 12.774, s))
        path.addLine(to: p(15.834, 12.804, s))
        path.addLine(to: p(15.883, 12.865, s))
        path.addLine(to: p(17.432, 13.011, s))
        path.addLine(to: p(18.094, 13.047, s))
        path.addLine(to: p(19.716, 13.047, s))
        path.addLine(to: p(22.736, 13.272, s))
        path.addLine(to: p(23.526, 13.794, s))
        path.addLine(to: p(24, 14.432, s))
        path.addLine(to: p(23.921, 14.917, s))
        path.addLine(to: p(22.706, 15.537, s))
        path.addLine(to: p(21.066, 15.148, s))
        path.addLine(to: p(17.237, 14.238, s))
        path.addLine(to: p(15.925, 13.909, s))
        path.addLine(to: p(15.743, 13.909, s))
        path.addLine(to: p(15.743, 14.019, s))
        path.addLine(to: p(16.836, 15.087, s))
        path.addLine(to: p(18.842, 16.897, s))
        path.addLine(to: p(21.351, 19.227, s))
        path.addLine(to: p(21.478, 19.805, s))
        path.addLine(to: p(21.156, 20.26, s))
        path.addLine(to: p(20.816, 20.211, s))
        path.addLine(to: p(18.611, 18.554, s))
        path.addLine(to: p(17.76, 17.807, s))
        path.addLine(to: p(15.834, 16.187, s))
        path.addLine(to: p(15.706, 16.187, s))
        path.addLine(to: p(15.706, 16.357, s))
        path.addLine(to: p(16.15, 17.006, s))
        path.addLine(to: p(18.495, 20.527, s))
        path.addLine(to: p(18.617, 21.607, s))
        path.addLine(to: p(18.447, 21.96, s))
        path.addLine(to: p(17.839, 22.173, s))
        path.addLine(to: p(17.171, 22.051, s))
        path.addLine(to: p(15.797, 20.126, s))
        path.addLine(to: p(14.382, 17.959, s))
        path.addLine(to: p(13.239, 16.016, s))
        path.addLine(to: p(13.099, 16.096, s))
        path.addLine(to: p(12.425, 23.35, s))
        path.addLine(to: p(12.109, 23.72, s))
        path.addLine(to: p(11.38, 24, s))
        path.addLine(to: p(10.773, 23.539, s))
        path.addLine(to: p(10.451, 22.792, s))
        path.addLine(to: p(10.773, 21.316, s))
        path.addLine(to: p(11.162, 19.392, s))
        path.addLine(to: p(11.477, 17.862, s))
        path.addLine(to: p(11.763, 15.962, s))
        path.addLine(to: p(11.933, 15.33, s))
        path.addLine(to: p(11.921, 15.288, s))
        path.addLine(to: p(11.781, 15.306, s))
        path.addLine(to: p(10.347, 17.273, s))
        path.addLine(to: p(8.167, 20.218, s))
        path.addLine(to: p(6.441, 22.063, s))
        path.addLine(to: p(6.027, 22.227, s))
        path.addLine(to: p(5.31, 21.857, s))
        path.addLine(to: p(5.377, 21.195, s))
        path.addLine(to: p(5.778, 20.606, s))
        path.addLine(to: p(8.166, 17.57, s))
        path.addLine(to: p(9.606, 15.688, s))
        path.addLine(to: p(10.536, 14.602, s))
        path.addLine(to: p(10.53, 14.444, s))
        path.addLine(to: p(10.475, 14.444, s))
        path.addLine(to: p(4.132, 18.56, s))
        path.addLine(to: p(3.002, 18.706, s))
        path.addLine(to: p(2.515, 18.25, s))
        path.addLine(to: p(2.576, 17.504, s))
        path.addLine(to: p(2.807, 17.261, s))
        path.addLine(to: p(4.715, 15.949, s))
        path.closeSubpath()

        // Center the path in the rect
        let bounds = path.boundingRect
        let xOffset = (rect.width - bounds.width) / 2 - bounds.minX
        let yOffset = (rect.height - bounds.height) / 2 - bounds.minY

        return path.offsetBy(dx: xOffset, dy: yOffset)
    }

    private func p(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }
}

// MARK: - Preference Keys

/// Preference key for measuring welcome message content height
struct WelcomeMessageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Previews

#Preview("Single Process") {
    let state = NotchState()
    let _ = { state.activeProcesses = [.claudeCode] }()
    return ZStack(alignment: .top) {
        Color.gray.opacity(0.2)
        NotchView(notchState: state, screenWidth: 400, screenHeight: 300)
    }
    .frame(width: 400, height: 300)
}

#Preview("Multiple Processes") {
    let state = NotchState()
    let _ = { state.activeProcesses = [.claudeCode, .androidStudio] }()
    return ZStack(alignment: .top) {
        Color.gray.opacity(0.2)
        NotchView(notchState: state, screenWidth: 400, screenHeight: 300)
    }
    .frame(width: 400, height: 300)
}

#Preview("Empty") {
    ZStack(alignment: .top) {
        Color.gray.opacity(0.2)
        NotchView(notchState: NotchState(), screenWidth: 400, screenHeight: 300)
    }
    .frame(width: 400, height: 300)
}
