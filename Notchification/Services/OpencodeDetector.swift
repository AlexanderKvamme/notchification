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
final class OpencodeDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?
    private let bundleIdentifier = "ai.opencode.desktop"

    // Status keywords that indicate activity (must be followed by timer like "· 25s")
    private let activeKeywords = [
        "Making edits",
        "Running commands",
        "Running command",
        "Planning next steps",
        "Gathering thoughts",
        "Gathering context",
        "Generating",
        "Writing"
    ]

    // Regex pattern for active status with timer (e.g., "Making edits · 25s" or "· 0.54s")
    // Using flexible separator to handle different dot characters
    private let timerPattern = try! NSRegularExpression(pattern: "\\d+\\.?\\d*s\\s*$", options: [])

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {
        logger.info("🟢 OpencodeDetector init")
    }

    func startMonitoring() {
        logger.info("🟢 OpencodeDetector startMonitoring")
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0

        // Request Automation permissions for terminal apps (triggers system prompt if needed)
        requestTerminalPermissions()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        checkStatus()
    }

    /// Request Automation permissions for iTerm2 and Terminal.app
    /// This triggers the system permission prompt if not already granted
    private func requestTerminalPermissions() {
        DispatchQueue.global(qos: .utility).async {
            // Try iTerm2
            let itermScript = "tell application \"iTerm2\" to return name"
            let itermTask = Process()
            itermTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            itermTask.arguments = ["-e", itermScript]
            itermTask.standardOutput = FileHandle.nullDevice
            itermTask.standardError = FileHandle.nullDevice
            try? itermTask.run()

            // Try Terminal
            let terminalScript = "tell application \"Terminal\" to return name"
            let terminalTask = Process()
            terminalTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            terminalTask.arguments = ["-e", terminalScript]
            terminalTask.standardOutput = FileHandle.nullDevice
            terminalTask.standardError = FileHandle.nullDevice
            try? terminalTask.run()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func checkStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let (isWorking, statusText) = self.isOpencodeWorking()
            let debug = DebugSettings.shared.debugOpencode

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if debug {
                        logger.debug("🟢 Opencode ACTIVE: \(statusText)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🟢 Opencode started working: \(statusText)")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if debug {
                        logger.debug("🟢 Opencode idle")
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
        // First check the GUI app
        if let opencodeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            let appElement = AXUIElementCreateApplication(opencodeApp.processIdentifier)

            var windowsValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

            if result == .success, let windows = windowsValue as? [AXUIElement] {
                for window in windows {
                    if let statusText = findStatusText(in: window) {
                        return (true, "GUI: \(statusText)")
                    }
                }
            }
        }

        // Check for CLI in terminal - look for tabs titled "opencode" AND opencode process running
        if isOpencodeCLIActive() {
            return (true, "CLI: opencode tab active")
        }

        return (false, "No activity")
    }

    /// Check if Opencode CLI is active in a terminal using AppleScript
    private func isOpencodeCLIActive() -> Bool {
        // Check iTerm2
        if isOpencodeActiveInITerm2() {
            return true
        }

        // Check Terminal.app
        if isOpencodeActiveInTerminal() {
            return true
        }

        return false
    }

    /// Use AppleScript to check iTerm2 terminal content for opencode activity
    private func isOpencodeActiveInITerm2() -> Bool {
        // Script to get all session content - last ~3000 chars (~30 lines)
        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then return "NOT_RUNNING"
        end tell

        tell application "iTerm2"
            set allContent to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionContent to contents of s
                        set contentLength to length of sessionContent
                        if contentLength > 3000 then
                            set recentContent to text (contentLength - 3000) thru contentLength of sessionContent
                        else
                            set recentContent to sessionContent
                        end if
                        set allContent to allContent & "---SESSION---" & recentContent
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

        // Check for "Generating..." followed by "press esc to exit cancel" on consecutive lines
        return hasGeneratingPattern(in: output)
    }

    /// Check if output contains "Generating..." followed by "press esc to exit cancel" on consecutive lines
    private func hasGeneratingPattern(in output: String) -> Bool {
        let lines = output.components(separatedBy: .newlines)
        for i in 0..<lines.count - 1 {
            let currentLine = lines[i]
            let nextLine = lines[i + 1]
            if currentLine.contains("Generating...") && nextLine.contains("press esc to exit cancel") {
                return true
            }
        }
        return false
    }

    /// Use AppleScript to check Terminal.app content for opencode activity
    private func isOpencodeActiveInTerminal() -> Bool {
        // Terminal.app uses "history" for full content, "contents" for visible only
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return "NOT_RUNNING"
        end tell

        tell application "Terminal"
            set allContent to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabContent to history of t
                    set contentLength to length of tabContent
                    if contentLength > 3000 then
                        set recentContent to text (contentLength - 3000) thru contentLength of tabContent
                    else
                        set recentContent to tabContent
                    end if
                    set allContent to allContent & "---TAB---" & recentContent
                end repeat
            end repeat
            return allContent
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        // Debug: check for errors
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            let debug = DebugSettings.shared.debugOpencode
            if debug {
                logger.debug("🟢 Terminal AppleScript error: \(errorOutput)")
            }
        }

        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "NOT_RUNNING" else {
            return false
        }

        return hasGeneratingPattern(in: output)
    }

    /// Check if text matches active status pattern (keyword + timer like "Making edits · 25s")
    private func isActiveStatus(_ text: String) -> Bool {
        // Must contain a timer pattern (· Xs)
        let range = NSRange(text.startIndex..., in: text)
        guard timerPattern.firstMatch(in: text, options: [], range: range) != nil else {
            return false
        }

        // Must contain one of our keywords
        for keyword in activeKeywords {
            if text.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Recursively search for status text elements
    private func findStatusText(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 15 else { return nil }  // Limit recursion

        // Check if this element has text that matches our active status pattern
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String, isActiveStatus(text) {
            return text
        }

        // Also check title attribute
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let text = titleRef as? String, isActiveStatus(text) {
            return text
        }

        // Check description attribute (sometimes status is here)
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let text = descRef as? String, isActiveStatus(text) {
            return text
        }

        // Recursively check children
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

    deinit {
        stopMonitoring()
    }
}
