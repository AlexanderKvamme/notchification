//
//  WarpDetector.swift
//  Notchification
//
//  Detects active work in Warp by reading the visible terminal text via Accessibility.
//  Warp exposes the terminal contents as an AXTextArea value; the active Pi status is
//  visible in the last few lines as "Thinking..." or "Working...".
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "WarpDetector")

/// Detects if an AI agent running in Warp is actively thinking/working.
final class WarpDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .warp

    private let bundleIdentifier = "dev.warp.Warp-Stable"
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2
    // Warp/Pi puts the live status a few lines above the bottom because the
    // powerline/footer, prompt, divider, and echoed prompt can follow it.
    // In testing "Working..." can sit up to ~10 lines from the bottom because
    // the powerline/footer, prompt, dividers, and echoed prompt follow it.
    private let lastLineCount: Int = 10

    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0
    private var pollCount: Int = 0
    private let throttleInterval: Int = 2

    private let checkQueue = DispatchQueue(label: "com.notchification.warp-check", qos: .utility)
    private let checkLock = NSLock()
    private var _isCheckInProgress = false
    private var isCheckInProgress: Bool {
        get { checkLock.lock(); defer { checkLock.unlock() }; return _isCheckInProgress }
        set { checkLock.lock(); defer { checkLock.unlock() }; _isCheckInProgress = newValue }
    }

    private var debug: Bool { DebugSettings.shared.debugWarp }

    init() {
        logger.info("🌀 WarpDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        pollCount = 0
        isActive = false
    }

    func poll() {
        guard !isCheckInProgress else { return }

        pollCount += 1
        if !isActive && pollCount % throttleInterval != 0 {
            return
        }

        isCheckInProgress = true

        checkQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isCheckInProgress = false }

            let (isWorking, statusText) = self.isWarpWorking()

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.debug {
                        print("🌀 Warp active: \(statusText)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🌀 Warp started working: \(statusText)")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.debug {
                        print("🌀 Warp inactive: \(statusText)")
                    }

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🌀 Warp finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    private func isWarpWorking() -> (Bool, String) {
        guard let warpApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            if debug { print("🌀 Warp: not running") }
            return (false, "Warp not running")
        }

        let appElement = AXUIElementCreateApplication(warpApp.processIdentifier)

        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            if debug { print("🌀 Warp: no accessible windows (result=\(result.rawValue))") }
            return (false, "No accessible windows")
        }

        for window in windows {
            if let text = findTerminalText(in: window) {
                let lines = lastNonEmptyLines(from: text, count: lastLineCount)

                if debug {
                    print("🌀 Warp last \(lastLineCount) lines:")
                    for (index, line) in lines.enumerated() {
                        print("🌀   [\(index + 1)] \(line.prefix(140))")
                    }
                }

                if let activeLine = lines.first(where: isActiveStatusLine) {
                    return (true, String(activeLine.prefix(140)))
                }
            }
        }

        return (false, "No Thinking/Working status in last \(lastLineCount) lines")
    }

    private func lastNonEmptyLines(from text: String, count: Int) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.suffix(count))
    }

    private func isActiveStatusLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()

        // Avoid matching old transcript text like a plain "Thinking..." line.
        // The live Warp/Pi status line is prefixed by a spinner, e.g. "⠧ Working...".
        guard lowercased.contains("thinking...") || lowercased.contains("working...") else {
            return false
        }

        guard let first = trimmed.first else { return false }
        return warpStatusSpinners.contains(first)
    }

    private let warpStatusSpinners: Set<Character> = [
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
        "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷",
        "◐", "◓", "◑", "◒", "|", "/", "-", "\\", ":"
    ]

    /// Recursively finds Warp's terminal AXTextArea and returns its text value.
    private func findTerminalText(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 8 else { return nil }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success) ? roleRef as? String : nil

        if role == kAXTextAreaRole as String {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let text = valueRef as? String,
               !text.isEmpty {
                return text
            }
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let found = findTerminalText(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }
}
