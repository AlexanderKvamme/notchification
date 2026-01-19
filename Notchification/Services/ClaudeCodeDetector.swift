//
//  ClaudeCodeDetector.swift
//  Notchification
//
//  Color: #D97757 (Claude orange)
//  Detects Claude Code CLI activity by looking for status indicators in terminal
//
//  Uses shared TerminalScanner for terminal reading.
//  See TerminalScanner.swift and Detector.swift for architecture notes.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "ClaudeCodeDetector")

/// Detects if Claude Code CLI is actively working
/// Uses TerminalScanner to read terminal content and look for "esc to interrupt"
final class ClaudeCodeDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .claudeCode

    // Consecutive readings required (1 = instant, no delay)
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 1

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.claudecode-check", qos: .utility)

    // Prevents polls from queuing up if checks take longer than poll interval
    private let checkLock = NSLock()
    private var _isCheckInProgress = false
    private var isCheckInProgress: Bool {
        get { checkLock.lock(); defer { checkLock.unlock() }; return _isCheckInProgress }
        set { checkLock.lock(); defer { checkLock.unlock() }; _isCheckInProgress = newValue }
    }

    // Claude CLI-specific patterns (to distinguish from Codex)
    // Claude shows: "✢ Dilly-dallying… (esc to interrupt · thinking)"
    // Codex shows: "• Working (1s • esc to interrupt)"
    //
    // Key difference: Claude uses fancy Unicode spinners, Codex uses bullet •

    // Claude's spinner symbols (all possible spinner characters)
    // Includes flower/star glyphs, braille dots, and other spinners
    private let claudeSpinners: Set<Character> = [
        // Flower/star glyphs (confirmed Claude spinners)
        "✶", "✸", "✹", "✺", "✻", "✼", "✽", "✾", "✿",
        "❀", "❁", "❂", "❃", "❄", "❅", "❆", "❇",
        "✦", "✧", "✱", "✲", "✳", "✴", "✵", "✷",
        "✢", "✣", "✤", "✥",
        // Half circles
        "◐", "◓", "◑", "◒",
        // Braille dots (common CLI spinners)
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
        "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷",
        // Middle dot (Claude also uses this)
        "·"
    ]

    // Codex uses bullet point - NOT a Claude spinner
    private let codexBullet: Character = "•"

    // Debug logging toggle
    private var debug: Bool { DebugSettings.shared.debugClaudeCode }

    init() {
        logger.info("🔶 ClaudeCodeDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        guard !isCheckInProgress else { return }
        isCheckInProgress = true

        checkQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isCheckInProgress = false }

            let isWorking = self.isClaudeCodeWorking()

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.debug {
                        logger.debug("🔶 Claude Code active: \(self.consecutiveActiveReadings)/\(self.requiredToShow)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🔶 Claude Code started working")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.debug {
                        logger.debug("🔶 Claude Code inactive: \(self.consecutiveInactiveReadings)/\(self.requiredToHide)")
                    }

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🔶 Claude Code finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Claude Code CLI is working by scanning terminal apps
    private func isClaudeCodeWorking() -> Bool {
        let scanner = TerminalScanner(
            lineCount: 20,
            scanAllSessions: true,  // Check all sessions (Claude may be in background tab)
            useiTermContents: false  // Use 'text' (visible screen) - faster
        )

        // Check iTerm2
        let iTermStart = CFAbsoluteTimeGetCurrent()
        if let output = scanner.scanITerm2() {
            let iTermTime = (CFAbsoluteTimeGetCurrent() - iTermStart) * 1000
            if debug {
                print("🔶 iTerm2 check: \(String(format: "%.1f", iTermTime))ms")
            }
            if hasClaudePattern(in: output, scanner: scanner) {
                return true
            }
        } else if debug {
            print("🔶 iTerm2: not running")
        }

        // Check Terminal.app
        let terminalStart = CFAbsoluteTimeGetCurrent()
        if let output = scanner.scanTerminal() {
            let terminalTime = (CFAbsoluteTimeGetCurrent() - terminalStart) * 1000
            if debug {
                print("🔶 Terminal check: \(String(format: "%.1f", terminalTime))ms")
            }
            if hasClaudePattern(in: output, scanner: scanner) {
                return true
            }
        } else if debug {
            print("🔶 Terminal: not running")
        }

        return false
    }

    /// Check if Claude-specific patterns appear in the last lines of any session
    /// Claude shows: "✢ Dilly-dallying… (esc to interrupt · thinking)"
    /// Claude thinking shows: "✻ Frosting... (ctrl+c to interrupt • 1m 13s • ↓ 5.1k tokens)"
    /// Codex shows: "• Working (1s • esc to interrupt)"
    private func hasClaudePattern(in output: String, scanner: TerminalScanner) -> Bool {
        let sessions = scanner.parseSessions(from: output)
        let checkLineCount = 7

        for session in sessions {
            let lastLines = Array(session.lastLines.suffix(checkLineCount))

            if debug {
                print("🔶 Last \(checkLineCount) non-empty lines:")
                for (i, line) in lastLines.enumerated() {
                    print("🔶   [\(i+1)] \(line.prefix(100))")
                }
            }

            for line in lastLines {
                // Must have "esc" or "ctrl" somewhere in the line (different interrupt methods)
                // Normal mode: "esc to interrupt"
                // Thinking mode: "ctrl+c to interrupt"
                guard line.contains("esc") || line.contains("ctrl") else { continue }

                // Check the first few characters for a spinner symbol
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let prefix = String(trimmed.prefix(5))  // Check first 5 chars

                if debug {
                    let chars = prefix.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                    print("🔶 Checking line prefix: '\(prefix)' [\(chars)]")
                }

                // Skip if line starts with Codex bullet
                if trimmed.hasPrefix(String(codexBullet)) {
                    if debug {
                        print("🔶 SKIP (Codex bullet): \(line.prefix(100))")
                    }
                    continue
                }

                // Match if any Claude spinner appears at the start
                for spinner in claudeSpinners {
                    if trimmed.hasPrefix(String(spinner)) {
                        if debug {
                            print("🔶 MATCH (spinner '\(spinner)'): \(line.prefix(100))")
                        }
                        return true
                    }
                }
            }
        }

        if debug {
            print("🔶 No match")
        }

        return false
    }
}
