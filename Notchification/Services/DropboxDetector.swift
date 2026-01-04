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
final class DropboxDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .dropbox

    // Consecutive readings required for state changes
    private let requiredToShow: Int = 2
    private let requiredToHide: Int = 2

    private var consecutiveSyncingReadings: Int = 0
    private var consecutiveIdleReadings: Int = 0

    // Status patterns indicating sync activity
    private let syncingPatterns = ["Syncing", "Uploading", "Downloading", "Indexing"]

    init() {}

    func reset() {
        consecutiveSyncingReadings = 0
        consecutiveIdleReadings = 0
        isActive = false
    }

    func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            guard self.isDropboxRunning() else {
                DispatchQueue.main.async {
                    self.consecutiveSyncingReadings = 0
                    self.consecutiveIdleReadings += 1
                    if self.consecutiveIdleReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                    }
                }
                return
            }

            let status = self.getMenuBarStatus()
            let isSyncing = self.isSyncing(status: status)

            DispatchQueue.main.async {
                if isSyncing {
                    self.consecutiveSyncingReadings += 1
                    self.consecutiveIdleReadings = 0
                    if self.consecutiveSyncingReadings >= self.requiredToShow && !self.isActive {
                        self.isActive = true
                    }
                } else {
                    self.consecutiveIdleReadings += 1
                    self.consecutiveSyncingReadings = 0
                    if self.consecutiveIdleReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                    }
                }
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
}
