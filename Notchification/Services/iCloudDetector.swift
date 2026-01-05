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
final class iCloudDetector: ObservableObject, Detector {
    private let debug = false
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .icloud

    // CPU thresholds for cloudd process
    private let cpuThresholdLow: Double = 0.5
    private let cpuThresholdHigh: Double = 1.5

    // Consecutive readings required
    private let requiredToShow: Int = 3
    private let requiredToHide: Int = 4

    private var consecutiveHighReadings: Int = 0
    private var consecutiveLowReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.icloud-check", qos: .utility)

    init() {}

    func reset() {
        consecutiveHighReadings = 0
        consecutiveLowReadings = 0
        isActive = false
    }

    func poll() {
        // Dispatch to serial queue - ensures checks run one at a time, never overlap
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let pids = self.getClouddPIDs()
            guard !pids.isEmpty else {
                if self.debug { print("☁️ iCloud: cloudd not found") }
                DispatchQueue.main.async {
                    self.consecutiveHighReadings = 0
                    self.consecutiveLowReadings += 1
                    if self.consecutiveLowReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                    }
                }
                return
            }

            var maxCpu: Double = 0.0
            for pid in pids {
                let cpu = self.getCPUUsage(for: pid)
                if cpu > maxCpu {
                    maxCpu = cpu
                }
            }

            if self.debug { print("☁️ iCloud: \(pids.count) cloudd processes, max CPU=\(maxCpu)%") }

            DispatchQueue.main.async {
                if maxCpu >= self.cpuThresholdHigh {
                    self.consecutiveHighReadings += 1
                    self.consecutiveLowReadings = 0
                    if self.debug { print("☁️ iCloud: HIGH readings=\(self.consecutiveHighReadings)/\(self.requiredToShow)") }
                    if self.consecutiveHighReadings >= self.requiredToShow && !self.isActive {
                        self.isActive = true
                    }
                } else if maxCpu <= self.cpuThresholdLow {
                    self.consecutiveLowReadings += 1
                    self.consecutiveHighReadings = 0
                    if self.debug { print("☁️ iCloud: LOW readings=\(self.consecutiveLowReadings)/\(self.requiredToHide)") }
                    if self.consecutiveLowReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                    }
                }
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
}
