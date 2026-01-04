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
final class InstallerDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .installer
    private let bundleIdentifier = "com.apple.installer"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {}

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let isRunning = self.isInstallerRunning()

            DispatchQueue.main.async {
                if isRunning {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Installer.app is running with an active installation (progress bar visible)
    private func isInstallerRunning() -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else { return false }

        return hasProgressBar()
    }

    /// Check if Installer.app has a busy or progress indicator visible (installation in progress)
    private func hasProgressBar() -> Bool {
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
}
