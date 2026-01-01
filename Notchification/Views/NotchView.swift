//
//  NotchView.swift
//  Notchification
//

import SwiftUI

struct NotchView: View {
    @ObservedObject var notchState: NotchState

    // Animation state
    @State private var isExpanded: Bool = false

    // Dimensions
    private let expandedHeight: CGFloat = 120
    private let notchWidth: CGFloat = 300
    private let frameWidth: CGFloat = 380  // Extra 80 for outward curves

    // Content dimensions
    private let logoSize: CGFloat = 32
    private let progressBarWidth: CGFloat = 180
    private let progressBarHeight: CGFloat = 16
    private let contentPadding: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            // The notch shape - scales from top center with bounce
            NotchShape()
                .fill(Color.black)
                .frame(width: notchWidth, height: expandedHeight)
                .scaleEffect(
                    x: isExpanded ? 1 : 0.3,
                    y: isExpanded ? 1 : 0,
                    anchor: .top
                )

            // Content: Claude logo + progress bar
            HStack(alignment: .center, spacing: 16) {
                ClaudeLogo()
                    .frame(width: logoSize, height: logoSize)

                AnimatedProgressBar(isActive: isExpanded)
                    .frame(width: progressBarWidth, height: progressBarHeight)
            }
            .offset(y: expandedHeight - contentPadding - logoSize - 4)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.5)
        }
        .frame(width: frameWidth, height: expandedHeight, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0), value: isExpanded)
        .onChange(of: notchState.activeProcesses.isEmpty) { _, isEmpty in
            isExpanded = !isEmpty
        }
        .onAppear {
            if !notchState.activeProcesses.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isExpanded = true
                }
            }
        }
    }
}

// MARK: - Animated Progress Bar

struct AnimatedProgressBar: View {
    let isActive: Bool

    @State private var baseProgress: CGFloat = 0
    @State private var waveProgress: CGFloat = 0
    @State private var waveOpacity: CGFloat = 1.0

    private let baseColor = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let waveColor = Color(red: 0.98, green: 0.65, blue: 0.5)
    private let animationDuration: Double = 1.5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Base layer (solid, always visible once filled)
                Capsule()
                    .fill(baseColor)
                    .frame(width: geometry.size.width * baseProgress)

                // Wave layer (draws across while fading out)
                Capsule()
                    .fill(waveColor)
                    .frame(width: geometry.size.width * waveProgress)
                    .opacity(waveOpacity)
            }
        }
        .clipShape(Capsule())
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            } else {
                resetAnimation()
            }
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        resetAnimation()

        // First: fill base layer
        withAnimation(.easeOut(duration: animationDuration)) {
            baseProgress = 1.0
        }

        // Start wave animation after base fills
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            animateWave()
        }
    }

    private func animateWave() {
        guard isActive else { return }

        // Reset wave
        waveProgress = 0
        waveOpacity = 1.0

        // Animate wave: progress to full while fading out
        withAnimation(.easeInOut(duration: animationDuration)) {
            waveProgress = 1.0
            waveOpacity = 0.0
        }

        // Repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            animateWave()
        }
    }

    private func resetAnimation() {
        baseProgress = 0
        waveProgress = 0
        waveOpacity = 1.0
    }
}

// MARK: - Claude Logo Shape

struct ClaudeLogo: View {
    var body: some View {
        ClaudeLogoShape()
            .fill(Color(red: 0.85, green: 0.47, blue: 0.34))  // #D97757
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

#Preview("Expanded") {
    let state = NotchState()
    state.activeProcesses = [.claude]
    return VStack(spacing: 0) {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 24)

        NotchView(notchState: state)

        Spacer()
    }
    .frame(width: 400, height: 300)
    .background(Color.gray.opacity(0.2))
}

#Preview("Empty") {
    VStack(spacing: 0) {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 24)

        NotchView(notchState: NotchState())

        Spacer()
    }
    .frame(width: 400, height: 300)
    .background(Color.gray.opacity(0.2))
}
