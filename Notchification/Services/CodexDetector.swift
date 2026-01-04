//
//  CodexDetector.swift
//  Notchification
//
//  Color: #F9F9F9 (OpenAI light gray)
//  Detects Codex CLI activity by looking for "Working" status in terminal
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "CodexDetector")

/// Detects if Codex CLI is actively working
/// Uses AppleScript to read terminal content
final class CodexDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {
        logger.info("🤖 CodexDetector init")
    }

    func startMonitoring() {
        logger.info("🤖 CodexDetector startMonitoring")
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let isWorking = self.isCodexWorking()

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🤖 Codex started working")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🤖 Codex finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Codex is working by looking in terminal apps
    private func isCodexWorking() -> Bool {
        // Check iTerm2
        if isCodexActiveInITerm2() {
            return true
        }

        // Check Terminal.app
        if isCodexActiveInTerminal() {
            return true
        }

        return false
    }

    /// Use AppleScript to check iTerm2 terminal content for Codex activity
    private func isCodexActiveInITerm2() -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then return "NOT_RUNNING"
        end tell

        tell application "iTerm2"
            set allContent to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionContent to contents of s
                        set contentLength to length of sessionContent
                        if contentLength > 3000 then
                            set recentContent to text (contentLength - 3000) thru contentLength of sessionContent
                        else
                            set recentContent to sessionContent
                        end if
                        set allContent to allContent & "---SESSION---" & recentContent
                    end repeat
                end repeat
            end repeat
            return allContent
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
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "NOT_RUNNING" else {
            return false
        }

        return hasCodexPattern(in: output)
    }

    /// Use AppleScript to check Terminal.app content for Codex activity
    private func isCodexActiveInTerminal() -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return "NOT_RUNNING"
        end tell

        tell application "Terminal"
            set allContent to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabContent to history of t
                    set contentLength to length of tabContent
                    if contentLength > 3000 then
                        set recentContent to text (contentLength - 3000) thru contentLength of tabContent
                    else
                        set recentContent to tabContent
                    end if
                    set allContent to allContent & "---TAB---" & recentContent
                end repeat
            end repeat
            return allContent
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
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "NOT_RUNNING" else {
            return false
        }

        return hasCodexPattern(in: output)
    }

    /// Check if output contains Codex "Working" pattern
    /// Looks for "Working" and "esc to interrupt" appearing together
    private func hasCodexPattern(in output: String) -> Bool {
        // Check for "Working" and "esc to interrupt" in the output
        // They appear on the same line: "Working (0s • esc to interrupt)"
        return output.contains("Working") && output.contains("esc to interrupt")
    }

    deinit {
        stopMonitoring()
    }
}
