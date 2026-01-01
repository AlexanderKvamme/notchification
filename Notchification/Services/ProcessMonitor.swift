//
//  ProcessMonitor.swift
//  Notchification
//

import Foundation
import Combine

/// Aggregates all process detectors and publishes the list of active processes
final class ProcessMonitor: ObservableObject {
    @Published private(set) var activeProcesses: [ProcessType] = []

    private let claudeDetector = ClaudeDetector()
    private let androidStudioDetector = AndroidStudioDetector()
    private let trackingSettings = TrackingSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    func startMonitoring() {
        // Start only enabled detectors
        if trackingSettings.trackClaude {
            claudeDetector.startMonitoring()
        }
        if trackingSettings.trackAndroidStudio {
            androidStudioDetector.startMonitoring()
        }
        // Future: if trackingSettings.trackXcode { xcodeDetector.startMonitoring() }
    }

    func stopMonitoring() {
        claudeDetector.stopMonitoring()
        androidStudioDetector.stopMonitoring()
    }

    private func setupBindings() {
        // Listen to detector state changes
        claudeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        androidStudioDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        // Listen to tracking settings changes
        trackingSettings.$trackClaude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.claudeDetector.startMonitoring()
                } else {
                    self.claudeDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackAndroidStudio
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.androidStudioDetector.startMonitoring()
                } else {
                    self.androidStudioDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)
    }

    private func updateActiveProcesses() {
        var processes: [ProcessType] = []

        if trackingSettings.trackClaude && claudeDetector.isActive {
            processes.append(.claude)
        }

        if trackingSettings.trackAndroidStudio && androidStudioDetector.isActive {
            processes.append(.androidStudio)
        }

        // Future: Check xcode detector with trackingSettings.trackXcode

        activeProcesses = processes
    }

    deinit {
        stopMonitoring()
    }
}
