//
//  XcodeDetector.swift
//  Notchification
//
//  Color: #147EFB (Xcode blue)
//  Detects Xcode builds by monitoring XCBBuildService process
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "XcodeDetector")

/// Detects if Xcode is actively building
final class XcodeDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .xcode

    // CPU threshold - read from settings
    private var cpuThreshold: Double { ThresholdSettings.shared.xcodeThreshold }

    // Debug logging toggle
    private var debug: Bool { DebugSettings.shared.debugXcode }

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 5

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.xcode-check", qos: .utility)

    init() {
        logger.info("🔨 XcodeDetector init")
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        isActive = false
    }

    /// Check if Xcode is running (cheap check using NSWorkspace)
    private var isXcodeRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.dt.Xcode" }
    }

    func poll() {
        // Skip expensive checks if Xcode isn't running
        guard isXcodeRunning else {
            if isActive {
                DispatchQueue.main.async { self.reset() }
            }
            return
        }

        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let (building, details) = self.isXcodeBuilding()

            DispatchQueue.main.async {
                if building {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0
                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        logger.info("🔨 Xcode build started: \(details)")
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        logger.info("🔨 Xcode build finished")
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check if Xcode is building by looking for active compiler processes or high CPU on XCBBuildService
    private func isXcodeBuilding() -> (Bool, String) {
        // Check for swift-frontend processes (active compilation)
        let swiftCount = getProcessCount(name: "swift-frontend")
        if swiftCount > 0 {
            if debug { print("🔨 Xcode: Detected \(swiftCount) swift-frontend processes") }
            return (true, "\(swiftCount) swift-frontend processes")
        }

        // Check for clang processes (C/ObjC compilation)
        let clangCount = getProcessCount(name: "clang")
        if clangCount > 0 {
            if debug { print("🔨 Xcode: Detected \(clangCount) clang processes") }
            return (true, "\(clangCount) clang processes")
        }

        // Check XCBBuildService CPU as fallback
        if let pid = getProcessPID(name: "XCBBuildService") {
            let cpu = getCPUUsage(for: pid)
            if debug { print("🔨 Xcode: XCBBuildService CPU: \(String(format: "%.1f", cpu))% (threshold: \(cpuThreshold)%)") }
            if cpu >= cpuThreshold {
                return (true, "XCBBuildService CPU: \(String(format: "%.1f", cpu))%")
            }
            return (false, "XCBBuildService idle: \(String(format: "%.1f", cpu))%")
        }

        if debug { print("🔨 Xcode: No build processes found") }
        return (false, "no build processes")
    }

    /// Count running processes with given name
    private func getProcessCount(name: String) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return 0
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return 0
        }

        return output.components(separatedBy: .newlines).count
    }

    /// Find the PID of a process by name
    private func getProcessPID(name: String) -> Int32? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let firstPID = output.components(separatedBy: .newlines).first ?? output
        return Int32(firstPID)
    }

    /// Get CPU usage percentage for a given PID
    private func getCPUUsage(for pid: Int32) -> Double {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "%cpu=", "-p", "\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return 0.0
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let cpu = Double(output) else {
            return 0.0
        }

        return cpu
    }
}
