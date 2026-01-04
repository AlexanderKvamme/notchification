//
//  InstallerDetector.swift
//  Notchification
//
//  Detects macOS Installer.app activity (pkg installations)
//  Color: Purple (system installer)
//

import Foundation
import Combine
import AppKit

/// Detects if Installer.app is running (pkg installations)
final class InstallerDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?
    private let bundleIdentifier = "com.apple.installer"

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {}

    func startMonitoring() {
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
        let isRunning = isInstallerRunning()

        if isRunning {
            consecutiveActiveReadings += 1
            consecutiveInactiveReadings = 0

            if consecutiveActiveReadings >= requiredToShow && !isActive {
                isActive = true
            }
        } else {
            consecutiveInactiveReadings += 1
            consecutiveActiveReadings = 0

            if consecutiveInactiveReadings >= requiredToHide && isActive {
                isActive = false
            }
        }
    }

    /// Check if Installer.app is running
    private func isInstallerRunning() -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return !runningApps.isEmpty
    }

    deinit {
        stopMonitoring()
    }
}
