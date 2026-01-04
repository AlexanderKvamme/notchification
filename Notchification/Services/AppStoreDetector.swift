//
//  AppStoreDetector.swift
//  Notchification
//
//  Detects App Store download/install activity via Accessibility API
//  Color: Blue (App Store blue)
//

import Foundation
import Combine
import AppKit

/// Detects App Store downloads by checking UI for active downloads
final class AppStoreDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?
    private let bundleIdentifier = "com.apple.AppStore"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {}

    func startMonitoring() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
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
        let hasDownload = isDownloading()

        if hasDownload {
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

    /// Check if App Store has active downloads by inspecting UI button states
    private func isDownloading() -> Bool {
        // First check if App Store is running
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else { return false }

        // Check button states in the updates list
        // "Resume" = paused download, "Stop" = active download, "Update" = not downloading
        let script = """
        tell application "System Events"
            tell process "App Store"
                try
                    set allGroups to every group of list 1 of list 1 of scroll area 1 of splitter group 1 of window 1
                    repeat with grp in allGroups
                        try
                            set allButtons to every button of grp
                            repeat with btn in allButtons
                                try
                                    set btnTitle to title of btn
                                    -- "Resume" = paused download, "Stop" = active download
                                    if btnTitle is "Resume" then return "DOWNLOADING"
                                    if btnTitle is "Stop" then return "DOWNLOADING"
                                    if btnTitle contains "Downloading" then return "DOWNLOADING"
                                    if btnTitle contains "Installing" then return "DOWNLOADING"
                                end try
                            end repeat
                        end try
                    end repeat
                    return "NONE"
                on error
                    return "NONE"
                end try
            end tell
        end tell
        """

        var result = "NONE"
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "NONE"
            } catch {}

            semaphore.signal()
        }

        // Wait max 3 seconds
        _ = semaphore.wait(timeout: .now() + 3)
        return result == "DOWNLOADING"
    }

    deinit {
        stopMonitoring()
    }
}
