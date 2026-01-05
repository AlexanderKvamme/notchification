//
//  TerminalScanner.swift
//  Notchification
//
//  Shared utility for scanning terminal content (iTerm2 and Terminal.app)
//  Used by ClaudeDetector, CodexDetector, OpencodeDetector, and future CLI detectors
//
//  USAGE:
//  ------
//  let scanner = TerminalScanner(
//      lineCount: 20,           // Get last N lines
//      scanAllSessions: false,  // true = all windows/tabs, false = frontmost only
//      useiTermContents: true   // true = 'contents' (scrollback), false = 'text' (visible)
//  )
//  if let output = scanner.scan() {
//      let sessions = scanner.parseSessions(from: output)
//      for session in sessions {
//          // Check your patterns in session.lastLines
//      }
//  }
//

import Foundation

/// Result from scanning a terminal session
struct TerminalSession {
    let content: String
    let lastLines: [String]
}

/// Scans iTerm2 and Terminal.app for content
final class TerminalScanner {
    /// Number of lines to get from the end
    let lineCount: Int

    /// Whether to scan all sessions/tabs or just frontmost
    let scanAllSessions: Bool

    /// For iTerm2: true = 'contents' (full scrollback), false = 'text' (visible screen only)
    let useiTermContents: Bool

    /// Timeout for AppleScript calls in seconds
    let timeout: TimeInterval

    init(
        lineCount: Int = 20,
        scanAllSessions: Bool = false,
        useiTermContents: Bool = true,
        timeout: TimeInterval = 2.0
    ) {
        self.lineCount = lineCount
        self.scanAllSessions = scanAllSessions
        self.useiTermContents = useiTermContents
        self.timeout = timeout
    }

    /// Scan both iTerm2 and Terminal.app, returns combined output or nil if both not running
    func scan() -> String? {
        var results: [String] = []

        if let iTerm = scanITerm2() {
            results.append(iTerm)
        }

        if let terminal = scanTerminal() {
            results.append(terminal)
        }

        return results.isEmpty ? nil : results.joined(separator: "\n")
    }

    /// Scan only iTerm2
    func scanITerm2() -> String? {
        let contentProperty = useiTermContents ? "contents" : "text"

        let script: String
        if scanAllSessions {
            script = """
            tell application "iTerm2"
                if not running then return "NOT_RUNNING"
                set allContent to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set sessionText to \(contentProperty) of s
                            set lineList to paragraphs of sessionText
                            set lineCount to count of lineList
                            if lineCount > \(lineCount) then
                                set lineList to items (lineCount - \(lineCount - 1)) thru lineCount of lineList
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
            script = """
            tell application "iTerm2"
                if not running then return "NOT_RUNNING"
                if (count of windows) = 0 then return "NO_WINDOWS"
                set sessionText to \(contentProperty) of current session of current window
                set lineList to paragraphs of sessionText
                set lineCount to count of lineList
                if lineCount > \(lineCount) then
                    set lineList to items (lineCount - \(lineCount - 1)) thru lineCount of lineList
                end if
                set AppleScript's text item delimiters to linefeed
                set sessionText to lineList as text
                set AppleScript's text item delimiters to ""
                return "---SESSION---" & sessionText
            end tell
            """
        }

        return runAppleScript(script)
    }

    /// Scan only Terminal.app
    func scanTerminal() -> String? {
        let script: String
        if scanAllSessions {
            script = """
            tell application "Terminal"
                if not running then return "NOT_RUNNING"
                set allContent to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabText to history of t
                        set lineList to paragraphs of tabText
                        set lineCount to count of lineList
                        if lineCount > \(lineCount) then
                            set lineList to items (lineCount - \(lineCount - 1)) thru lineCount of lineList
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
            script = """
            tell application "Terminal"
                if not running then return "NOT_RUNNING"
                if (count of windows) = 0 then return "NO_WINDOWS"
                set tabText to history of selected tab of front window
                set lineList to paragraphs of tabText
                set lineCount to count of lineList
                if lineCount > \(lineCount) then
                    set lineList to items (lineCount - \(lineCount - 1)) thru lineCount of lineList
                end if
                set AppleScript's text item delimiters to linefeed
                set tabText to lineList as text
                set AppleScript's text item delimiters to ""
                return "---TAB---" & tabText
            end tell
            """
        }

        return runAppleScript(script)
    }

    /// Parse the raw output into individual sessions
    func parseSessions(from output: String) -> [TerminalSession] {
        var sessions: [TerminalSession] = []

        // Split by session/tab separator
        let parts: [String]
        if output.contains("---SESSION---") {
            parts = output.components(separatedBy: "---SESSION---").filter { !$0.isEmpty }
        } else if output.contains("---TAB---") {
            parts = output.components(separatedBy: "---TAB---").filter { !$0.isEmpty }
        } else {
            parts = [output]
        }

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let lines = trimmed.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            sessions.append(TerminalSession(
                content: trimmed,
                lastLines: Array(lines.suffix(lineCount))
            ))
        }

        return sessions
    }

    /// Check if any session contains a pattern in its last lines
    func containsPattern(_ pattern: String, in output: String) -> Bool {
        let sessions = parseSessions(from: output)
        for session in sessions {
            for line in session.lastLines {
                if line.contains(pattern) {
                    return true
                }
            }
        }
        return false
    }

    /// Check if any session matches a custom predicate in its last lines
    func matchesInLastLines(in output: String, predicate: ([String]) -> Bool) -> Bool {
        let sessions = parseSessions(from: output)
        for session in sessions {
            if predicate(session.lastLines) {
                return true
            }
        }
        return false
    }

    // MARK: - Private

    private func runAppleScript(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // Timeout
        let timeoutWork = DispatchWorkItem { [weak task] in
            if task?.isRunning == true {
                task?.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        do {
            try task.run()
            task.waitUntilExit()
            timeoutWork.cancel()
        } catch {
            timeoutWork.cancel()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "NOT_RUNNING",
              output != "NO_WINDOWS" else {
            return nil
        }

        return output
    }
}
