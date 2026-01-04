//
//  AndroidStudioDetector.swift
//  Notchification
//
//  Color: #2BA160 (Android green)
//  Detects Android Studio builds using gradle --status command
//  which shows BUSY when a build is running
//

import Foundation
import Combine

/// Detects if Android Studio is actively building
final class AndroidStudioDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?
    private var gradlePath: String?

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 3

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    init() {
        findGradlePath()
    }

    /// Find the gradle executable path
    private func findGradlePath() {
        // Check common locations
        let possiblePaths = [
            "/opt/homebrew/bin/gradle",
            "/usr/local/bin/gradle",
            NSString(string: "~/.gradle/wrapper/dists/gradle-9.0.0-bin").expandingTildeInPath + "/d6wjpkvcgsg3oed0qlfss3wgl/gradle-9.0.0/bin/gradle"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                gradlePath = path
                return
            }
        }

        // Try to find dynamically
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "find ~/.gradle/wrapper/dists -name 'gradle' -type f -path '*/bin/*' 2>/dev/null | head -1"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                gradlePath = path
            }
        } catch {
            // Silently fail - gradle not found
        }
    }

    func startMonitoring() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0

        // Create timer and add to .common mode so it fires even when menu is open
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Fire immediately
        checkStatus()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func checkStatus() {
        // Run on background to not block UI
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let (building, details) = self.isGradleBusy()
            let debug = DebugSettings.shared.debugAndroid

            DispatchQueue.main.async {
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

        // Use bash to run gradle with proper environment
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "\(gradle) --status 2>&1"]

        // Set JAVA_HOME if needed
        var env = ProcessInfo.processInfo.environment
        if env["JAVA_HOME"] == nil {
            // Try common Android Studio JBR location
            let jbrPath = NSString(string: "~/Applications/Android Studio.app/Contents/jbr/Contents/Home").expandingTildeInPath
            if FileManager.default.fileExists(atPath: jbrPath) {
                env["JAVA_HOME"] = jbrPath
            }
        }
        task.environment = env

        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (false, "gradle error: \(error)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        let combined = output + errOutput

        // Only log if debug enabled and not just boilerplate messages
        if DebugSettings.shared.debugAndroid && !combined.isEmpty && !combined.contains("Only Daemons for the current Gradle version") {
            print("🤖 gradle output: \(combined.prefix(200))")
        }

        // Check if any daemon is BUSY
        if combined.contains("BUSY") {
            return (true, "daemon BUSY")
        }

        if combined.contains("IDLE") {
            return (false, "daemon IDLE")
        }

        return (false, combined.isEmpty ? "no output" : "no daemon status")
    }

    deinit {
        stopMonitoring()
    }
}
