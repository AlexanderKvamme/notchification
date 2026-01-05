//
//  ScriptEditorDetector.swift
//  Notchification
//
//  Detects Script Editor (AppleScript) activity
//  Color: Light purple (like AppleScript icon)
//

import Foundation
import Combine
import AppKit

/// Detects if Script Editor is running a script
/// Checks if Script Editor.app is running and has a Stop button enabled
final class ScriptEditorDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .scriptEditor
    private let bundleIdentifier = "com.apple.ScriptEditor2"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.scripteditor-check", qos: .utility)

    init() {
        print("📜 ScriptEditorDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let isRunning = self.isScriptRunning()

            DispatchQueue.main.async {
                if isRunning {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        print("📜 Script Editor: script STARTED")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        print("📜 Script Editor: script STOPPED")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Script Editor is running a script
    private func isScriptRunning() -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        if runningApps.isEmpty {
            return false
        }

        print("📜 Script Editor is running, checking for Stop button...")

        // Check if Stop button is enabled (indicates script is running)
        let result = hasStopButton()
        print("📜 Stop button enabled = \(result)")
        return result
    }

    /// Check if Script Editor has an enabled Stop button using Accessibility API
    private func hasStopButton() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get windows
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsValue)

        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            print("📜 AX: No windows found")
            return false
        }

        print("📜 AX: Found \(windows.count) window(s)")

        // Check first window for toolbar
        let window = windows[0]
        var toolbarValue: CFTypeRef?
        let toolbarResult = AXUIElementCopyAttributeValue(window, "AXToolbar" as CFString, &toolbarValue)

        if toolbarResult == .success, let toolbar = toolbarValue {
            print("📜 AX: Found toolbar")
            // Get toolbar children (buttons)
            var childrenValue: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(toolbar as! AXUIElement, "AXChildren" as CFString, &childrenValue)

            if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
                print("📜 AX: Toolbar has \(children.count) children")
                // Look for Stop button and check if enabled
                for child in children {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, "AXTitle" as CFString, &titleValue)
                    let title = titleValue as? String ?? "(no title)"

                    var roleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &roleValue)
                    let role = roleValue as? String ?? "(no role)"

                    print("📜 AX: Toolbar child - role=\(role), title=\(title)")

                    if title == "Stop" {
                        var enabledValue: CFTypeRef?
                        let enabledResult = AXUIElementCopyAttributeValue(child, "AXEnabled" as CFString, &enabledValue)

                        if enabledResult == .success, let enabled = enabledValue as? Bool {
                            print("📜 AX: Stop button found! enabled=\(enabled)")
                            return enabled
                        }
                    }
                }
            }
        } else {
            print("📜 AX: No toolbar found, searching window children...")
        }

        // Fallback: search window children for Stop button
        return searchForStopButton(in: window, depth: 0)
    }

    /// Recursively search for Stop button (limited depth)
    private func searchForStopButton(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 4 else { return false }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            return false
        }

        for child in children {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &roleValue)
            let role = roleValue as? String ?? ""

            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXTitle" as CFString, &titleValue)
            let title = titleValue as? String ?? ""

            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXDescription" as CFString, &descValue)
            let desc = descValue as? String ?? ""

            if depth == 0 {
                print("📜 AX: Window child depth=\(depth) - role=\(role), title=\(title), desc=\(desc)")
            }

            if role == "AXButton" && (title == "Stop" || desc == "Stop") {
                var enabledValue: CFTypeRef?
                let enabledResult = AXUIElementCopyAttributeValue(child, "AXEnabled" as CFString, &enabledValue)

                if enabledResult == .success, let enabled = enabledValue as? Bool {
                    print("📜 AX: Found Stop button at depth \(depth)! enabled=\(enabled)")
                    return enabled
                }
            }

            // Recurse into groups/containers
            if role == "AXGroup" || role == "AXToolbar" || role == "AXSplitGroup" || role == "AXScrollArea" {
                if searchForStopButton(in: child, depth: depth + 1) {
                    return true
                }
            }
        }

        return false
    }
}
