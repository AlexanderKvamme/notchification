//
//  FinderDetector.swift
//  Notchification
//
//  Color: #e6e8ef (Finder gray)
//  Detects Finder file operations by checking for progress windows via Accessibility API
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "FinderDetector")

/// Detects if Finder is actively copying or moving files by looking for progress windows
final class FinderDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?

    // Consecutive readings required
    private let requiredToShow: Int = 1  // Trigger immediately
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Cooldown to prevent rapid re-triggering
    private var lastDeactivationTime: Date?
    private let reactivationCooldown: TimeInterval = 3.0  // Must wait 3 seconds before re-activating

    init() {
        logger.info("📁 FinderDetector init")
    }

    func startMonitoring() {
        logger.info("📁 FinderDetector startMonitoring")
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

            let hasProgressWindow = self.finderHasProgressWindow()

            DispatchQueue.main.async {
                if hasProgressWindow {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        // Check cooldown - don't reactivate too quickly after deactivation
                        if let lastDeactivation = self.lastDeactivationTime,
                           Date().timeIntervalSince(lastDeactivation) < self.reactivationCooldown {
                            logger.debug("📁 Ignoring activation - still in cooldown period")
                            return
                        }
                        logger.info("📁 Finder file operation started (progress window detected)")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("📁 Finder file operation finished")
                        self.isActive = false
                        self.lastDeactivationTime = Date()
                    }
                }
            }
        }
    }

    /// Check if Finder has a progress window open using Accessibility API
    private func finderHasProgressWindow() -> Bool {
        // Get Finder app
        guard let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return false
        }

        let finderPID = finderApp.processIdentifier
        let appElement = AXUIElementCreateApplication(finderPID)

        // Get all windows
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return false
        }

        // First pass: check if there's a dialog window (confirmation prompt)
        // If so, skip detection - the copy is paused waiting for user input
        for window in windows {
            if isDialogWindow(window) {
                return false
            }
        }

        // Second pass: check for progress windows
        for window in windows {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String, !title.isEmpty {
                // Finder progress windows have short titles like "Copy", "Move", etc.
                let progressKeywords = ["Copy", "Move", "Delete", "Preparing", "Emptying", "Trash"]
                for keyword in progressKeywords {
                    if title.contains(keyword) {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Check if window is a dialog (confirmation, alert, etc.)
    private func isDialogWindow(_ window: AXUIElement) -> Bool {
        // Check subrole for dialog types
        var subroleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String {
            if subrole == "AXDialog" || subrole == "AXSystemDialog" {
                return true
            }
        }

        // Check if window has typical dialog buttons (Replace, Keep Both, Stop, Skip)
        return windowHasDialogButtons(window)
    }

    /// Check if window contains dialog-specific buttons
    private func windowHasDialogButtons(_ element: AXUIElement, depth: Int = 0) -> Bool {
        guard depth < 5 else { return false }  // Limit recursion

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String, role == "AXButton" {
            // Check button title
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                let dialogButtonTitles = ["Replace", "Keep Both", "Stop", "Skip", "Merge"]
                if dialogButtonTitles.contains(title) {
                    return true
                }
            }
        }

        // Check children
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(30) {
                if windowHasDialogButtons(child, depth: depth + 1) {
                    return true
                }
            }
        }

        return false
    }

    deinit {
        stopMonitoring()
    }
}
