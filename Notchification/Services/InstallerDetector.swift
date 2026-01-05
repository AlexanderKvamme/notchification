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

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.installer-check", qos: .utility)

    init() {}

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
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
    /// Note: System Events is required to check UI elements
    private func hasProgressBar() -> Bool {
        // Search for any progress indicator anywhere in the Installer window
        let script = """
        tell application "System Events"
            tell process "Installer"
                if not (exists window 1) then return "NONE"
                set allElements to entire contents of window 1
                repeat with elem in allElements
                    set elemClass to class of elem as string
                    if elemClass contains "progress indicator" or elemClass contains "busy indicator" then
                        return "PROGRESS"
                    end if
                end repeat
                return "NONE"
            end tell
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // Timeout after 2 seconds
        let timeoutWork = DispatchWorkItem { [weak task] in
            if task?.isRunning == true {
                task?.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutWork)

        do {
            try task.run()
            task.waitUntilExit()
            timeoutWork.cancel()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return output == "BUSY" || output == "PROGRESS"
        } catch {
            timeoutWork.cancel()
            return false
        }
    }
}
