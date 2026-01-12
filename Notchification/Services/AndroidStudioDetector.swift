//
//  AndroidStudioDetector.swift
//  Notchification
//
//  Color: #2BA160 (Android green)
//  Detects Android Studio builds by monitoring GradleDaemon CPU usage.
//  Version-agnostic - works with any Gradle version.
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = OSLog(subsystem: "com.notchification", category: "AndroidStudio")

/// Detects if Android Studio is actively building
final class AndroidStudioDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .androidStudio
    private var detectedBundleId: String?
    private var lastLoggedStatus: String?

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.android-check", qos: .utility)

    private func log(_ message: String) {
        os_log("[Notchification] 🤖 %{public}@", log: logger, type: .info, message)
    }

    init() {
        log("========== AndroidStudioDetector initializing ==========")
        log("Detection method: CPU monitoring of GradleDaemon processes (version-agnostic)")

        // Log currently running Google apps (helps debug bundle ID issues)
        let googleApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.contains("google") == true || $0.bundleIdentifier?.contains("android") == true
        }
        if googleApps.isEmpty {
            log("No Google/Android apps currently running")
        } else {
            log("Currently running Google/Android apps:")
            for app in googleApps {
                log("   - \(app.bundleIdentifier ?? "unknown") (\(app.localizedName ?? "?"))")
            }
        }

        log("========== AndroidStudioDetector ready ==========")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    /// Check if Android Studio is running (cheap check using NSWorkspace)
    /// Matches any bundle ID starting with "com.google.android.studio" to cover all variants:
    /// - Stable: com.google.android.studio
    /// - Beta/RC: com.google.android.studio.beta
    /// - Canary: com.google.android.studio.canary
    /// - Dev: com.google.android.studio.dev
    private var isAndroidStudioRunning: Bool {
        let found = NSWorkspace.shared.runningApplications.first { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return bundleId.hasPrefix("com.google.android.studio")
        }
        if let app = found, let bundleId = app.bundleIdentifier {
            // Only log if bundle ID changed (avoid spam)
            if detectedBundleId != bundleId {
                detectedBundleId = bundleId
                log("Android Studio detected - bundle ID: \(bundleId)")
            }
        }
        return found != nil
    }

    func poll() {
        // Skip expensive checks if Android Studio isn't running
        guard isAndroidStudioRunning else {
            if isActive {
                DispatchQueue.main.async { self.reset() }
            }
            return
        }

        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let (building, details) = self.isGradleBusy()

            DispatchQueue.main.async {
                // Only log when status changes to avoid spam
                let statusKey = "\(building)-\(details)"
                if self.lastLoggedStatus != statusKey {
                    self.lastLoggedStatus = statusKey
                    self.log("Gradle status: building=\(building) | \(details)")
                }

                if building {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0
                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        self.log("✅ SHOWING Android Studio indicator")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        self.log("⏹️ HIDING Android Studio indicator")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if any gradle daemon is BUSY by monitoring CPU usage
    /// This is version-agnostic - works regardless of which gradle version is installed
    private func isGradleBusy() -> (Bool, String) {
        // Use ps to find GradleDaemon processes and their CPU usage
        // A daemon with >5% CPU is likely building
        let pipe = Pipe()
        let task = Process()

        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Get PID, CPU%, and command for GradleDaemon processes
        task.arguments = ["-c", "ps -eo pid,%cpu,comm | grep -i 'GradleDaemon\\|gradle' | grep -v grep"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // Timeout after 1 second
        let timeoutWork = DispatchWorkItem { [weak task] in
            if task?.isRunning == true { task?.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0, execute: timeoutWork)

        do {
            try task.run()
            task.waitUntilExit()
            timeoutWork.cancel()
        } catch {
            timeoutWork.cancel()
            return (false, "ps error: \(error)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if output.isEmpty {
            return (false, "no GradleDaemon processes")
        }

        // Parse ps output - look for any daemon using significant CPU
        var maxCpu: Double = 0
        var daemonCount = 0

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            if parts.count >= 2 {
                daemonCount += 1
                if let cpu = Double(parts[1]) {
                    maxCpu = max(maxCpu, cpu)
                }
            }
        }

        // Consider daemon "busy" if CPU > 5%
        // Idle daemons typically use 0% CPU
        let isBusy = maxCpu > 5.0

        if isBusy {
            let detail = "GradleDaemon active (CPU: \(String(format: "%.1f", maxCpu))%)"
            log("✅ \(detail)")
            return (true, detail)
        }

        return (false, "\(daemonCount) daemon(s) idle (CPU: \(String(format: "%.1f", maxCpu))%)")
    }
}
