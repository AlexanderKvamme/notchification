//
//  Detector.swift
//  Notchification
//
//  Protocol for all service detectors
//
//  IMPLEMENTATION GUIDE:
//  ---------------------
//  All detectors should follow these patterns:
//
//  1. Use a dedicated serial DispatchQueue for async work (prevents overlapping checks)
//  2. For terminal-based detectors, use TerminalScanner (handles AppleScript, timeouts, parsing)
//  3. Use consecutive readings before state changes (prevents flickering)
//  4. Avoid System Events "exists process" checks (causes -1712 timeouts)
//
//  See TerminalScanner.swift for shared terminal reading functionality.
//  See ClaudeDetector.swift for a reference implementation.
//

import Foundation

/// Protocol that all detectors conform to
protocol Detector: AnyObject {
    /// Whether this detector currently detects activity
    var isActive: Bool { get }

    /// The process type this detector handles
    var processType: ProcessType { get }

    /// Called by ProcessMonitor on each tick (1 second interval).
    /// Implementations should dispatch to their own serial queue to prevent overlapping.
    func poll()

    /// Reset state when detector is enabled/disabled
    func reset()
}
