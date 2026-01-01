//
//  ClaudeDetector.swift
//  Notchification
//

import Foundation
import Combine

/// Detects if Claude CLI is actively "thinking" (generating a response)
/// by monitoring CPU usage of the claude process.
final class ClaudeDetector: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 0.5
    private let cpuThresholdHigh: Double = 3.0  // CPU% above this = working
    private let cpuThresholdLow: Double = 1.0   // CPU% below this = idle
    private var consecutiveLowReadings: Int = 0
    private let requiredLowReadings: Int = 4    // 2 seconds of low CPU to go idle
    private let queue = DispatchQueue(label: "com.notchification.claudedetector", qos: .utility)

    init() {}

    func startMonitoring() {
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
    }

    private func checkClaudeStatus() {
        guard let pid = getClaudePID() else {
            updateStatus(isActive: false)
            return
        }

        let cpuUsage = getCPUUsage(for: pid)

        if cpuUsage > cpuThresholdHigh {
            consecutiveLowReadings = 0
            updateStatus(isActive: true)
        } else if cpuUsage < cpuThresholdLow {
            consecutiveLowReadings += 1
            if consecutiveLowReadings >= requiredLowReadings {
                updateStatus(isActive: false)
            }
        }
    }

    private func updateStatus(isActive: Bool) {
        if self.isActive != isActive {
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
