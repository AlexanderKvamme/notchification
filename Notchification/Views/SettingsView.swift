//
//  SettingsView.swift
//  Notchification
//
//  Settings window with tabbed interface
//

import SwiftUI
import AVFoundation
import EventKit

struct SettingsView: View {
    var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem {
                    Label("Display", systemImage: "display")
                }

            SmartFeaturesTab()
                .tabItem {
                    Label("Smart Features", systemImage: "sparkles")
                }

            DetectionSettingsTab()
                .tabItem {
                    Label("Detection", systemImage: "eye")
                }

            ThresholdsSettingsTab()
                .tabItem {
                    Label("Thresholds", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 450, height: 380)
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

// MARK: - Display Tab

struct DisplaySettingsTab: View {
    @ObservedObject var styleSettings = StyleSettings.shared

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

            Section {
                Button("Manage License...") {
                    LicenseWindowController.shared.showLicenseWindow()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Smart Features Tab

struct SmartFeaturesTab: View {
    @ObservedObject var trackingSettings = TrackingSettings.shared
    @ObservedObject var calendarSettings = CalendarSettings.shared
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var calendarStatus: CalendarAuthStatus = CalendarSettings.shared.authorizationStatus
    @State private var availableCalendars: [EKCalendar] = []
    private let eventStore = EKEventStore()

    var body: some View {
        Form {
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

                if calendarStatus == .denied || calendarStatus == .restricted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Calendar access denied")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }

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

            Section("Teams Camera Preview") {
                Toggle("Enable", isOn: $trackingSettings.trackTeams)
                    .onChange(of: trackingSettings.trackTeams) { _, enabled in
                        if enabled {
                            handleCameraPermission()
                            // Show Teams preview so user can try hovering to dismiss
                            NotificationCenter.default.post(name: .showTeamsPreview, object: nil)
                        }
                    }
                Text("Show a camera preview when Microsoft Teams launches, so you can check your appearance before joining a meeting. Hover to enlarge, move mouse away to dismiss.")
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
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
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

// MARK: - Detection Tab

struct DetectionSettingsTab: View {
    @ObservedObject var debugSettings = DebugSettings.shared

    var body: some View {
        Form {
            Section("Claude") {
                Toggle("Scan All Terminal Sessions", isOn: $debugSettings.claudeScanAllSessions)
                Text("When disabled (default), only scans the frontmost terminal session for faster detection. Enable to scan all windows/tabs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Thresholds Tab

struct ThresholdsSettingsTab: View {
    @ObservedObject var settings = ThresholdSettings.shared

    var body: some View {
        Form {
            Section {
                Text("Adjust when each detector triggers. Lower values = more sensitive.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Claude") {
                ThresholdSlider(label: "Low (idle)", value: $settings.claudeLowThreshold, range: 0...50, defaultValue: ThresholdSettings.defaultClaudeLow)
                ThresholdSlider(label: "High (active)", value: $settings.claudeHighThreshold, range: 0...100, defaultValue: ThresholdSettings.defaultClaudeHigh)
            }

            Section("Opencode") {
                ThresholdSlider(label: "Low (idle)", value: $settings.opencodeLowThreshold, range: 0...20, defaultValue: ThresholdSettings.defaultOpencodeLow)
                ThresholdSlider(label: "High (active)", value: $settings.opencodeHighThreshold, range: 0...50, defaultValue: ThresholdSettings.defaultOpencodeHigh)
            }

            Section("Xcode") {
                ThresholdSlider(label: "Threshold", value: $settings.xcodeThreshold, range: 0...50, defaultValue: ThresholdSettings.defaultXcode)
            }

            Section {
                Button("Reset All to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ThresholdSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Slider(value: $value, in: range, step: 0.5)
            Text("\(String(format: "%.1f", value))%")
                .frame(width: 50)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
}
