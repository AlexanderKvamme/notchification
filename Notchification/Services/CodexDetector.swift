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

        if let output = scanner.scan() {
            if debug {
                print("🤖 Codex: scanning terminals...")
            }
            return hasCodexPattern(in: output, scanner: scanner)
        }

        return false
    }

    /// Check if "Working" + "esc to interrupt" appears in the last 10 lines of any session
    private func hasCodexPattern(in output: String, scanner: TerminalScanner) -> Bool {
        let debug = DebugSettings.shared.debugCodex
        let sessions = scanner.parseSessions(from: output)

        for session in sessions {
            for line in session.lastLines {
                if line.contains("Working") && line.contains("esc to interrupt") {
                    if debug {
                        print("🤖 MATCH: \(line.prefix(80))")
                    }
                    return true
                }
            }
        }

        return false
    }
}
