//
//  XcodeDetector.swift
//  Notchification
//
//  Color: #147EFB (Xcode blue)
//  Detects Xcode builds via Accessibility API (status text) with subprocess fallback
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "XcodeDetector")

/// Detects if Xcode is actively building
/// Primary: Reads status text from toolbar via Accessibility API (e.g., "Building...", "Compiling...")
/// Fallback: Checks for compiler processes via pgrep (when AX fails)
final class XcodeDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .xcode
    private let bundleIdentifier = "com.apple.dt.Xcode"

    // Status text patterns that indicate building
    private let buildingPatterns = ["Building", "Compiling", "Linking", "Copying", "Processing", "Analyzing"]

    // Debug logging toggle
    private var debug: Bool { DebugSettings.shared.debugXcode }

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Throttling to reduce power usage (Accessibility API is expensive)
    private var pollCount: Int = 0
    private let throttleInterval: Int = 3

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.xcode-check", qos: .utility)

    init() {
        logger.info("🔨 XcodeDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        pollCount = 0
        isActive = false
    }

    /// Check if Xcode is running (cheap check using NSWorkspace)
    private var isXcodeRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func poll() {
        // Skip expensive checks if Xcode isn't running
        guard isXcodeRunning else {
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

        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let (building, details) = self.isXcodeBuilding()

            DispatchQueue.main.async {
                if building {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0
                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🔨 Xcode build started: \(details)")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🔨 Xcode build finished")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Xcode is building using Accessibility API (authoritative source)
    /// Reads the actual status text from Xcode's toolbar - no heuristic fallbacks
    private func isXcodeBuilding() -> (Bool, String) {
        if let statusText = getStatusTextViaAccessibility() {
            let isBuilding = buildingPatterns.contains { statusText.contains($0) }
            if debug { print("🔨 Xcode status: \"\(statusText)\" -> building=\(isBuilding)") }
            return isBuilding ? (true, "Status: \(statusText)") : (false, "Status: \(statusText)")
        }

        if debug { print("🔨 Xcode: Could not read status via Accessibility API") }
        return (false, "No AX status")
    }

    // MARK: - Primary Detection: Accessibility API (Status Text)

    /// Get Xcode's status text from the toolbar via Accessibility API
    /// Returns nil if AX check fails (permissions, UI not found, etc.)
    private func getStatusTextViaAccessibility() -> String? {
        guard let xcodeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            if debug { print("🔨 Xcode AX: Xcode app not found") }
            return nil
        }

        let appElement = AXUIElementCreateApplication(xcodeApp.processIdentifier)

        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsValue)

        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            if debug {
                let errorDesc = axErrorDescription(windowsResult)
                print("🔨 Xcode AX: No windows found (error: \(errorDesc))")
            }
            return nil
        }

        if debug { print("🔨 Xcode AX: Found \(windows.count) windows") }

        // Check each window for status text
        for (index, window) in windows.enumerated() {
            if let status = findStatusTextInWindow(window, windowIndex: index) {
                return status
            }
        }

        if debug { print("🔨 Xcode AX: No status text found in any window") }
        return nil
    }

    /// Convert AXError to readable string
    private func axErrorDescription(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(error.rawValue))"
        }
    }

    /// Search for status text in a window's toolbar
    private func findStatusTextInWindow(_ window: AXUIElement, windowIndex: Int = 0) -> String? {
        // Get window title for debugging
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXTitle" as CFString, &titleValue)
        let windowTitle = titleValue as? String ?? "untitled"

        // First try the toolbar directly
        var toolbarValue: CFTypeRef?
        let toolbarResult = AXUIElementCopyAttributeValue(window, "AXToolbar" as CFString, &toolbarValue)

        if toolbarResult == .success, let toolbar = toolbarValue {
            if debug { print("🔨 Xcode AX: Window \(windowIndex) '\(windowTitle)' has toolbar") }
            if let status = findStatusTextInElement(toolbar as! AXUIElement) {
                return status
            }
        } else if debug {
            print("🔨 Xcode AX: Window \(windowIndex) '\(windowTitle)' no toolbar (\(axErrorDescription(toolbarResult)))")
        }

        // Fallback: recursive search through window hierarchy
        return searchForStatusText(in: window, depth: 0)
    }

    /// Check children of an element for status text
    private func findStatusTextInElement(_ element: AXUIElement) -> String? {
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &roleValue)
            let role = roleValue as? String ?? ""

            // Look for static text elements that might contain status
            if role == "AXStaticText" {
                var valueValue: CFTypeRef?
                AXUIElementCopyAttributeValue(child, "AXValue" as CFString, &valueValue)

                if let value = valueValue as? String, !value.isEmpty {
                    // Check if this looks like a status message
                    if buildingPatterns.contains(where: { value.contains($0) }) ||
                       value.contains("Finished") ||
                       value.contains("Succeeded") ||
                       value.contains("Failed") ||
                       value.contains("Ready") {
                        return value
                    }
                }
            }

            // Recurse into groups
            if role == "AXGroup" || role == "AXToolbar" {
                if let status = findStatusTextInElement(child) {
                    return status
                }
            }
        }

        return nil
    }

    /// Recursive search for status text (fallback when direct search fails)
    private func searchForStatusText(in element: AXUIElement, depth: Int) -> String? {
        guard depth < 5 else { return nil }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &roleValue)
            let role = roleValue as? String ?? ""

            // Check static text elements
            if role == "AXStaticText" {
                var valueValue: CFTypeRef?
                AXUIElementCopyAttributeValue(child, "AXValue" as CFString, &valueValue)

                if let value = valueValue as? String, !value.isEmpty {
                    if buildingPatterns.contains(where: { value.contains($0) }) ||
                       value.contains("Finished") ||
                       value.contains("Succeeded") ||
                       value.contains("Failed") {
                        return value
                    }
                }
            }

            // Recurse into container elements
            if role == "AXGroup" || role == "AXToolbar" || role == "AXSplitGroup" || role == "AXScrollArea" {
                if let found = searchForStatusText(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }
}
