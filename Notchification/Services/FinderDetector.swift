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
final class FinderDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .finder

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Cooldown to prevent rapid re-triggering
    private var lastDeactivationTime: Date?
    private let reactivationCooldown: TimeInterval = 3.0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.finder-check", qos: .utility)

    init() {
        logger.info("📁 FinderDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        lastDeactivationTime = nil
        isActive = false
    }

    func poll() {
        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let hasProgressWindow = self.finderHasProgressWindow()

            DispatchQueue.main.async {
                if hasProgressWindow {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
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
        guard let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return false
        }

        let finderPID = finderApp.processIdentifier
        let appElement = AXUIElementCreateApplication(finderPID)

        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return false
        }

        for window in windows {
            if isDialogWindow(window) {
                return false
            }
        }

        for window in windows {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String, !title.isEmpty {
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
        var subroleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String {
            if subrole == "AXDialog" || subrole == "AXSystemDialog" {
                return true
            }
        }

        return windowHasDialogButtons(window)
    }

    /// Check if window contains dialog-specific buttons
    private func windowHasDialogButtons(_ element: AXUIElement, depth: Int = 0) -> Bool {
        guard depth < 5 else { return false }

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String, role == "AXButton" {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                let dialogButtonTitles = ["Replace", "Keep Both", "Stop", "Skip", "Merge"]
                if dialogButtonTitles.contains(title) {
                    return true
                }
            }
        }

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
}
