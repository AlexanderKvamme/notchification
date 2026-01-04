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

    /// Use AppleScript to get iTerm2 terminal content
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
                        set allContent to allContent & "---SESSION---" & contents of s
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

    /// Use AppleScript to get Terminal.app content
    private func isClaudeActiveInTerminal() -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return "NOT_RUNNING"
        end tell

        tell application "Terminal"
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
                    if DebugSettings.shared.debugClaude {
                        print("🔶 Claude FOUND: \(line.prefix(100))")
                    }
                    return true
                }
            }
        }

        return false
    }

    deinit {
        stopMonitoring()
    }
}
