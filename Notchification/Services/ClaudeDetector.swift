//
//  ClaudeDetector.swift
//  Notchification
//
//  Color: #D97757 (Claude orange)
//  Detects Claude Code activity by looking for status indicators in terminal
//
//  Uses shared TerminalScanner for terminal reading.
//  See TerminalScanner.swift and Detector.swift for architecture notes.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "ClaudeDetector")

/// Detects if Claude Code is actively working
/// Uses TerminalScanner to read terminal content and look for "esc to interrupt"
final class ClaudeDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .claude

    // Consecutive readings required (1 = instant, no delay)
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 1

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.claude-check", qos: .utility)

    // Prevents polls from queuing up if checks take longer than poll interval
    private let checkLock = NSLock()
    private var _isCheckInProgress = false
    private var isCheckInProgress: Bool {
        get { checkLock.lock(); defer { checkLock.unlock() }; return _isCheckInProgress }
        set { checkLock.lock(); defer { checkLock.unlock() }; _isCheckInProgress = newValue }
    }

    // Search pattern built at runtime to avoid false positives when source code is shown in terminal
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
        guard !isCheckInProgress else { return }
        isCheckInProgress = true

        checkQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isCheckInProgress = false }

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

    /// Check if Claude Code is working by scanning terminal apps
    private func isClaudeWorking() -> Bool {
        let debug = DebugSettings.shared.debugClaude
        let scanAll = DebugSettings.shared.claudeScanAllSessions

        let scanner = TerminalScanner(
            lineCount: 20,
            scanAllSessions: scanAll,
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

    /// Check if "esc to interrupt" appears in the last 5 lines of any session
    private func hasClaudePattern(in output: String, scanner: TerminalScanner) -> Bool {
        let debug = DebugSettings.shared.debugClaude
        let sessions = scanner.parseSessions(from: output)
        let lineCount = 7
        
        for session in sessions {
            let last5 = Array(session.lastLines.suffix(7))

            // DEBUG: Print last 5 lines (helps diagnose detection issues)
            if debug {
                print("🔶 Last \(lineCount) lines:")
                for (i, line) in last5.enumerated() {
                    print("🔶   [\(i+1)] \(line.prefix(80))")
                }
            }

            for line in last5 {
                // Skip lines that look like Codex (has "Working" + "esc to interrupt")
                if line.contains("Working") {
                    continue
                }
                if line.contains(escPattern) {
                    if debug {
                        print("🔶 MATCH: \(line.prefix(80))")
                    }
                    return true
                }
            }
        }

        if debug {
            print("🔶 No match")
        }

        return false
    }
}
