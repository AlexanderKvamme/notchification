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
        guard let opencodeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return (false, "App not running")
        }

        let appElement = AXUIElementCreateApplication(opencodeApp.processIdentifier)

        // Get all windows
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return (false, "No windows")
        }

        // Search each window for status text
        for window in windows {
            if let statusText = findStatusText(in: window) {
                return (true, statusText)
            }
        }

        return (false, "No activity")
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
