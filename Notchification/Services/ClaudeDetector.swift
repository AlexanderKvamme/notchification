//
//  ClaudeDetector.swift
//  Notchification
//
//  Color: #D97757 (Claude orange)
//  Detects Claude Code activity by looking for status indicators in terminal
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "ClaudeDetector")

/// Detects if Claude Code is actively working
/// Uses AppleScript to read terminal content and look for status indicators
final class ClaudeDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {
        logger.info("🔶 ClaudeDetector init")
    }

    func startMonitoring() {
        logger.info("🔶 ClaudeDetector startMonitoring")
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

            let isWorking = self.isClaudeWorking()
            let debug = DebugSettings.shared.debugClaude

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if debug {
                        logger.debug("🔶 Claude active: \(self.consecutiveActiveReadings)/\(self.requiredToShow)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🔶 Claude started working")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if debug {
                        logger.debug("🔶 Claude inactive: \(self.consecutiveInactiveReadings)/\(self.requiredToHide)")
                    }

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🔶 Claude finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Claude Code is working by looking in terminal apps
    private func isClaudeWorking() -> Bool {
        // Check iTerm2
        if isClaudeActiveInITerm2() {
            return true
        }

        // Check Terminal.app
        if isClaudeActiveInTerminal() {
            return true
        }

        return false
    }

    /// Use AppleScript to check iTerm2 terminal content for Claude activity
    /// Only reads the last ~200 chars (bottom of terminal) to avoid matching old history
    private func isClaudeActiveInITerm2() -> Bool {
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
                        -- Only check the last 200 chars (roughly 2-3 lines)
                        if contentLength > 200 then
                            set recentContent to text (contentLength - 200) thru contentLength of sessionContent
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

        return hasClaudePattern(in: output)
    }

    /// Use AppleScript to check Terminal.app content for Claude activity
    /// Only reads the last ~200 chars (bottom of terminal) to avoid matching old history
    private func isClaudeActiveInTerminal() -> Bool {
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
                    -- Only check the last 200 chars (roughly 2-3 lines)
                    if contentLength > 200 then
                        set recentContent to text (contentLength - 200) thru contentLength of tabContent
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

        return hasClaudePattern(in: output)
    }

    /// Check if output contains Claude Code working pattern
    /// Claude shows status like: "✳ Adding ProcessType cases… (esc to interrupt · ctrl+t to show todos · 3m 28s)"
    /// The key indicators are the status characters combined with "esc to interrupt"
    private func hasClaudePattern(in output: String) -> Bool {
        // Must have "esc to interrupt" - this means Claude is actively working
        // This alone is sufficient - it only appears when Claude is processing
        return output.contains("esc to interrupt")
    }

    deinit {
        stopMonitoring()
    }
}
