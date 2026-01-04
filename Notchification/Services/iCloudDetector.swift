//
//  iCloudDetector.swift
//  Notchification
//
//  Detects iCloud sync activity by monitoring the 'cloudd' daemon CPU usage
//  Color: iCloud blue
//

import Foundation
import Combine

/// Detects if iCloud is actively syncing by monitoring the cloudd daemon
final class iCloudDetector: ObservableObject {
    private let debug = false  // Set to true for debug logging
    @Published private(set) var isActive: Bool = false

    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.notchification.iclouddetector", qos: .utility)

    // CPU thresholds for cloudd process (lower since iCloud doesn't spike CPU much)
    private let cpuThresholdLow: Double = 0.5   // Below this = idle
    private let cpuThresholdHigh: Double = 1.5  // Above this = syncing

    // Consecutive readings required
    private let requiredToShow: Int = 3
    private let requiredToHide: Int = 4

    private var consecutiveHighReadings: Int = 0
    private var consecutiveLowReadings: Int = 0

    init() {}

    func startMonitoring() {
        consecutiveHighReadings = 0
        consecutiveLowReadings = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.checkStatus()
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

    private func checkStatus() {
        let pids = getClouddPIDs()
        guard !pids.isEmpty else {
            if debug { print("☁️ iCloud: cloudd not found") }
            consecutiveHighReadings = 0
            consecutiveLowReadings += 1
            if consecutiveLowReadings >= requiredToHide {
                updateStatus(isActive: false)
            }
            return
        }

        // Check all cloudd processes and use the highest CPU value
        var maxCpu: Double = 0.0
        for pid in pids {
            let cpu = getCPUUsage(for: pid)
            if cpu > maxCpu {
                maxCpu = cpu
            }
        }

        if debug { print("☁️ iCloud: \(pids.count) cloudd processes, max CPU=\(maxCpu)%") }

        if maxCpu >= cpuThresholdHigh {
            consecutiveHighReadings += 1
            consecutiveLowReadings = 0
            if debug { print("☁️ iCloud: HIGH readings=\(consecutiveHighReadings)/\(requiredToShow)") }
            if consecutiveHighReadings >= requiredToShow {
                updateStatus(isActive: true)
            }
        } else if maxCpu <= cpuThresholdLow {
            consecutiveLowReadings += 1
            consecutiveHighReadings = 0
            if debug { print("☁️ iCloud: LOW readings=\(consecutiveLowReadings)/\(requiredToHide)") }
            if consecutiveLowReadings >= requiredToHide {
                updateStatus(isActive: false)
            }
        }
        // Between thresholds: don't change state
    }

    private func updateStatus(isActive: Bool) {
        if self.isActive != isActive {
            if debug { print("☁️ iCloud: STATUS CHANGED to \(isActive ? "ACTIVE" : "INACTIVE")") }
            DispatchQueue.main.async {
                self.isActive = isActive
            }
        }
    }

    /// Find all PIDs of cloudd processes (iCloud sync daemon)
    private func getClouddPIDs() -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "cloudd"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        // Return all PIDs
        return output.components(separatedBy: .newlines).compactMap { Int32($0) }
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
