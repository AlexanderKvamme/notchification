//
//  AndroidStudioDetector.swift
//  Notchification
//
//  Color: #2BA160 (Android green)
//  Detects Android Studio builds using `gradle --status` command
//  which shows BUSY when a Gradle daemon is building.
//  Works with any Gradle version - searches dynamically.
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
    private var gradlePath: String?
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

    // Debug logging is ALWAYS enabled for Android Studio (users need Console.app to see it)
    private var debug: Bool { true }

    private func log(_ message: String) {
        os_log("[Notchification] 🤖 %{public}@", log: logger, type: .info, message)
    }

    init() {
        log("========== AndroidStudioDetector initializing ==========")

        // Log environment
        if let gradleUserHome = ProcessInfo.processInfo.environment["GRADLE_USER_HOME"] {
            log("GRADLE_USER_HOME env: \(gradleUserHome)")
        } else {
            log("GRADLE_USER_HOME env: not set (will use ~/.gradle)")
        }

        if let javaHomeEnv = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            log("JAVA_HOME env: \(javaHomeEnv)")
        } else {
            log("JAVA_HOME env: not set")
        }

        // Find and log gradle path
        findGradlePath()
        if let path = gradlePath {
            log("✅ Gradle found at: \(path)")
            // Check if executable
            if FileManager.default.isExecutableFile(atPath: path) {
                log("✅ Gradle is executable")
            } else {
                log("⚠️ Gradle file exists but is NOT executable!")
            }
        } else {
            log("❌ NO GRADLE FOUND - Android Studio detection will not work!")
            log("   Searched: /opt/homebrew/bin/gradle")
            log("   Searched: /usr/local/bin/gradle")
            log("   Searched: ~/.gradle/wrapper/dists/*/bin/gradle")
        }

        // Log Java home status (found via java_home utility or Android Studio JBR)
        if let javaHome = findJavaHome() {
            log("✅ Java found at: \(javaHome)")
        } else {
            log("⚠️ No Java found via /usr/libexec/java_home or Android Studio JBR")
        }

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

    /// Find the gradle executable path
    private func findGradlePath() {
        // Check common Homebrew locations first
        let homebrewPaths = [
            "/opt/homebrew/bin/gradle",
            "/usr/local/bin/gradle"
        ]

        for path in homebrewPaths {
            if FileManager.default.fileExists(atPath: path) {
                log("Found gradle at Homebrew path: \(path)")
                gradlePath = path
                return
            }
        }

        log("No Homebrew gradle found, searching ~/.gradle/wrapper/dists...")

        // Search for any gradle wrapper version dynamically
        // Check GRADLE_USER_HOME first, fall back to ~/.gradle
        let gradleHome = ProcessInfo.processInfo.environment["GRADLE_USER_HOME"]
            ?? NSString(string: "~/.gradle").expandingTildeInPath

        log("Searching for gradle wrapper in: \(gradleHome)/wrapper/dists")

        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "find '\(gradleHome)/wrapper/dists' -name 'gradle' -type f -path '*/bin/*' 2>/dev/null | head -1"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                log("Found gradle wrapper: \(path)")
                gradlePath = path
            } else {
                log("No gradle wrapper found in \(gradleHome)/wrapper/dists")
            }
        } catch {
            log("Error searching for gradle: \(error)")
        }
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    /// Find Java home using macOS java_home utility, fallback to Android Studio's bundled JBR
    private func findJavaHome() -> String? {
        // Try macOS built-in java_home utility first
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // java_home not available or failed
        }

        // Fallback: Search for any Android Studio variant's bundled JBR
        let appDirs = ["/Applications", NSString(string: "~/Applications").expandingTildeInPath]

        for appDir in appDirs {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: appDir) {
                for app in contents where app.hasPrefix("Android Studio") && app.hasSuffix(".app") {
                    let jbrPath = "\(appDir)/\(app)/Contents/jbr/Contents/Home"
                    if FileManager.default.fileExists(atPath: jbrPath) {
                        return jbrPath
                    }
                }
            }
        }

        return nil
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

    /// Check if gradle daemon is BUSY using gradle --status
    private func isGradleBusy() -> (Bool, String) {
        guard let gradle = gradlePath else {
            return (false, "⚠️ no gradle path configured")
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        let task = Process()

        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "\(gradle) --status 2>&1"]

        // Set JAVA_HOME if not already set
        var env = ProcessInfo.processInfo.environment
        if env["JAVA_HOME"] == nil {
            if let javaHome = findJavaHome() {
                env["JAVA_HOME"] = javaHome
            } else {
                log("⚠️ JAVA_HOME not set and could not find Java automatically")
            }
        }
        task.environment = env

        task.standardOutput = outPipe
        task.standardError = errPipe

        // Timeout after 2 seconds
        let timeoutWork = DispatchWorkItem { [weak task] in
            if task?.isRunning == true {
                task?.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutWork)

        do {
            try task.run()
            task.waitUntilExit()
            timeoutWork.cancel()
        } catch {
            timeoutWork.cancel()
            log("❌ gradle --status failed to run: \(error)")
            return (false, "gradle error: \(error)")
        }

        let exitCode = task.terminationStatus
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        let combined = output + errOutput

        // Log exit code if non-zero
        if exitCode != 0 {
            log("⚠️ gradle --status exit code: \(exitCode)")
        }

        // Log gradle output if it contains useful info (not just the default message)
        if !combined.isEmpty && !combined.contains("Only Daemons for the current Gradle version") {
            log("gradle --status output: \(String(combined.prefix(300)))")
        }

        if combined.contains("BUSY") {
            return (true, "daemon BUSY")
        }

        if combined.contains("IDLE") {
            return (false, "daemon IDLE")
        }

        // Log unexpected output for debugging
        if !combined.isEmpty {
            log("⚠️ Unexpected gradle output (no BUSY/IDLE): \(String(combined.prefix(200)))")
        }

        return (false, combined.isEmpty ? "no output from gradle" : "no BUSY/IDLE in output")
    }
}
