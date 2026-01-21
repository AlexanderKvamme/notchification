//
//  WelcomeMessageView.swift
//  Notchification
//
//  Shows a "What's New" message from the CEO in the notch.
//  Styled to match the calendar view with Fira Code typography.
//

import SwiftUI

/// Message to show users after updating to a new version
struct WelcomeMessage {
    let version: String
    let title: String
    let body: String
    let signoff: String

    /// Current message to show - update this with each release
    static let current = WelcomeMessage(
        version: "1.0.35",
        title: "What's New",
        body: """
        Hello Notification Family!

        Quick update: The notch now shows on your laptop when no external display is connected. Also, the calendar button in the menu now toggles on/off.

        Have a good one, fellas.
        """,
        signoff: "— Alexander"
    )
}

/// Manager for tracking which version's message has been seen
final class WelcomeMessageManager: ObservableObject {
    static let shared = WelcomeMessageManager()

    private let lastSeenVersionKey = "welcomeMessageLastSeenVersion"

    /// Check if we should show the welcome message
    var shouldShowMessage: Bool {
        // Always show if debug setting is enabled
        if DebugSettings.shared.alwaysShowWelcomeMessage {
            return true
        }
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenVersionKey) ?? ""
        let currentMessage = WelcomeMessage.current.version
        return lastSeen != currentMessage
    }

    /// Mark the current message as seen
    func markAsSeen() {
        // Don't mark as seen if debug mode is on (so it keeps showing)
        guard !DebugSettings.shared.alwaysShowWelcomeMessage else { return }
        UserDefaults.standard.set(WelcomeMessage.current.version, forKey: lastSeenVersionKey)
    }
}

/// Welcome message content - displays in the notch
/// Styled to match MorningOverviewContent with Fira Code typography
struct WelcomeMessageContent: View {
    let message: WelcomeMessage
    var onDismiss: (() -> Void)? = nil

    @State private var isHovering: Bool = false
    @State private var opacityC: CGFloat = 0
    @State private var opacityE: CGFloat = 0
    @State private var opacityO: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(message.title)
                .font(.custom("FiraCode-Medium", size: 16))
                .foregroundColor(.white)

            // Body text
            Text(message.body)
                .font(.custom("FiraCode-Regular", size: 13))
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Signature
            Image("ceosignature")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: 140, maxHeight: 40)
                .padding(.leading, -40)

            // CEO text - each character fades in with overshoot
            HStack(spacing: 4) {
                Text("C")
                    .opacity(opacityC)
                    .animation(.easeOut(duration: 0.3), value: opacityC)
                Text("E")
                    .opacity(opacityE)
                    .animation(.easeOut(duration: 0.3), value: opacityE)
                Text("O")
                    .opacity(opacityO)
                    .animation(.easeOut(duration: 0.3), value: opacityO)
            }
            .font(.custom("FiraCode-Bold", size: 10))
            .foregroundColor(.white)
            .padding(.top, -15)
            .padding(.leading, 5)
            .padding(.bottom, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture {
            WelcomeMessageManager.shared.markAsSeen()
            onDismiss?()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear {
            // Fade in CEO characters with overshoot: full white then settle to 0.5
            let settleDelay = 0.4  // Time before settling down

            // C
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                opacityC = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + settleDelay) {
                opacityC = 0.5
            }

            // E
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                opacityE = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0 + settleDelay) {
                opacityE = 0.5
            }

            // O
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                opacityO = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0 + settleDelay) {
                opacityO = 0.5
            }
        }
    }
}

/// Controller for showing the welcome message in the notch
final class WelcomeMessageWindowController {
    static let shared = WelcomeMessageWindowController()

    func showIfNeeded() {
        guard WelcomeMessageManager.shared.shouldShowMessage else { return }
        show()
    }

    func show() {
        // Set the debug flag to show the welcome message in the notch
        DebugSettings.shared.showWelcomeMessage = true
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        WelcomeMessageContent(
            message: WelcomeMessage.current
        )
        .padding(20)
        .frame(width: 280)
    }
    .frame(width: 320, height: 300)
}
