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
final class CodexDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .codex

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.codex-check", qos: .utility)

    init() {
        logger.info("🤖 CodexDetector init")
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
        if isCodexActiveInITerm2() {
            return true
        }

        if isCodexActiveInTerminal() {
            return true
        }

        return false
    }

    /// Use AppleScript to get iTerm2 terminal content
    private func isCodexActiveInITerm2() -> Bool {
        // Use 'text' (visible screen) instead of 'contents' (full scrollback) for speed
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

        // Timeout after 2 seconds
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

        return hasCodexPattern(in: output)
    }

    /// Use AppleScript to get Terminal.app content
    private func isCodexActiveInTerminal() -> Bool {
        // Note: Terminal.app uses 'history' property (no 'text' equivalent)
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

        // Timeout after 2 seconds
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

        return hasCodexPattern(in: output)
    }

    /// Check if "Working" + "esc to interrupt" appears in the last 10 non-empty lines of ANY session
    private func hasCodexPattern(in output: String) -> Bool {
        let sessions = output.components(separatedBy: "---SESSION---") +
                       output.components(separatedBy: "---TAB---")

        for session in sessions {
            let lines = session.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .suffix(10)

            for line in lines {
                if line.contains("Working") && line.contains("esc to interrupt") {
                    return true
                }
            }
        }

        return false
    }
}
