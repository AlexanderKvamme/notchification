//
//  SettingsView.swift
//  Notchification
//
//  Settings window with tabbed interface
//

import SwiftUI
import AVFoundation
import EventKit
import ApplicationServices

struct SettingsView: View {
    var body: some View {
        TabView {
            AppsSettingsTab()
                .tabItem {
                    Label("Apps", systemImage: "app.badge")
                }

            CalendarSettingsTab()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 450, height: 480)
        .padding(.top, 8)
        .onAppear {
            // Show preview when settings window opens (any tab)
            NotificationCenter.default.post(name: .showSettingsPreview, object: nil)
        }
        .onDisappear {
            // Hide preview when settings window closes
            NotificationCenter.default.post(name: .hideSettingsPreview, object: nil)
        }
    }
}

// MARK: - Apps Tab

struct AppsSettingsTab: View {
    @ObservedObject var trackingSettings = TrackingSettings.shared
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var accessibilityEnabled: Bool = AXIsProcessTrusted()

    var body: some View {
        Form {
            // Accessibility permission status
            Section {
                HStack(spacing: 10) {
                    Image(systemName: accessibilityEnabled ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(accessibilityEnabled ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(accessibilityEnabled ? "Accessibility Enabled" : "Accessibility Required")
                            .font(.headline)
                        Text(accessibilityEnabled
                            ? "App detection is fully functional"
                            : "Most app trackers need this permission to read status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !accessibilityEnabled {
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("AI Tools") {
                Toggle("Claude Code (CLI)", isOn: $trackingSettings.trackClaudeCode)
                Toggle("Claude (App)", isOn: $trackingSettings.trackClaudeApp)
                Toggle("Codex (CLI)", isOn: $trackingSettings.trackCodex)
                Toggle("Opencode (CLI)", isOn: $trackingSettings.trackOpencode)
            }

            Section("Development") {
                Toggle("Android Studio", isOn: $trackingSettings.trackAndroidStudio)
                Toggle("Xcode", isOn: $trackingSettings.trackXcode)
                Toggle("Automator", isOn: $trackingSettings.trackAutomator)
                Toggle("Script Editor", isOn: $trackingSettings.trackScriptEditor)
            }

            Section("Meetings") {
                Toggle("Microsoft Teams", isOn: $trackingSettings.trackTeams)
                    .onChange(of: trackingSettings.trackTeams) { _, enabled in
                        if enabled {
                            handleCameraPermission()
                            NotificationCenter.default.post(name: .showTeamsPreview, object: nil)
                        }
                    }
                Text("Shows a camera preview when Teams launches")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if cameraStatus == .denied || cameraStatus == .restricted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Camera access denied")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Cloud Storage") {
                Toggle("Dropbox", isOn: $trackingSettings.trackDropbox)
                Toggle("Google Drive", isOn: $trackingSettings.trackGoogleDrive)
                Toggle("OneDrive", isOn: $trackingSettings.trackOneDrive)
                Toggle("iCloud", isOn: $trackingSettings.trackICloud)
            }

            Section("Creative") {
                Toggle("DaVinci Resolve", isOn: $trackingSettings.trackDaVinciResolve)
            }

            Section("System") {
                Toggle("Finder", isOn: $trackingSettings.trackFinder)
                Toggle("Installer", isOn: $trackingSettings.trackInstaller)
                Toggle("App Store", isOn: $trackingSettings.trackAppStore)
                Toggle("Downloads", isOn: $trackingSettings.trackDownloads)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            accessibilityEnabled = AXIsProcessTrusted()
        }
    }

    private func handleCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraStatus = status

        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
        } else if status == .denied || status == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Calendar Tab

struct CalendarSettingsTab: View {
    @ObservedObject var trackingSettings = TrackingSettings.shared
    @ObservedObject var calendarSettings = CalendarSettings.shared
    @State private var calendarStatus: CalendarAuthStatus = CalendarSettings.shared.authorizationStatus
    @State private var availableCalendars: [EKCalendar] = []
    private let eventStore = EKEventStore()

    var body: some View {
        Form {
            // Calendar permission status
            Section {
                HStack(spacing: 10) {
                    Image(systemName: calendarStatus == .authorized ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(calendarStatus == .authorized ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(calendarStatus == .authorized ? "Calendar Access Enabled" : "Calendar Access Required")
                            .font(.headline)
                        Text(calendarStatus == .authorized
                            ? "Calendar reminders are fully functional"
                            : "Enable access to show meeting reminders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if calendarStatus != .authorized {
                        Button("Enable Access") {
                            handleCalendarPermission()
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Calendar Reminders") {
                Toggle("Enable", isOn: $trackingSettings.trackCalendar)
                    .onChange(of: trackingSettings.trackCalendar) { _, enabled in
                        if enabled {
                            handleCalendarPermission()
                        }
                    }
                Text("Show a reminder in the notch before meetings start. Reads from macOS Calendar.app (syncs with Outlook, iCloud, Google, etc).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if trackingSettings.trackCalendar && calendarStatus == .authorized {
                    Text("Remind me:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    // Reminder interval checkboxes
                    ForEach(ReminderInterval.allCases.sorted()) { interval in
                        Toggle(interval.displayName + " before", isOn: Binding(
                            get: { calendarSettings.enabledIntervals.contains(interval) },
                            set: { enabled in
                                if enabled {
                                    calendarSettings.enabledIntervals.insert(interval)
                                } else {
                                    calendarSettings.enabledIntervals.remove(interval)
                                }
                            }
                        ))
                    }

                    if calendarSettings.enabledIntervals.isEmpty {
                        Text("Select at least one reminder interval")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if !availableCalendars.isEmpty {
                        DisclosureGroup("Select Calendars") {
                            ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                                Toggle(calendar.title, isOn: Binding(
                                    get: { calendarSettings.selectedCalendarIdentifiers.contains(calendar.calendarIdentifier) },
                                    set: { selected in
                                        if selected {
                                            calendarSettings.selectedCalendarIdentifiers.insert(calendar.calendarIdentifier)
                                        } else {
                                            calendarSettings.selectedCalendarIdentifiers.remove(calendar.calendarIdentifier)
                                        }
                                    }
                                ))
                            }
                            if calendarSettings.selectedCalendarIdentifiers.isEmpty {
                                Text("All calendars will be used when none are selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Morning Overview") {
                Toggle("Enable Morning Overview", isOn: $calendarSettings.enableMorningOverview)
                Text("Automatically show today's schedule each morning (6am - 10am)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            calendarStatus = calendarSettings.authorizationStatus
            loadCalendars()
        }
    }

    private func loadCalendars() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            availableCalendars = eventStore.calendars(for: .event)
        }
    }

    private func handleCalendarPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarStatus = CalendarAuthStatus.from(status)

        if status == .notDetermined {
            Task {
                do {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    await MainActor.run {
                        calendarStatus = granted ? .authorized : .denied
                        calendarSettings.updateAuthorizationStatus()
                        if granted {
                            loadCalendars()
                        }
                    }
                } catch {
                    await MainActor.run {
                        calendarStatus = .denied
                        calendarSettings.updateAuthorizationStatus()
                    }
                }
            }
        } else if status == .denied || status == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Appearance Tab

struct AppearanceSettingsTab: View {
    @ObservedObject var styleSettings = StyleSettings.shared
    @ObservedObject var trackingSettings = TrackingSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Screen:", selection: $styleSettings.screenMode) {
                    ForEach(ScreenMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Select which screen(s) to show the notch indicator on")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Picker("Display Style", selection: $styleSettings.notchStyle) {
                    ForEach(NotchStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch styleSettings.notchStyle {
                    case .normal:
                        Text("Full size with icons and progress bars")
                    case .medium:
                        Text("Compact view at notch width with smaller icons")
                    case .minimal:
                        Text("Only a colored border around the notch")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // Stroke width stepper for minimal style
                if styleSettings.notchStyle == .minimal {
                    Stepper("Stroke Width: \(Int(styleSettings.minimalStrokeWidth))px",
                            value: $styleSettings.minimalStrokeWidth,
                            in: 2...10,
                            step: 1)
                }

                Toggle("Grayscale Mode", isOn: $styleSettings.grayscaleMode)
                Text("Convert all notch colors to grayscale")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Trim top on notch displays", isOn: $styleSettings.trimTopOnNotchDisplay)
                Text("Remove extra padding above progress bars on MacBook displays")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Trim top on external displays", isOn: $styleSettings.trimTopOnExternalDisplay)
                Text("Remove extra padding above progress bars on displays without a notch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("Horizontal Position")
                    Slider(value: $styleSettings.horizontalOffset, in: -500...500, step: 1)
                        .onChange(of: styleSettings.horizontalOffset) { _, _ in
                            NotificationCenter.default.post(name: .showPositionPreview, object: nil)
                        }
                    Text("\(Int(styleSettings.horizontalOffset))")
                        .frame(width: 40)
                        .monospacedDigit()
                }
                Button("Reset to Center") {
                    styleSettings.horizontalOffset = 0
                }
                .disabled(styleSettings.horizontalOffset == 0)
                Text("Adjust horizontal position for external displays")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Completion Effects") {
                Toggle("Confetti", isOn: $trackingSettings.confettiEnabled)
                Text("Show confetti animation when a task completes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Sound", isOn: $trackingSettings.soundEnabled)
                Text("Play a sound when a task completes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @ObservedObject var debugSettings = DebugSettings.shared
    @ObservedObject var licenseManager = LicenseManager.shared

    var body: some View {
        Form {
            Section("Claude Detection") {
                Toggle("Scan All Terminal Sessions", isOn: $debugSettings.claudeScanAllSessions)
                Text("When disabled (default), only scans the frontmost terminal session for faster detection. Enable to scan all windows/tabs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Button("Manage License...") {
                        LicenseWindowController.shared.showLicenseWindow()
                    }
                    Spacer()
                    licenseStatusLabel
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var licenseStatusLabel: some View {
        switch licenseManager.state {
        case .licensed:
            Label("Licensed", systemImage: "checkmark.seal.fill")
                .font(.body.weight(.medium))
                .foregroundColor(.green)
        case .trial(let daysRemaining):
            Label("Trial: \(daysRemaining) days", systemImage: "clock")
                .font(.body.weight(.medium))
                .foregroundColor(.orange)
        case .expired:
            Label("Not Licensed", systemImage: "xmark.circle.fill")
                .font(.body.weight(.medium))
                .foregroundColor(.red)
        }
    }
}

#Preview {
    SettingsView()
}
