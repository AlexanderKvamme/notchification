//
//  ClaudeDetector.swift
//  Notchification
//
//  Color: #D97757 (Claude orange)
//  Detects Claude Code activity by looking for status indicators in terminal
//
//  ARCHITECTURE NOTES:
//  -------------------
//  1. Serial Queue: All detectors use a dedicated serial DispatchQueue instead of
//     DispatchQueue.global(). This prevents overlapping checks - if a check takes
//     longer than the 1-second poll interval, subsequent polls queue up rather than
//     running concurrently (which caused stuck states).
//
//  2. Timeouts: AppleScript/osascript calls have a 2-second timeout. Without this,
//     a hanging osascript would block the serial queue forever.
//
//  3. 'text' vs 'contents': For iTerm2, we use the 'text' property (visible screen)
//     instead of 'contents' (full scrollback). 'contents' can take 2-3 seconds on
//     large scrollbacks, while 'text' is instant. Since we only need the last 10
//     lines to detect "esc to interrupt", visible screen is sufficient.
//
//  4. No System Events check: We removed "tell application System Events" checks
//     like "if exists process X". These cause -1712 timeout errors when run from
//     within the app. Instead, we use "if not running" directly in the app's tell block.
//
//  5. Consecutive readings: We require multiple consecutive readings before changing
//     state. This prevents flickering from transient states.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "ClaudeDetector")

/// Detects if Claude Code is actively working
/// Uses AppleScript to read terminal content and look for status indicators
final class ClaudeDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .claude

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // See ARCHITECTURE NOTES at top of file for why we use serial queue
    private let checkQueue = DispatchQueue(label: "com.notchification.claude-check", qos: .utility)

    init() {
        logger.info("🔶 ClaudeDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let isWorking = self.isClaudeWorking()
            let debug = DebugSettings.shared.debugClaude

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    // NOTE: Keep debug logs - helps diagnose detection issues
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

                    // NOTE: Keep debug logs - helps diagnose detection issues
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

    /// Use AppleScript to get iTerm2 terminal content
    private func isClaudeActiveInITerm2() -> Bool {
        // Use 'text' (visible screen) instead of 'contents' (full scrollback).
        // 'contents' can take 2-3 seconds on large scrollbacks, while 'text' is instant.
        // Since we only need the last 10 lines to detect "esc to interrupt", visible screen is sufficient.
        let script = """
        tell application "iTerm2"
            if not running then return "NOT_RUNNING"
            set allContent to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set allContent to allContent & "---SESSION---" & text of s
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

        // Timeout after 2 seconds (text property is fast, but osascript can hang)
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
        } catch {
            timeoutWork.cancel()
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "NOT_RUNNING" else {
            return false
        }

        return hasClaudePattern(in: output)
    }

    /// Use AppleScript to get Terminal.app content
    private func isClaudeActiveInTerminal() -> Bool {
        // Skip System Events check - it causes timeouts
        let script = """
        tell application "Terminal"
            if not running then return "NOT_RUNNING"
            set allContent to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set allContent to allContent & "---TAB---" & history of t
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

        // Timeout after 2 seconds (text property is fast, but osascript can hang)
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
        } catch {
            timeoutWork.cancel()
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "NOT_RUNNING" else {
            return false
        }

        return hasClaudePattern(in: output)
    }

    /// Check if "esc to interrupt" appears in the last 10 non-empty lines of ANY session
    private func hasClaudePattern(in output: String) -> Bool {
        // Split by session/tab separator and check each one
        let sessions = output.components(separatedBy: "---SESSION---") +
                       output.components(separatedBy: "---TAB---")

        for session in sessions {
            // Get last 10 non-empty lines of this session
            let lines = session.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .suffix(10)

            for line in lines {
                if line.contains("esc to interrupt") {
                    // NOTE: Keep this debug output - helps diagnose detection issues
                    if DebugSettings.shared.debugClaude {
                        print("🔶 Claude FOUND: \(line.prefix(100))")
                    }
                    return true
                }
            }
        }

        return false
    }
}
