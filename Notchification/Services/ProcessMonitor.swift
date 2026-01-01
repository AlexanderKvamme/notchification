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
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    func startMonitoring() {
        claudeDetector.startMonitoring()
        // Future: xcodeDetector.startMonitoring()
        // Future: androidStudioDetector.startMonitoring()
    }

    func stopMonitoring() {
        claudeDetector.stopMonitoring()
    }

    private func setupBindings() {
        claudeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)
    }

    private func updateActiveProcesses() {
        var processes: [ProcessType] = []

        if claudeDetector.isActive {
            processes.append(.claude)
        }

        // Future: Check xcode detector
        // Future: Check android studio detector

        activeProcesses = processes
    }

    deinit {
        stopMonitoring()
    }
}
