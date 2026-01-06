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

/// Detects if Android Studio is actively building
final class AndroidStudioDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .androidStudio
    private var gradlePath: String?

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.android-check", qos: .utility)

    private var debug: Bool { DebugSettings.shared.debugAndroid }

    init() {
        findGradlePath()
        if debug {
            if let path = gradlePath {
                print("🤖 AndroidStudioDetector init - gradle found: \(path)")
            } else {
                print("🤖 AndroidStudioDetector init - NO GRADLE FOUND")
            }
        }
    }

    /// Find the gradle executable path
    private func findGradlePath() {
        let debug = DebugSettings.shared.debugAndroid

        // Check common Homebrew locations first
        let homebrewPaths = [
            "/opt/homebrew/bin/gradle",
            "/usr/local/bin/gradle"
        ]

        for path in homebrewPaths {
            if FileManager.default.fileExists(atPath: path) {
                if debug { print("🤖 Found gradle at Homebrew path: \(path)") }
                gradlePath = path
                return
            }
        }

        if debug { print("🤖 No Homebrew gradle, searching ~/.gradle/wrapper/dists...") }

        // Search for any gradle wrapper version dynamically
        // Check GRADLE_USER_HOME first, fall back to ~/.gradle
        let gradleHome = ProcessInfo.processInfo.environment["GRADLE_USER_HOME"]
            ?? NSString(string: "~/.gradle").expandingTildeInPath

        if debug { print("🤖 Searching for gradle in: \(gradleHome)/wrapper/dists") }

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
                if debug { print("🤖 Found gradle wrapper: \(path)") }
                gradlePath = path
            } else {
                if debug { print("🤖 No gradle wrapper found in ~/.gradle/wrapper/dists") }
            }
        } catch {
            if debug { print("🤖 Error searching for gradle: \(error)") }
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

    func poll() {
        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let (building, details) = self.isGradleBusy()
            let debug = DebugSettings.shared.debugAndroid

            DispatchQueue.main.async {
                // NOTE: Keep debug logs - helps diagnose detection issues
                if debug {
                    print("🤖 Android building=\(building) | \(details)")
                }

                if building {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0
                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        if debug { print("🤖 >>> SHOWING ANDROID INDICATOR") }
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        if debug { print("🤖 >>> HIDING ANDROID INDICATOR") }
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if gradle daemon is BUSY using gradle --status
    private func isGradleBusy() -> (Bool, String) {
        guard let gradle = gradlePath else {
            return (false, "no gradle path")
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
                if debug { print("🤖 Using JAVA_HOME: \(javaHome)") }
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
            return (false, "gradle error: \(error)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        let combined = output + errOutput

        if DebugSettings.shared.debugAndroid && !combined.isEmpty && !combined.contains("Only Daemons for the current Gradle version") {
            print("🤖 gradle output: \(combined.prefix(200))")
        }

        if combined.contains("BUSY") {
            return (true, "daemon BUSY")
        }

        if combined.contains("IDLE") {
            return (false, "daemon IDLE")
        }

        return (false, combined.isEmpty ? "no output" : "no daemon status")
    }
}
