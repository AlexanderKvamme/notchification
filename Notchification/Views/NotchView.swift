//
//  NotchView.swift
//  Notchification
//

import SwiftUI
import ConfettiSwiftUI
import AppKit

// Shared sound instance for completion sound
private let completionSound = NSSound(named: "Glass")

struct NotchView: View {
    @ObservedObject var notchState: NotchState
    var screenWidth: CGFloat = 1440
    var screenHeight: CGFloat = 900

    // Animation state
    @State private var isExpanded: Bool = false
    @State private var previousProcesses: Set<ProcessType> = []

    // Separate confetti triggers for each process type
    @State private var claudeConfettiTrigger: Int = 0
    @State private var xcodeConfettiTrigger: Int = 0
    @State private var androidConfettiTrigger: Int = 0
    @State private var finderConfettiTrigger: Int = 0
    @State private var opencodeConfettiTrigger: Int = 0
    @State private var codexConfettiTrigger: Int = 0

    // Dimensions
    private let notchWidth: CGFloat = 300
    private let notchFrameWidth: CGFloat = 380  // Extra 80 for outward curves

    // Content dimensions
    private let logoSize: CGFloat = 24
    private let progressBarHeight: CGFloat = 12
    private let horizontalPadding: CGFloat = 20
    private let rowSpacing: CGFloat = 8
    private let topPadding: CGFloat = 38  // Space below physical notch cutout (~34px)

    // Dynamic height based on number of processes
    private var expandedHeight: CGFloat {
        let processCount = max(1, notchState.activeProcesses.count)
        let contentHeight = CGFloat(processCount) * logoSize + CGFloat(processCount - 1) * rowSpacing
        return topPadding + contentHeight + 16  // 16 bottom padding
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The notch shape - scales from top center with bounce
            NotchShape()
                .fill(Color.black)
                .frame(width: notchWidth, height: expandedHeight)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: expandedHeight)
                .scaleEffect(
                    x: isExpanded ? 1 : 0.3,
                    y: isExpanded ? 1 : 0,
                    anchor: .top
                )
                .overlay(alignment: .top) {
                    // Separate confetti cannons - one per process type
                    // Each has a fixed color, avoiding caching issues
                    ZStack {
                        ConfettiEmitter(trigger: $claudeConfettiTrigger, color: ProcessType.claude.color)
                        ConfettiEmitter(trigger: $xcodeConfettiTrigger, color: ProcessType.xcode.color)
                        ConfettiEmitter(trigger: $androidConfettiTrigger, color: ProcessType.androidStudio.color)
                        ConfettiEmitter(trigger: $finderConfettiTrigger, color: ProcessType.finder.color)
                        ConfettiEmitter(trigger: $opencodeConfettiTrigger, color: ProcessType.opencode.color)
                        ConfettiEmitter(trigger: $codexConfettiTrigger, color: ProcessType.codex.color)
                    }
                    .allowsHitTesting(false)
                }

            // Content: Multiple processes stacked vertically
            if !notchState.activeProcesses.isEmpty {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(notchState.activeProcesses) { process in
                        HStack(alignment: .center, spacing: 10) {
                            ProcessLogo(processType: process)
                                .frame(width: logoSize, height: logoSize)

                            AnimatedProgressBar(
                                isActive: isExpanded,
                                baseColor: process.color,
                                waveColor: process.waveColor
                            )
                            .frame(height: progressBarHeight)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(width: notchWidth)
                .offset(y: topPadding)
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(
                    x: isExpanded ? 1 : 0.3,  // Match notch's x-scale
                    y: isExpanded ? 1 : 0,    // Match notch's y-scale
                    anchor: .top
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: notchState.activeProcesses.count)
            }
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .top)
        .drawingGroup()  // GPU acceleration for smoother animations
        .onChange(of: notchState.activeProcesses.isEmpty) { _, isEmpty in
            let animation: Animation = isEmpty
                ? .easeOut(duration: 0.3)  // Smooth close
                : .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)  // Bouncy open
            withAnimation(animation) {
                isExpanded = !isEmpty
            }
        }
        .onChange(of: notchState.activeProcesses) { oldValue, newValue in
            // Check if a process was removed (completed)
            let oldSet = Set(oldValue)
            let newSet = Set(newValue)
            let removed = oldSet.subtracting(newSet)

            // Trigger effects for each removed process
            for removedProcess in removed {
                // Confetti (if enabled)
                if TrackingSettings.shared.confettiEnabled {
                    switch removedProcess {
                    case .claude:
                        claudeConfettiTrigger += 1
                    case .xcode:
                        xcodeConfettiTrigger += 1
                    case .androidStudio:
                        androidConfettiTrigger += 1
                    case .finder:
                        finderConfettiTrigger += 1
                    case .opencode:
                        opencodeConfettiTrigger += 1
                    case .codex:
                        codexConfettiTrigger += 1
                    }
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
        .onAppear {
            previousProcesses = Set(notchState.activeProcesses)
            if !notchState.activeProcesses.isEmpty {
                // Use withAnimation for explicit control
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
                    isExpanded = true
                }
            }
        }
    }
}

// MARK: - Process Logo

struct ProcessLogo: View {
    let processType: ProcessType

