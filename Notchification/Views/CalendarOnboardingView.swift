//
//  CalendarOnboardingView.swift
//  Notchification
//
//  Explains the morning overview feature and requests calendar permission.
//

import SwiftUI
import EventKit

struct CalendarOnboardingView: View {
    @ObservedObject var calendarSettings = CalendarSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isRequestingPermission = false
    @State private var isAuthorized: Bool = false

    private func checkAuthorization() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            // Title
            Text("Morning Overview")
                .font(.custom("FiraCode-Medium", size: 20))

            // Description
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "sunrise",
                    text: "See your day's meetings when you open your Mac each morning"
                )
                FeatureRow(
                    icon: "bell.badge",
                    text: "Get reminders before meetings start"
                )
                FeatureRow(
                    icon: "hand.tap",
                    text: "Click the notch to dismiss"
                )
            }
            .padding(.horizontal)

            // Time setting
            HStack {
                Text("Show between")
                    .foregroundColor(.secondary)
                Picker("", selection: $calendarSettings.morningStartHour) {
                    ForEach(5..<12, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
                Text("and")
                    .foregroundColor(.secondary)
                Picker("", selection: $calendarSettings.morningEndHour) {
                    ForEach(7..<14, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
            }
            .font(.custom("FiraCode-Regular", size: 12))

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                if isAuthorized {
                    // Already authorized
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Calendar access granted")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    Button(action: { dismiss() }) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if EKEventStore.authorizationStatus(for: .event) == .denied || EKEventStore.authorizationStatus(for: .event) == .restricted {
                    // Permission denied - direct to System Settings
                    Text("Calendar access was denied")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button(action: openSystemSettings) {
                        Text("Open System Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip for now") {
                        calendarSettings.enableMorningOverview = false
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                } else {
                    // Need to request permission
                    Button(action: requestCalendarAccess) {
                        if isRequestingPermission {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Allow Calendar Access")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRequestingPermission)

                    Button("Skip for now") {
                        calendarSettings.enableMorningOverview = false
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 340, height: 420)
        .onAppear {
            isAuthorized = checkAuthorization()
        }
    }

    private func requestCalendarAccess() {
        isRequestingPermission = true
        let eventStore = EKEventStore()
        Task {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                await MainActor.run {
                    isRequestingPermission = false
                    isAuthorized = granted || checkAuthorization()
                    calendarSettings.updateAuthorizationStatus()
                    if isAuthorized {
                        // Small delay then dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isRequestingPermission = false
                    isAuthorized = checkAuthorization()
                    calendarSettings.updateAuthorizationStatus()
                }
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(text)
                .font(.custom("FiraCode-Regular", size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Window Controller

class CalendarOnboardingWindowController {
    static let shared = CalendarOnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    func showOnboarding() {
        // Don't show if already shown
        if UserDefaults.standard.bool(forKey: "calendarOnboardingShown") {
            return
        }

        // Don't show if already authorized
        if CalendarSettings.shared.authorizationStatus == .authorized {
            UserDefaults.standard.set(true, forKey: "calendarOnboardingShown")
            return
        }

        if window == nil {
            let contentView = CalendarOnboardingView()

            let hostingController = NSHostingController(rootView: contentView)

            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Calendar Setup"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()

            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Mark as shown
        UserDefaults.standard.set(true, forKey: "calendarOnboardingShown")
    }

    /// Reset the onboarding shown flag (for testing)
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "calendarOnboardingShown")
    }
}

#Preview {
    CalendarOnboardingView()
}
