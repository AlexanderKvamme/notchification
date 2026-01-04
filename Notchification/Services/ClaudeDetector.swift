//
//  ClaudeDetector.swift
//  Notchification
//
//  Color: #D97757 (Claude orange)
//

import Foundation
import Combine

/// Detects if Claude CLI is actively "thinking" (generating a response)
/// Uses CPU-based state machine with rolling average (inspired by ClaudeCodeMonitor)
final class ClaudeDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 0.3
    private let queue = DispatchQueue(label: "com.notchification.claudedetector", qos: .utility)

    // CPU thresholds - read from settings
    private var cpuLowMax: Double { ThresholdSettings.shared.claudeLowThreshold }
    private var cpuMedMax: Double { ThresholdSettings.shared.claudeHighThreshold }

    // Consecutive readings required
    private let requiredHighToShow: Int = 2   // 2 consecutive highs → show
    private let requiredLowToHide: Int = 2    // 2 consecutive lows → hide

    // Counters
    private var consecutiveHighReadings: Int = 0
    private var consecutiveLowReadings: Int = 0

    init() {}

    func startMonitoring() {
        consecutiveHighReadings = 0
        consecutiveLowReadings = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.checkClaudeStatus()
        }
        timer.resume()
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        DispatchQueue.main.async {
            self.isActive = false
        }
    }

    private func checkClaudeStatus() {
        let debug = DebugSettings.shared.debugClaude

        guard let pid = getClaudePID() else {
            if debug { print("🔶 Claude: No process found") }
            consecutiveHighReadings = 0
            consecutiveLowReadings += 1
            if consecutiveLowReadings >= requiredLowToHide {
                updateStatus(isActive: false)
            }
            return
        }

        let cpu = getCPUUsage(for: pid)

        if cpu >= cpuMedMax {
            // HIGH (20+) - count towards showing
            consecutiveHighReadings += 1
            consecutiveLowReadings = 0
            if debug { print("🔶 Claude HIGH: \(String(format: "%.1f", cpu))% | high: \(consecutiveHighReadings)/\(requiredHighToShow) | active: \(isActive)") }
            if consecutiveHighReadings >= requiredHighToShow {
                updateStatus(isActive: true)
            }
        } else if cpu <= cpuLowMax {
            // LOW (0-10) - count towards hiding
            consecutiveLowReadings += 1
            consecutiveHighReadings = 0
            if debug { print("🔶 Claude LOW: \(String(format: "%.1f", cpu))% | low: \(consecutiveLowReadings)/\(requiredLowToHide) | active: \(isActive)") }
            if consecutiveLowReadings >= requiredLowToHide {
                updateStatus(isActive: false)
            }
        } else {
            // MEDIUM (10-20) - neutral, don't count
            if debug { print("🔶 Claude MED: \(String(format: "%.1f", cpu))% | active: \(isActive)") }
        }
    }

    /// Get process state (R = running, S = sleeping)
    private func getProcessState(for pid: Int32) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "state=", "-p", "\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return "S"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "S"
    }

    private func updateStatus(isActive: Bool) {
        if self.isActive != isActive {
            if DebugSettings.shared.debugClaude {
                print("🔶 Claude STATUS: \(isActive ? "ACTIVE ▶️" : "INACTIVE ⏹️")")
            }
            DispatchQueue.main.async {
                self.isActive = isActive
            }
        }
    }

    /// Find the PID of the claude process
    private func getClaudePID() -> Int32? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "claude"]

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

        // Take the first PID if multiple
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

    deinit {
        stopMonitoring()
    }
}
