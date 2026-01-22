//
//  CodexDetector.swift
//  Notchification
//
//  Color: #F9F9F9 (OpenAI light gray)
//  Detects Codex CLI activity by looking for "Working" + "esc to interrupt" in terminal
//
//  Uses shared TerminalScanner for terminal reading.
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "CodexDetector")

/// Detects if Codex CLI is actively working
/// Uses TerminalScanner to read terminal content
final class CodexDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .codex

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Throttling to reduce power usage (AppleScript is expensive)
    private var pollCount: Int = 0
    private let throttleInterval: Int = 3

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.codex-check", qos: .utility)

    init() {
        logger.info("🤖 CodexDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        pollCount = 0
        isActive = false
    }

    func poll() {
        pollCount += 1

        // Throttle when idle to save power (AppleScript is expensive)
        if !isActive && pollCount % throttleInterval != 0 {
            return
        }

        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let isWorking = self.isCodexWorking()
            let debug = DebugSettings.shared.debugCodex

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if debug {
                        print("🤖 Codex active: \(self.consecutiveActiveReadings)/\(self.requiredToShow)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🤖 Codex started working")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if debug {
                        print("🤖 Codex inactive: \(self.consecutiveInactiveReadings)/\(self.requiredToHide)")
                    }

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🤖 Codex finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Codex is working by scanning terminal apps
    private func isCodexWorking() -> Bool {
        let debug = DebugSettings.shared.debugCodex

        // Codex uses 'text' (visible screen) - faster than scrollback
        let scanner = TerminalScanner(
            lineCount: 10,
            scanAllSessions: true,  // Check all sessions for Codex
            useiTermContents: false // Use 'text' (visible only) for speed
        )

        if debug {
            print("🤖 Codex: scanning terminals...")
        }

        // Check iTerm2
        let iTermStart = CFAbsoluteTimeGetCurrent()
        if let output = scanner.scanITerm2() {
            let iTermTime = (CFAbsoluteTimeGetCurrent() - iTermStart) * 1000
            if debug {
                print("🤖 iTerm2 check: \(String(format: "%.1f", iTermTime))ms")
            }
            if hasCodexPattern(in: output, scanner: scanner) {
                return true
            }
        } else if debug {
            print("🤖 iTerm2: not running")
        }

        // Check Terminal.app
        let terminalStart = CFAbsoluteTimeGetCurrent()
        if let output = scanner.scanTerminal() {
            let terminalTime = (CFAbsoluteTimeGetCurrent() - terminalStart) * 1000
            if debug {
                print("🤖 Terminal check: \(String(format: "%.1f", terminalTime))ms")
            }
            if hasCodexPattern(in: output, scanner: scanner) {
                return true
            }
        } else if debug {
            print("🤖 Terminal: not running")
        }

        return false
    }

    /// Codex bullet point - used to identify Codex vs Claude
    private let codexBullet: Character = "•"

    /// Regex to match Codex timing pattern: (1s •, (9s •, (54s •, etc.
    /// This pattern is specific to Codex and distinguishes it from Claude.
    /// DO NOT remove this check - it prevents false positives with Claude CLI.
    private let timingPattern = try! NSRegularExpression(pattern: #"\(\d+s •"#)

    /// Check if Codex pattern appears in terminal output
    /// Codex shows: "• [action] (Xs • esc to interrupt)"
    /// Examples:
    ///   • Working (1s • esc to interrupt)
    ///   • Searching for pattern detection (9s • esc to interrupt)
    ///   • Analyzing terminal output parsing issues (54s • esc to interrupt)
    private func hasCodexPattern(in output: String, scanner: TerminalScanner) -> Bool {
        let debug = DebugSettings.shared.debugCodex
        let sessions = scanner.parseSessions(from: output)

        if debug {
            print("🤖 Checking \(sessions.count) sessions...")
        }

        for (sessionIdx, session) in sessions.enumerated() {
            if debug {
                print("🤖 Session \(sessionIdx + 1) - \(session.lastLines.count) lines:")
                for (i, line) in session.lastLines.enumerated() {
                    print("🤖   [\(i+1)] \(line.prefix(100))")
                }
            }

            for line in session.lastLines {
                // Must have "esc to interrupt" somewhere in the line
                guard line.contains("esc to interrupt") else { continue }

                // Check if line starts with Codex bullet •
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(String(codexBullet)) else { continue }

                // Check for timing pattern (Xs • - this is specific to Codex
                let range = NSRange(line.startIndex..., in: line)
                if timingPattern.firstMatch(in: line, range: range) != nil {
                    if debug {
                        print("🤖 MATCH: \(line.prefix(100))")
                    }
                    return true
                }
            }
        }

        if debug {
            print("🤖 No match found")
        }

        return false
    }
}
