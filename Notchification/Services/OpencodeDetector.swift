//
//  OpencodeDetector.swift
//  Notchification
//
//  Color: #D8D8D8 (Opencode gray)
//  Detects Opencode activity by looking for status text via Accessibility API
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "OpencodeDetector")

/// Detects if Opencode is actively working (running commands, making edits, etc.)
/// Uses Accessibility API to look for status text indicators
final class OpencodeDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .opencode
    private let bundleIdentifier = "ai.opencode.desktop"

    // Status keywords that indicate activity (must be followed by timer like "· 25s")
    private let activeKeywords = [
        "Making edits",
        "Running commands",
        "Running command",
        "Planning next steps",
        "Considering next steps",
        "Gathering thoughts",
        "Gathering context",
        "Generating",
        "Writing"
    ]

    // Regex pattern for active status with timer
    private let timerPattern = try! NSRegularExpression(pattern: "\\d+\\.?\\d*s\\s*$", options: [])

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap.
    // Without this, if a check takes longer than 1 second (the poll interval),
    // multiple checks could run concurrently and cause stuck states.
    private let checkQueue = DispatchQueue(label: "com.notchification.opencode-check", qos: .utility)

    init() {
        logger.info("🟢 OpencodeDetector init")
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

            let (isWorking, statusText) = self.isOpencodeWorking()
            let debug = DebugSettings.shared.debugOpencode

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    // NOTE: Keep debug logs - helps diagnose detection issues
                    if debug {
                        print("🟢 Opencode ACTIVE: \(statusText)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🟢 Opencode started working: \(statusText)")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    // NOTE: Keep debug logs - helps diagnose detection issues
                    if debug {
                        print("🟢 Opencode idle")
                    }

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🟢 Opencode finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Opencode is working by looking for status text via Accessibility API
    private func isOpencodeWorking() -> (Bool, String) {
        let debug = DebugSettings.shared.debugOpencode

        // NOTE: Keep debug logs - helps diagnose detection issues
        if debug {
            print("🟢 Opencode: checking...")
        }

        if let opencodeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            if debug {
                print("🟢 Opencode: GUI app found, checking windows...")
            }
            let appElement = AXUIElementCreateApplication(opencodeApp.processIdentifier)

            var windowsValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

            if result == .success, let windows = windowsValue as? [AXUIElement] {
                if debug {
                    print("🟢 Opencode: found \(windows.count) windows")
                }
                for window in windows {
                    if let statusText = findStatusText(in: window) {
                        return (true, "GUI: \(statusText)")
                    }
                }
            }
        } else if debug {
            print("🟢 Opencode: GUI app not running")
        }

        // Also check for CLI version in terminals.
        // NOTE: This runs even when GUI isn't open, which uses some energy.
        // If you only use GUI (not CLI), this could be optimized to skip.
        if debug {
            print("🟢 Opencode: checking CLI in terminals...")
        }

        if isOpencodeCLIActive() {
            return (true, "CLI: opencode tab active")
        }

        return (false, "No activity")
    }

    /// Check if Opencode CLI is active in a terminal using AppleScript
    private func isOpencodeCLIActive() -> Bool {
        if isOpencodeActiveInITerm2() {
            return true
        }

        if isOpencodeActiveInTerminal() {
            return true
        }

        return false
    }

    /// Use AppleScript to get iTerm2 terminal content
    private func isOpencodeActiveInITerm2() -> Bool {
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

        return hasGeneratingPattern(in: output)
    }

    /// Check if "Generating..." + "press esc to exit cancel" appears in the last 10 lines of ANY session
    private func hasGeneratingPattern(in output: String) -> Bool {
        let sessions = output.components(separatedBy: "---SESSION---") +
                       output.components(separatedBy: "---TAB---")

        for session in sessions {
            let lines = session.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .suffix(10)

            let lineArray = Array(lines)
            guard lineArray.count >= 2 else { continue }

            for i in 0..<(lineArray.count - 1) {
                if lineArray[i].contains("Generating...") && lineArray[i + 1].contains("press esc to exit cancel") {
                    return true
                }
            }
        }
        return false
    }

    /// Use AppleScript to get Terminal.app content
    private func isOpencodeActiveInTerminal() -> Bool {
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

        return hasGeneratingPattern(in: output)
    }

    /// Check if text matches active status pattern (keyword + timer like "Making edits · 25s")
    private func isActiveStatus(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard timerPattern.firstMatch(in: text, options: [], range: range) != nil else {
            return false
        }

        for keyword in activeKeywords {
            if text.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Recursively search for status text elements
    private func findStatusText(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 15 else { return nil }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String, isActiveStatus(text) {
            return text
        }

        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let text = titleRef as? String, isActiveStatus(text) {
            return text
        }

        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let text = descRef as? String, isActiveStatus(text) {
            return text
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let found = findStatusText(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }
}
