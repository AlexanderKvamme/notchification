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

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.xcode-check", qos: .utility)

    init() {
        logger.info("🔨 XcodeDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
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

    /// Check if Xcode is building - tries Accessibility API first, falls back to process detection
    private func isXcodeBuilding() -> (Bool, String) {
        // Primary: Check status text via Accessibility API
        if let statusText = getStatusTextViaAccessibility() {
            let isBuilding = buildingPatterns.contains { statusText.contains($0) }
            if debug { print("🔨 Xcode status: \"\(statusText)\" -> building=\(isBuilding)") }
            return isBuilding ? (true, "Status: \(statusText)") : (false, "Status: \(statusText)")
        }

        if debug { print("🔨 Xcode: AX check failed, falling back to process detection") }

        // Fallback: Check for compiler processes
        return checkBuildProcesses()
    }

    // MARK: - Primary Detection: Accessibility API (Status Text)

    /// Get Xcode's status text from the toolbar via Accessibility API
    /// Returns nil if AX check fails (permissions, UI not found, etc.)
    private func getStatusTextViaAccessibility() -> String? {
        guard let xcodeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(xcodeApp.processIdentifier)

        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsValue)

        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            if debug { print("🔨 Xcode AX: No windows found") }
            return nil
        }

        // Check each window for status text
        for window in windows {
            if let status = findStatusTextInWindow(window) {
                return status
            }
        }

        return nil
    }

    /// Search for status text in a window's toolbar
    private func findStatusTextInWindow(_ window: AXUIElement) -> String? {
        // First try the toolbar directly
        var toolbarValue: CFTypeRef?
        let toolbarResult = AXUIElementCopyAttributeValue(window, "AXToolbar" as CFString, &toolbarValue)

        if toolbarResult == .success, let toolbar = toolbarValue {
            if let status = findStatusTextInElement(toolbar as! AXUIElement) {
                return status
            }
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

    // MARK: - Fallback Detection: Process Monitoring

    /// Check for compiler processes (fallback when AX fails)
    private func checkBuildProcesses() -> (Bool, String) {
        // Check for swift-frontend processes (active compilation)
        let swiftCount = getProcessCount(name: "swift-frontend")
        if swiftCount > 0 {
            if debug { print("🔨 Xcode: Detected \(swiftCount) swift-frontend processes") }
            return (true, "\(swiftCount) swift-frontend processes")
        }

        // Check for clang processes (C/ObjC compilation)
        let clangCount = getProcessCount(name: "clang")
        if clangCount > 0 {
            if debug { print("🔨 Xcode: Detected \(clangCount) clang processes") }
            return (true, "\(clangCount) clang processes")
        }

        if debug { print("🔨 Xcode: No build processes found") }
        return (false, "no build processes")
    }

    /// Count running processes with given name
    private func getProcessCount(name: String) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return 0
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return 0
        }

        return output.components(separatedBy: .newlines).count
    }
}
