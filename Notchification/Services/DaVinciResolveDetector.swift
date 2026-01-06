//
//  DaVinciResolveDetector.swift
//  Notchification
//
//  Detects DaVinci Resolve rendering by checking for "Rendering in Progress" text
//  Uses direct path: Window → Render Queue group → "Rendering in Progress" text
//

import Foundation
import Combine
import AppKit

/// Detects if DaVinci Resolve is actively rendering
final class DaVinciResolveDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .davinciResolve
    private let bundleIdentifier = "com.blackmagic-design.DaVinciResolve"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.davinci-check", qos: .utility)

    private var debug: Bool { DebugSettings.shared.debugDaVinciResolve }

    init() {
        if debug {
            print("🎬 DaVinciResolveDetector init")
        }
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    func poll() {
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let isRendering = self.checkIfRendering()

            DispatchQueue.main.async {
                if self.debug {
                    print("🎬 DaVinci rendering=\(isRendering)")
                }

                if isRendering {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        if self.debug { print("🎬 >>> SHOWING DAVINCI INDICATOR") }
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        if self.debug { print("🎬 >>> HIDING DAVINCI INDICATOR") }
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if DaVinci Resolve is rendering
    private func checkIfRendering() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get windows
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsValue)

        guard windowsResult == .success,
              let windows = windowsValue as? [AXUIElement],
              !windows.isEmpty else {
            return false
        }

        // Search the main window for "Render Queue" group, then look for "Rendering in Progress"
        let window = windows[0]

        // Find "Render Queue" checkbox/group first (direct path)
        if let renderQueueGroup = findElement(in: window, withDescription: "Render Queue", maxDepth: 3) {
            // Now search within this group for "Rendering in Progress"
            if hasRenderingInProgress(in: renderQueueGroup, maxDepth: 5) {
                return true
            }
        }

        // Fallback: search more broadly for "Rendering in Progress" text
        return hasRenderingInProgress(in: window, maxDepth: 8)
    }

    /// Find an element with a specific description
    private func findElement(in element: AXUIElement, withDescription desc: String, maxDepth: Int, currentDepth: Int = 0) -> AXUIElement? {
        guard currentDepth < maxDepth else { return nil }

        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard let children = childrenValue as? [AXUIElement] else { return nil }

        for child in children {
            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXDescription" as CFString, &descValue)

            if let childDesc = descValue as? String, childDesc == desc {
                return child
            }

            // Recurse
            if let found = findElement(in: child, withDescription: desc, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                return found
            }
        }

        return nil
    }

    /// Check if "Rendering in Progress" text exists in the element tree
    private func hasRenderingInProgress(in element: AXUIElement, maxDepth: Int, currentDepth: Int = 0) -> Bool {
        guard currentDepth < maxDepth else { return false }

        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard let children = childrenValue as? [AXUIElement] else { return false }

        for child in children {
            // Check value attribute (where the text content is)
            var valueValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXValue" as CFString, &valueValue)

            if let value = valueValue as? String, value.contains("Rendering in Progress") {
                if debug { print("🎬 Found: '\(value)'") }
                return true
            }

            // Recurse
            if hasRenderingInProgress(in: child, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                return true
            }
        }

        return false
    }
}
