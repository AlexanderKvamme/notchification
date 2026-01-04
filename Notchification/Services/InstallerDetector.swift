//
//  InstallerDetector.swift
//  Notchification
//
//  Detects macOS Installer.app activity (pkg installations)
//  Color: Purple (system installer)
//

import Foundation
import Combine
import AppKit

/// Detects if Installer.app is running (pkg installations)
final class InstallerDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?
    private let bundleIdentifier = "com.apple.installer"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {}

    func startMonitoring() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        checkStatus()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func checkStatus() {
        let isRunning = isInstallerRunning()

        if isRunning {
            consecutiveActiveReadings += 1
            consecutiveInactiveReadings = 0

            if consecutiveActiveReadings >= requiredToShow && !isActive {
                isActive = true
            }
        } else {
            consecutiveInactiveReadings += 1
            consecutiveActiveReadings = 0

            if consecutiveInactiveReadings >= requiredToHide && isActive {
                isActive = false
            }
        }
    }

    /// Check if Installer.app is running with an active installation (progress bar visible)
    private func isInstallerRunning() -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else { return false }

        // Check if there's a progress indicator visible (actual installation in progress)
        return hasProgressBar()
    }

    /// Check if Installer.app has a busy or progress indicator visible (installation in progress)
    private func hasProgressBar() -> Bool {
        // Use osascript via Process to avoid NSAppleScript permission issues
        // Check for busy indicator (Preparing phase) or progress indicator (Writing files phase)
        let script = """
        tell application "System Events"
            tell process "Installer"
                try
                    set busyExists to exists (busy indicator 1 of group 1 of group 1 of window 1)
                    if busyExists then return "BUSY"
                end try
                try
                    set progressExists to exists (progress indicator 1 of group 1 of group 1 of window 1)
                    if progressExists then return "PROGRESS"
                end try
                return "NONE"
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return output == "BUSY" || output == "PROGRESS"
        } catch {
            return false
        }
    }

    deinit {
        stopMonitoring()
    }
}