    var body: some View {
        switch processType {
        case .claude:
            ClaudeLogo()
        case .androidStudio:
            AndroidStudioLogo()
        case .xcode:
            XcodeLogo()
        case .finder:
            FinderLogo()
        case .opencode:
            OpencodeLogo()
        case .codex:
            CodexLogo()
        }
    }
}

// MARK: - Android Studio Logo

struct AndroidStudioLogo: View {
    var body: some View {
        AndroidStudioLogoShape()
            .fill(ProcessType.androidStudio.color)
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
    var body: some View {
        XcodeLogoShape()
            .fill(ProcessType.xcode.color)
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
    var body: some View {
        Image("findericon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(ProcessType.finder.color)
    }
}

// MARK: - Opencode Logo

struct OpencodeLogo: View {
    var body: some View {
        Image("opencodeicon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(ProcessType.opencode.color)
    }
}

// MARK: - Codex Logo

struct CodexLogo: View {
    var body: some View {
        Image("codexicon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(ProcessType.codex.color)
    }
}

// MARK: - Animated Progress Bar

struct AnimatedProgressBar: View {
    let isActive: Bool
    var baseColor: Color = Color(red: 0.85, green: 0.47, blue: 0.34)
    var waveColor: Color = Color(red: 0.95, green: 0.60, blue: 0.48)

    @State private var baseWidth: CGFloat = 0
    @State private var waveWidth: CGFloat = 0
    @State private var waveOpacity: CGFloat = 1.0

    private let animationDuration: Double = 3.0

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
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
                    startAnimation(width: geometry.size.width)
                } else {
                    stopAnimation()
                }
            }
            .onAppear {
                if isActive {
                    startAnimation(width: geometry.size.width)
                }
            }
        }
        .clipShape(Capsule())
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
        guard isActive else { return }

        // Reset wave instantly (no animation)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            waveWidth = 0
            waveOpacity = 1.0
        }

        // Small delay to let reset apply, then animate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard self.isActive else { return }

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
    var body: some View {
        ClaudeLogoShape()
            .fill(ProcessType.claude.color)
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

// MARK: - Confetti Emitter

struct ConfettiEmitter: View {
    @Binding var trigger: Int
    let color: Color

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 300, height: 50)
            .confettiCannon(
                counter: $trigger,
                num: 40,  // Reduced from 100 for smoother performance
                colors: [color],
                confettiSize: 12,
                rainHeight: 200,
                openingAngle: Angle(degrees: 180),
                closingAngle: Angle(degrees: 360),
                radius: 300
            )
    }
}

#Preview("Single Process") {
    let state = NotchState()
    state.activeProcesses = [.claude]
    return ZStack(alignment: .top) {
        Color.gray.opacity(0.2)
        NotchView(notchState: state, screenWidth: 400, screenHeight: 300)
    }
    .frame(width: 400, height: 300)
}

#Preview("Multiple Processes") {
    let state = NotchState()
    state.activeProcesses = [.claude, .androidStudio]
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
