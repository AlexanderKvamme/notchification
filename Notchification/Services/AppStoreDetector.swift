//
//  AppStoreDetector.swift
//  Notchification
//
//  Detects App Store download activity by looking for "loaded" progress button
//  Color: Blue (App Store blue)
//

import Foundation
import Combine

/// Detects App Store downloads by checking for progress button (e.g. "75% loaded")
final class AppStoreDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?

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

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
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
        print("[AppStoreDetector] timer tick")
        checkDownloadStatus { [weak self] downloadActive in
            guard let self = self else { return }

            if downloadActive {
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

    private func checkDownloadStatus(completion: @escaping (Bool) -> Void) {
        let script = """
        tell application "System Events"
            if not (exists process "App Store") then return "0|0|"
            tell process "App Store"
                try
                    set appGroups to every group of list 1 of list 1 of scroll area 1 of splitter group 1 of window 1
                    set groupCount to count of appGroups
                    set standardCount to 0
                    set allTitles to {}
                    repeat with grp in appGroups
                        repeat with btn in (every button of grp)
                            set t to title of btn as text
                            set end of allTitles to t
                            if t is "Update" or t is "Resume" or t is "Open" then
                                set standardCount to standardCount + 1
                            end if
                        end repeat
                    end repeat
                    set AppleScript's text item delimiters to ","
                    return (groupCount as text) & "|" & (standardCount as text) & "|" & (allTitles as text)
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // Timeout: kill after 2 seconds
        let timeoutWork = DispatchWorkItem { [weak task] in
            if task?.isRunning == true {
                print("[AppStoreDetector] killing hung process")
                task?.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutWork)

        task.terminationHandler = { [weak self] _ in
            timeoutWork.cancel()

            let data = pipe.fileHandleForReading.availableData
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0|0|"

            let parts = result.split(separator: "|", omittingEmptySubsequences: false)
            let groups = parts.count >= 1 ? Int(parts[0]) ?? 0 : 0
            let buttons = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
            let titles = parts.count > 2 ? String(parts[2]) : ""

            let isDownloading = groups > buttons
            print("[AppStoreDetector] groups=\(groups) buttons=\(buttons) titles=[\(titles)] downloading=\(isDownloading)")

            DispatchQueue.main.async {
                completion(isDownloading)
            }
        }

        do {
            try task.run()
        } catch {
            print("[AppStoreDetector] Error: \(error)")
            timeoutWork.cancel()
            completion(false)
        }
    }

    deinit {
        stopMonitoring()
    }
}
