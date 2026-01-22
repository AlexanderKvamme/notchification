//
//  ClaudeAppDetector.swift
//  Notchification
//
//  Color: #D97757 (Claude orange)
//  Detects Claude desktop app activity via Accessibility API
//
//  Looks for status text like "Claude is thinking" in the app UI.
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "ClaudeAppDetector")

/// Detects if Claude desktop app is actively generating a response
/// Uses Accessibility API to find status indicators in the UI
final class ClaudeAppDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .claudeApp

    // Claude desktop app bundle identifier
    // Verify with: osascript -e 'id of app "Claude"'
    private let bundleIdentifier = "com.anthropic.claudefordesktop"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Throttling to reduce power usage (Accessibility API can be expensive)
    private var pollCount: Int = 0
    private let throttleInterval: Int = 3

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.claudeapp-check", qos: .utility)

    // Status keywords that indicate Claude desktop app is working
    private let activeKeywords = [
        "Claude is thinking",
        "Thinking",
        "Generating",
        "Writing",
        "Analyzing"
    ]

    // Debug logging toggle
    private var debug: Bool { DebugSettings.shared.debugClaudeApp }

    init() {
        logger.info("🟠 ClaudeAppDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        pollCount = 0
        isActive = false
    }

    /// Check if Claude desktop app is running (cheap check using NSWorkspace)
    private var isClaudeAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func poll() {
        // Skip expensive checks if Claude app isn't running
        guard isClaudeAppRunning else {
            if isActive {
                DispatchQueue.main.async { self.reset() }
            }
            return
        }

        pollCount += 1

        // Throttle when idle to save power (Accessibility API is expensive)
        if !isActive && pollCount % throttleInterval != 0 {
            return
        }

        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let isWorking = self.isClaudeAppWorking()

            DispatchQueue.main.async {
                if isWorking {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.debug {
                        print("🟠 Claude App active: \(self.consecutiveActiveReadings)/\(self.requiredToShow)")
                    }

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🟠 Claude App started working")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.debug {
                        print("🟠 Claude App inactive: \(self.consecutiveInactiveReadings)/\(self.requiredToHide)")
                    }

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🟠 Claude App finished working")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Claude desktop app is actively generating a response
    private func isClaudeAppWorking() -> Bool {
        guard let claudeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }

        let appElement = AXUIElementCreateApplication(claudeApp.processIdentifier)

        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        guard result == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            if debug {
                print("🟠 Claude App: no windows found")
            }
            return false
        }

        if debug {
            print("🟠 Claude App: found \(windows.count) window(s)")
        }

        // Search windows for activity indicators
        for window in windows {
            if let statusText = findStatusText(in: window) {
                if debug {
                    print("🟠 Claude App ACTIVE: \(statusText)")
                }
                return true
            }
        }

        return false
    }

    /// Recursively search for status text in Claude desktop app UI
    private func findStatusText(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 15 else { return nil }

        // Check AXValue
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String, isActiveStatus(text) {
            return text
        }

        // Check AXTitle
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let text = titleRef as? String, isActiveStatus(text) {
            return text
        }

        // Check AXDescription
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let text = descRef as? String, isActiveStatus(text) {
            return text
        }

        // Recurse into children
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

    /// Check if text indicates Claude desktop app is actively working
    private func isActiveStatus(_ text: String) -> Bool {
        for keyword in activeKeywords {
            if text.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }
        return false
    }
}
