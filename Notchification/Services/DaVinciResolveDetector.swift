//
//  DaVinciResolveDetector.swift
//  Notchification
//
//  Detects DaVinci Resolve rendering by checking for "Rendering in Progress" text
//  Uses direct path: Window → Render Queue group → "Rendering in Progress" text
//  Also extracts progress percentage for determinate progress bar
//

import Foundation
import Combine
import AppKit

/// Detects if DaVinci Resolve is actively rendering
final class DaVinciResolveDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    /// Current render progress (0.0 to 1.0), nil if indeterminate
    @Published private(set) var progress: Double? = nil

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
        progress = nil
    }

    func poll() {
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let (isRendering, currentProgress) = self.checkRenderingStatus()

            DispatchQueue.main.async {
                if self.debug {
                    print("🎬 DaVinci rendering=\(isRendering), progress=\(currentProgress?.description ?? "nil")")
                }

                // Update progress
                self.progress = currentProgress

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
                        self.progress = nil
                    }
                }
            }
        }
    }

    /// Check if DaVinci Resolve is rendering and extract progress
    /// Returns (isRendering, progress) where progress is 0.0-1.0 or nil if unknown
    private func checkRenderingStatus() -> (Bool, Double?) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return (false, nil)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get windows
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsValue)

        guard windowsResult == .success,
              let windows = windowsValue as? [AXUIElement],
              !windows.isEmpty else {
            return (false, nil)
        }

        // Try to get progress from the Dock icon first (most reliable)
        let dockProgress = getDockIconProgress()

        // Check ALL windows (window order changes when app loses focus)
        for window in windows {
            // Find "Render Queue" group first (direct path)
            if let renderQueueGroup = findElement(in: window, withDescription: "Render Queue", maxDepth: 3) {
                // Search within this group for rendering status and progress
                let (found, uiProgress) = findRenderingProgress(in: renderQueueGroup, maxDepth: 6)
                if found {
                    // Prefer dock progress if available, otherwise use UI progress
                    return (true, dockProgress ?? uiProgress)
                }
            }

            // Fallback: search more broadly in this window
            let (found, uiProgress) = findRenderingProgress(in: window, maxDepth: 10)
            if found {
                return (true, dockProgress ?? uiProgress)
            }
        }

        // If dock shows progress, rendering is happening even if we can't see the window
        // (e.g., DaVinci is on a different Space/desktop)
        if let progress = dockProgress, progress > 0 && progress < 1 {
            if debug { print("🎬 Dock progress detected on different Space: \(progress)") }
            return (true, progress)
        }

        return (false, nil)
    }

    /// Try to read progress from the Dock icon
    /// Apps can display progress bars on their dock icons
    private func getDockIconProgress() -> Double? {
        // Find the Dock application
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            if debug { print("🎬 Dock app not found") }
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)

        // Get the dock's children (the dock bar itself)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, "AXChildren" as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            if debug { print("🎬 Could not get Dock children") }
            return nil
        }

        if debug { print("🎬 Searching Dock with \(children.count) children") }

        // Search for DaVinci Resolve's dock tile
        for child in children {
            if let progress = findDockTileProgress(in: child, appName: "DaVinci Resolve", maxDepth: 6) {
                if debug { print("🎬 Found dock progress: \(progress)") }
                return progress
            }
        }

        if debug { print("🎬 No dock progress found") }
        return nil
    }

    /// Search for a dock tile's progress indicator
    private func findDockTileProgress(in element: AXUIElement, appName: String, maxDepth: Int, currentDepth: Int = 0) -> Double? {
        guard currentDepth < maxDepth else { return nil }

        // Check if this element is for our app
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXTitle" as CFString, &titleValue)
        let title = titleValue as? String ?? ""

        var descValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXDescription" as CFString, &descValue)
        let desc = descValue as? String ?? ""

        // Check role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        // Log dock elements at shallow depth
        if debug && currentDepth <= 2 && (title.count > 0 || desc.count > 0 || role.count > 0) {
            print("🎬 Dock[\(currentDepth)]: role=\(role), title='\(title)', desc='\(desc)'")
        }

        // If this is a progress indicator, get its value
        if role == "AXProgressIndicator" {
            var progressValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXValue" as CFString, &progressValue)
            if debug { print("🎬 Dock: Found AXProgressIndicator! value=\(String(describing: progressValue))") }

            if let pv = progressValue {
                // Try CFNumber extraction first (most reliable for AX values)
                if CFGetTypeID(pv) == CFNumberGetTypeID() {
                    let cfNum = pv as! CFNumber
                    var doubleVal: Double = 0
                    if CFNumberGetValue(cfNum, .doubleType, &doubleVal) {
                        if debug { print("🎬 Dock: CFNumber value = \(doubleVal)") }
                        return doubleVal > 1 ? doubleVal / 100.0 : doubleVal
                    }
                }
                // Fallback to NSNumber bridge
                else if let progress = pv as? NSNumber {
                    let value = progress.doubleValue
                    if debug { print("🎬 Dock: NSNumber value = \(value)") }
                    return value > 1 ? value / 100.0 : value
                }
            }
        }

        // If this is the DaVinci dock tile, search its children for progress
        let isDaVinciTile = title.contains(appName) || desc.contains(appName)
        if isDaVinciTile && debug {
            print("🎬 Found DaVinci dock tile!")
        }

        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        if let children = childrenValue as? [AXUIElement] {
            for child in children {
                // If we found DaVinci's tile, only search within it
                if isDaVinciTile || currentDepth < 2 {
                    if let progress = findDockTileProgress(in: child, appName: appName, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                        return progress
                    }
                }
            }
        }

        return nil
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

    /// Search for rendering status and progress percentage
    /// Returns (isRendering, progress) where progress is 0.0-1.0 or nil
    private func findRenderingProgress(in element: AXUIElement, maxDepth: Int, currentDepth: Int = 0) -> (Bool, Double?) {
        guard currentDepth < maxDepth else { return (false, nil) }

        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)

        guard let children = childrenValue as? [AXUIElement] else { return (false, nil) }

        var foundRendering = false
        var extractedProgress: Double? = nil

        for child in children {
            // Check role for progress indicator
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &roleValue)
            let role = roleValue as? String ?? ""

            // Check for progress indicator element
            if role == "AXProgressIndicator" {
                var progressValue: CFTypeRef?
                AXUIElementCopyAttributeValue(child, "AXValue" as CFString, &progressValue)

                if debug {
                    print("🎬 UI: Found AXProgressIndicator, value=\(String(describing: progressValue))")
                    if let pv = progressValue {
                        print("🎬 UI: CFTypeID = \(CFGetTypeID(pv)), CFNumberTypeID = \(CFNumberGetTypeID())")
                    }
                }

                // Extract the value - AX can return CFNumber or CFString
                var value: Double? = nil
                if let pv = progressValue {
                    // First try: String (CFTypeID 7) - DaVinci returns progress as string
                    if CFGetTypeID(pv) == CFStringGetTypeID() {
                        if let str = pv as? String, let parsed = Double(str) {
                            value = parsed
                            if debug { print("🎬 UI: CFString value = '\(str)' -> \(parsed)") }
                        }
                    }
                    // Second try: CFNumber extraction
                    else if CFGetTypeID(pv) == CFNumberGetTypeID() {
                        let cfNum = pv as! CFNumber
                        var doubleVal: Double = 0
                        if CFNumberGetValue(cfNum, .doubleType, &doubleVal) {
                            value = doubleVal
                            if debug { print("🎬 UI: CFNumber as double = \(doubleVal)") }
                        }
                    }
                    // Third try: NSNumber bridge
                    else if let numValue = pv as? NSNumber {
                        value = numValue.doubleValue
                        if debug { print("🎬 UI: NSNumber = \(numValue.doubleValue)") }
                    }
                }

                if let v = value {
                    // DaVinci initializes progress to 100 before starting - ignore that specific value
                    if v == 100 {
                        if debug { print("🎬 UI: Progress at 100 (init state), ignoring") }
                    } else {
                        // DaVinci reports 0-100, normalize to 0-1
                        extractedProgress = v / 100.0
                        if debug { print("🎬 UI: Progress indicator value: \(v) -> \(extractedProgress!)") }
                    }
                } else if debug {
                    print("🎬 UI: Failed to extract progress value")
                }
            }

            // Check value attribute for text content
            var valueValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXValue" as CFString, &valueValue)

            if let value = valueValue as? String {
                // Check for "Rendering in Progress"
                if value.contains("Rendering in Progress") {
                    if debug { print("🎬 Found: '\(value)'") }
                    foundRendering = true
                }

                // Try to extract percentage from text like "50%" or "Rendering 50%"
                if let percentMatch = value.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) {
                    let numStr = value[percentMatch].dropLast() // Remove %
                        .trimmingCharacters(in: .whitespaces)
                    if let percent = Double(numStr) {
                        extractedProgress = percent / 100.0
                        if debug { print("🎬 UI: Found percentage text: '\(value)' -> \(percent)%") }
                    }
                }

                // Also check for "Remaining X%" pattern
                if value.contains("Remaining") && value.contains("%") {
                    if debug { print("🎬 UI: Found Remaining text: '\(value)'") }
                }
            }

            // Recurse into children
            let (childFound, childProgress) = findRenderingProgress(in: child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
            if childFound {
                foundRendering = true
            }
            if let cp = childProgress {
                extractedProgress = cp
            }
        }

        return (foundRendering, extractedProgress)
    }
}
