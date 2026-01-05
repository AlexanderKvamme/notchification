//
//  AutomatorDetector.swift
//  Notchification
//
//  Detects Automator workflow activity
//  Color: Light gray (like Automator robot)
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "AutomatorDetector")

/// Detects if an Automator workflow is running
/// Checks if Automator.app is running and has a Stop button visible
final class AutomatorDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .automator
    private let bundleIdentifier = "com.apple.Automator"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.automator-check", qos: .utility)

    init() {}

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        print("🤖 POLL called")

        checkQueue.async { [weak self] in
            guard let self = self else {
                print("🤖 POLL: self is nil, returning")
                return
            }

            let isRunning = self.isAutomatorRunning()
            print("🤖 POLL: isAutomatorRunning = \(isRunning)")

            DispatchQueue.main.async {
                let wasActive = self.isActive

                if isRunning {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0
                    print("🤖 STATE: active readings = \(self.consecutiveActiveReadings)/\(self.requiredToShow)")

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        print("🤖 🟢 ACTIVATING - workflow detected!")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    print("🤖 STATE: inactive readings = \(self.consecutiveInactiveReadings)/\(self.requiredToHide)")

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        print("🤖 🔴 DEACTIVATING - workflow stopped")
                        self.isActive = false
                    }
                }

                if wasActive != self.isActive {
                    print("🤖 ⚡️ isActive CHANGED: \(wasActive) -> \(self.isActive)")
                }
            }
        }
    }

    /// Check if Automator.app is running a workflow
    private func isAutomatorRunning() -> Bool {
        // First check if Automator.app is running
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        print("🤖 CHECK: Automator.app instances = \(runningApps.count)")

        if runningApps.isEmpty {
            return false
        }

        // Check if Stop button is enabled (indicates workflow is running)
        let result = hasStopButton()
        print("🤖 CHECK: Stop button enabled = \(result)")
        return result
    }

    /// Check if Automator has an enabled Stop button using Accessibility API
    private func hasStopButton() -> Bool {
        // Get Automator app element
        guard let automatorApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }

        let appElement = AXUIElementCreateApplication(automatorApp.processIdentifier)

        // Get windows
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsValue)

        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            print("🤖 AX: No windows found")
            return false
        }

        // Check first window for toolbar
        let window = windows[0]
        var toolbarValue: CFTypeRef?
        let toolbarResult = AXUIElementCopyAttributeValue(window, "AXToolbar" as CFString, &toolbarValue)

        if toolbarResult == .success, let toolbar = toolbarValue {
            // Get toolbar children (buttons)
            var childrenValue: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(toolbar as! AXUIElement, "AXChildren" as CFString, &childrenValue)

            if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
                // Look for Stop button and check if enabled
                for child in children {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, "AXTitle" as CFString, &titleValue)

                    if let title = titleValue as? String, title == "Stop" {
                        var enabledValue: CFTypeRef?
                        let enabledResult = AXUIElementCopyAttributeValue(child, "AXEnabled" as CFString, &enabledValue)

                        if enabledResult == .success, let enabled = enabledValue as? Bool {
                            print("🤖 AX: Stop button enabled = \(enabled)")
                            return enabled
                        }
                    }
                }
                print("🤖 AX: Stop button not found in toolbar children")
            }
        }

        // Fallback: search all children of window for a button named "Stop"
        print("🤖 AX: No toolbar, searching window children...")
        return searchForStopButton(in: window, depth: 0)
    }

    /// Recursively search for Stop button (limited depth)
    private func searchForStopButton(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 3 else { return false }  // Limit recursion

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            return false
        }

        for child in children {
            // Check role
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &roleValue)
            let role = roleValue as? String ?? ""

            // Check title
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXTitle" as CFString, &titleValue)
            let title = titleValue as? String ?? ""

            if role == "AXButton" && title == "Stop" {
                var enabledValue: CFTypeRef?
                let enabledResult = AXUIElementCopyAttributeValue(child, "AXEnabled" as CFString, &enabledValue)

                if enabledResult == .success, let enabled = enabledValue as? Bool {
                    print("🤖 AX: Found Stop button at depth \(depth), enabled = \(enabled)")
                    return enabled
                }
            }

            // Recurse into groups/containers
            if role == "AXGroup" || role == "AXToolbar" || role == "AXSplitGroup" {
                if searchForStopButton(in: child, depth: depth + 1) {
                    return true
                }
            }
        }

        return false
    }
}
