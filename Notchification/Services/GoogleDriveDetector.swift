//
//  GoogleDriveDetector.swift
//  Notchification
//
//  Detects Google Drive sync activity by polling menu bar status via AppleScript
//  Color: #4285F4 (Google blue)
//

import Foundation
import Combine

/// Detects if Google Drive is actively syncing by reading its menu bar status
final class GoogleDriveDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 1.0
    private let queue = DispatchQueue(label: "com.notchification.googledrivedetector", qos: .utility)

    private let requiredToShow: Int = 2
    private let requiredToHide: Int = 2

    private var consecutiveSyncingReadings: Int = 0
    private var consecutiveIdleReadings: Int = 0

    // Google Drive status patterns
    private let syncingPatterns = ["Syncing", "Uploading", "Downloading", "Preparing"]

    init() {}

    func startMonitoring() {
        consecutiveSyncingReadings = 0
        consecutiveIdleReadings = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.checkStatus()
        }
        timer.resume()
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        DispatchQueue.main.async {
            self.isActive = false
        }
    }

    private func checkStatus() {
        guard isGoogleDriveRunning() else {
            consecutiveSyncingReadings = 0
            consecutiveIdleReadings += 1
            if consecutiveIdleReadings >= requiredToHide {
                updateStatus(isActive: false)
            }
            return
        }

        let status = getMenuBarStatus()

        if isSyncing(status: status) {
            consecutiveSyncingReadings += 1
            consecutiveIdleReadings = 0
            if consecutiveSyncingReadings >= requiredToShow {
                updateStatus(isActive: true)
            }
        } else {
            consecutiveIdleReadings += 1
            consecutiveSyncingReadings = 0
            if consecutiveIdleReadings >= requiredToHide {
                updateStatus(isActive: false)
            }
        }
    }

    private func isSyncing(status: String) -> Bool {
        for pattern in syncingPatterns {
            if status.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }
        return false
    }

    private func isGoogleDriveRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "Google Drive"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !output.isEmpty
    }

    /// Get Google Drive menu bar status via AppleScript
    /// The sync status is typically in the 'help' property
    private func getMenuBarStatus() -> String {
        let script = """
        tell application "System Events"
            if exists process "Google Drive" then
                tell process "Google Drive"
                    try
                        return help of menu bar item 1 of menu bar 2
                    on error
                        return ""
                    end try
                end tell
            else
                return ""
            end if
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func updateStatus(isActive: Bool) {
        if self.isActive != isActive {
            DispatchQueue.main.async {
                self.isActive = isActive
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
