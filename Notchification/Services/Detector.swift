//
//  Detector.swift
//  Notchification
//
//  Protocol for all service detectors
//

import Foundation

/// Protocol that all detectors conform to
protocol Detector: AnyObject {
    /// Whether this detector currently detects activity
    var isActive: Bool { get }

    /// The process type this detector handles
    var processType: ProcessType { get }

    /// Called by ProcessMonitor on each tick - detector handles its own async work
    func poll()

    /// Reset state when detector is enabled/disabled
    func reset()
}
