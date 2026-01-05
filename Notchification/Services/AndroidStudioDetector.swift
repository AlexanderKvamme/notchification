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

    init() {
        findGradlePath()
    }

    /// Find the gradle executable path
    private func findGradlePath() {
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

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
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

        var env = ProcessInfo.processInfo.environment
        if env["JAVA_HOME"] == nil {
            let jbrPath = NSString(string: "~/Applications/Android Studio.app/Contents/jbr/Contents/Home").expandingTildeInPath
            if FileManager.default.fileExists(atPath: jbrPath) {
                env["JAVA_HOME"] = jbrPath
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
