//
//  DropboxDetector.swift
//  Notchification
//
//  Detects Dropbox sync activity by polling menu bar status via AppleScript
//  Color: #0061FF (Dropbox blue)
//

import Foundation
import Combine

/// Detects if Dropbox is actively syncing by reading its menu bar status
final class DropboxDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 1.0  // Slower polling for menu bar
    private let queue = DispatchQueue(label: "com.notchification.dropboxdetector", qos: .utility)

    // Consecutive readings required for state changes
    private let requiredToShow: Int = 2
    private let requiredToHide: Int = 2

    private var consecutiveSyncingReadings: Int = 0
    private var consecutiveIdleReadings: Int = 0

    // Status patterns indicating sync activity
    private let syncingPatterns = ["Syncing", "Uploading", "Downloading", "Indexing"]
    private let idlePatterns = ["Up to date", "Paused", "Offline"]

    init() {}

    func startMonitoring() {
        consecutiveSyncingReadings = 0
        consecutiveIdleReadings = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.checkDropboxStatus()
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

    private func checkDropboxStatus() {
        guard isDropboxRunning() else {
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

    private func isDropboxRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "Dropbox"]

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

    /// Get Dropbox menu bar status via AppleScript
    /// The sync status is in the 'help' property, not 'description'
    private func getMenuBarStatus() -> String {
        let script = """
        tell application "System Events"
            if exists process "Dropbox" then
                tell process "Dropbox"
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
