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
//  3. Last 500 chars only: We get 'contents' from iTerm2 but only keep the last 500
//     characters per session. This avoids reading old scrollback and focuses on
//     the actual bottom of the terminal where the Claude status bar appears.
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

    // Prevents polls from queuing up if checks take longer than poll interval
    private let checkLock = NSLock()
    private var _isCheckInProgress = false
    private var isCheckInProgress: Bool {
        get { checkLock.lock(); defer { checkLock.unlock() }; return _isCheckInProgress }
        set { checkLock.lock(); defer { checkLock.unlock() }; _isCheckInProgress = newValue }
    }

    // Search pattern built at runtime to avoid false positives when source code is shown in terminal
    // The pattern indicates Claude Code is actively working (see Claude Code docs)
    private let searchPattern = ["esc", "to", "interrupt"].joined(separator: " ")

    init() {
        logger.info("🔶 ClaudeDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        // Skip if a check is already in progress - prevents queue buildup
        guard !isCheckInProgress else { return }
        isCheckInProgress = true

        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isCheckInProgress = false }

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
        let debug = DebugSettings.shared.debugClaude

        // Check iTerm2
        let iTermStart = CFAbsoluteTimeGetCurrent()
        let iTermResult = isClaudeActiveInITerm2()
        let iTermTime = (CFAbsoluteTimeGetCurrent() - iTermStart) * 1000

        if debug {
            print("🔶 iTerm2 check: \(String(format: "%.1f", iTermTime))ms")
        }

        if iTermResult {
            return true
        }

        // Check Terminal.app
        let terminalStart = CFAbsoluteTimeGetCurrent()
        let terminalResult = isClaudeActiveInTerminal()
        let terminalTime = (CFAbsoluteTimeGetCurrent() - terminalStart) * 1000

        if debug {
            print("🔶 Terminal check: \(String(format: "%.1f", terminalTime))ms")
            print("🔶 Total check time: \(String(format: "%.1f", iTermTime + terminalTime))ms")
        }

        if terminalResult {
            return true
        }

        return false
    }

    /// Use AppleScript to get iTerm2 terminal content - only the last 500 chars per session
    private func isClaudeActiveInITerm2() -> Bool {
        let scanAll = DebugSettings.shared.claudeScanAllSessions

        // Fast path: only check frontmost session (default)
        // Slow path: check all sessions (when claudeScanAllSessions is enabled)
        let script: String
        if scanAll {
            script = """
            tell application "iTerm2"
                if not running then return "NOT_RUNNING"
                set allContent to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set sessionText to contents of s
                            set textLen to length of sessionText
                            if textLen > 500 then
                                set sessionText to text (textLen - 499) thru textLen of sessionText
                            end if
                            set allContent to allContent & "---SESSION---" & sessionText
                        end repeat
                    end repeat
                end repeat
                return allContent
            end tell
            """
        } else {
            // Fast: only frontmost session
            script = """
            tell application "iTerm2"
                if not running then return "NOT_RUNNING"
                if (count of windows) = 0 then return "NO_WINDOWS"
                set sessionText to contents of current session of current window
                set textLen to length of sessionText
                if textLen > 500 then
                    set sessionText to text (textLen - 499) thru textLen of sessionText
                end if
                return "---SESSION---" & sessionText
            end tell
            """
        }

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

    /// Use AppleScript to get Terminal.app content - only the last 500 chars per tab
    private func isClaudeActiveInTerminal() -> Bool {
        let scanAll = DebugSettings.shared.claudeScanAllSessions

        // Fast path: only check frontmost tab (default)
        // Slow path: check all tabs (when claudeScanAllSessions is enabled)
        let script: String
        if scanAll {
            script = """
            tell application "Terminal"
                if not running then return "NOT_RUNNING"
                set allContent to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabText to history of t
                        set textLen to length of tabText
                        if textLen > 500 then
                            set tabText to text (textLen - 499) thru textLen of tabText
                        end if
                        set allContent to allContent & "---TAB---" & tabText
                    end repeat
                end repeat
                return allContent
            end tell
            """
        } else {
            // Fast: only frontmost tab
            script = """
            tell application "Terminal"
                if not running then return "NOT_RUNNING"
                if (count of windows) = 0 then return "NO_WINDOWS"
                set tabText to history of selected tab of front window
                set textLen to length of tabText
                if textLen > 500 then
                    set tabText to text (textLen - 499) thru textLen of tabText
                end if
                return "---TAB---" & tabText
            end tell
            """
        }

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

    /// Check if the Claude status indicator appears in the last 5 non-empty lines of ANY session
    /// Looks for the pattern: [esc] + [to] + [interrupt] to detect active Claude Code
    /// DEBUG NOTE: Never remove the debug prints below - they are essential for diagnosing issues
    private func hasClaudePattern(in output: String) -> Bool {
        let debug = DebugSettings.shared.debugClaude

        // Split by session/tab separator and check each one
        // Note: We split by both separators separately, then combine (excluding empty first elements)
        var sessions: [String] = []
        let sessionSplit = output.components(separatedBy: "---SESSION---").filter { !$0.isEmpty }
        let tabSplit = output.components(separatedBy: "---TAB---").filter { !$0.isEmpty }
        sessions.append(contentsOf: sessionSplit)
        sessions.append(contentsOf: tabSplit)

        if debug {
            print("🔶 ═══════════════════════════════════════════════════")
            print("🔶 Searching for pattern: '\(searchPattern)'")
            print("🔶 Total sessions found: \(sessions.count)")
            print("🔶 Raw output length: \(output.count) chars")
        }

        for (sessionIndex, session) in sessions.enumerated() {
            // Skip empty sessions
            guard !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            // Get last 5 non-empty lines of this session (Claude status bar is at the very bottom)
            let lines = session.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let last5 = Array(lines.suffix(5))

            // Check if pattern exists in this session's last 5 lines only
            var foundInSession = false
            var foundLine = ""
            for line in last5 {
                if line.contains(searchPattern) {
                    foundInSession = true
                    foundLine = line
                    break
                }
            }

            // DEBUG: Print session info (NEVER REMOVE THIS)
            if debug && !last5.isEmpty {
                let status = foundInSession ? "⚡ MATCH" : "✗ No match"
                print("🔶 [Session \(sessionIndex)] \(status) | Total lines: \(lines.count) | Last 5:")
                for (i, line) in last5.enumerated() {
                    let marker = line.contains(searchPattern) ? ">>>" : "   "
                    print("🔶 \(marker) [\(i+1)] \(line.prefix(100))")
                }
            }

            if foundInSession {
                return true
            }
        }

        // DEBUG: Log when no pattern found (NEVER REMOVE THIS)
        if debug {
            print("🔶 No match found in any session")
        }

        return false
    }
}
