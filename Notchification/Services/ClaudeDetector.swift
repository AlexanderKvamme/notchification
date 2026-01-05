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
//  3. Last 20 lines only: We get 'contents' from iTerm2 but only keep the last 20
//     lines per session. This avoids reading old scrollback and focuses on
//     the actual bottom of the terminal where the Claude status bar appears.
//     Using lines instead of characters avoids separator lines (────) eating up the limit.
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

    // Consecutive readings required (1 = instant, no delay)
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 1

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
    // This pattern indicates Claude Code is actively working (see Claude Code docs)
    private let escPattern = ["esc", "to", "interrupt"].joined(separator: " ")

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

    /// Use AppleScript to get iTerm2 terminal content - only the last 20 lines per session
    private func isClaudeActiveInITerm2() -> Bool {
        let scanAll = DebugSettings.shared.claudeScanAllSessions

        // Fast path: only check frontmost session (default)
        // Slow path: check all sessions (when claudeScanAllSessions is enabled)
        // NOTE: We get the last 20 lines instead of last N characters to avoid
        // separator lines (────) eating up the limit
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
                            set lineList to paragraphs of sessionText
                            set lineCount to count of lineList
                            if lineCount > 20 then
                                set lineList to items (lineCount - 19) thru lineCount of lineList
                            end if
                            set AppleScript's text item delimiters to linefeed
                            set sessionText to lineList as text
                            set AppleScript's text item delimiters to ""
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
                set lineList to paragraphs of sessionText
                set lineCount to count of lineList
                if lineCount > 20 then
                    set lineList to items (lineCount - 19) thru lineCount of lineList
                end if
                set AppleScript's text item delimiters to linefeed
                set sessionText to lineList as text
                set AppleScript's text item delimiters to ""
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

    /// Use AppleScript to get Terminal.app content - only the last 20 lines per tab
    private func isClaudeActiveInTerminal() -> Bool {
        let scanAll = DebugSettings.shared.claudeScanAllSessions

        // Fast path: only check frontmost tab (default)
        // Slow path: check all tabs (when claudeScanAllSessions is enabled)
        // NOTE: We get the last 20 lines instead of last N characters to avoid
        // separator lines (────) eating up the limit
        let script: String
        if scanAll {
            script = """
            tell application "Terminal"
                if not running then return "NOT_RUNNING"
                set allContent to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabText to history of t
                        set lineList to paragraphs of tabText
                        set lineCount to count of lineList
                        if lineCount > 20 then
                            set lineList to items (lineCount - 19) thru lineCount of lineList
                        end if
                        set AppleScript's text item delimiters to linefeed
                        set tabText to lineList as text
                        set AppleScript's text item delimiters to ""
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
                set lineList to paragraphs of tabText
                set lineCount to count of lineList
                if lineCount > 20 then
                    set lineList to items (lineCount - 19) thru lineCount of lineList
                end if
                set AppleScript's text item delimiters to linefeed
                set tabText to lineList as text
                set AppleScript's text item delimiters to ""
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
    /// Looks for patterns: "esc to interrupt" OR "accept edits on"
    /// DEBUG NOTE: Never remove the debug prints below - they are essential for diagnosing issues
    private func hasClaudePattern(in output: String) -> Bool {
        let debug = DebugSettings.shared.debugClaude

        // Split by session/tab separator - use SESSION for iTerm2, TAB for Terminal.app
        let sessions: [String]
        if output.contains("---SESSION---") {
            sessions = output.components(separatedBy: "---SESSION---").filter { !$0.isEmpty }
        } else if output.contains("---TAB---") {
            sessions = output.components(separatedBy: "---TAB---").filter { !$0.isEmpty }
        } else {
            // No separator found - treat entire output as one session
            sessions = [output]
        }

        for session in sessions {
            guard !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let lines = session.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let last5 = Array(lines.suffix(5))

            // DEBUG: Print last 5 lines (NEVER REMOVE THIS)
            if debug {
                print("🔶 Last 5 lines:")
                for (i, line) in last5.enumerated() {
                    print("🔶   [\(i+1)] \(line.prefix(80))")
                }
            }

            for line in last5 {
                if line.contains(escPattern) {
                    if debug {
                        print("🔶 MATCH: \(line.prefix(80))")
                    }
                    return true
                }
            }
        }

        // DEBUG: Log when no pattern found (NEVER REMOVE THIS)
        if debug {
            print("🔶 No match")
        }

        return false
    }
}
