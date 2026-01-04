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
    private let xcodeDetector = XcodeDetector()
    private let finderDetector = FinderDetector()
    private let opencodeDetector = OpencodeDetector()
    private let codexDetector = CodexDetector()
    private let dropboxDetector = DropboxDetector()
    private let googleDriveDetector = GoogleDriveDetector()
    private let oneDriveDetector = OneDriveDetector()
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
        if trackingSettings.trackXcode {
            xcodeDetector.startMonitoring()
        }
        if trackingSettings.trackFinder {
            finderDetector.startMonitoring()
        }
        if trackingSettings.trackOpencode {
            opencodeDetector.startMonitoring()
        }
        if trackingSettings.trackCodex {
            codexDetector.startMonitoring()
        }
        if trackingSettings.trackDropbox {
            dropboxDetector.startMonitoring()
        }
        if trackingSettings.trackGoogleDrive {
            googleDriveDetector.startMonitoring()
        }
        if trackingSettings.trackOneDrive {
            oneDriveDetector.startMonitoring()
        }
    }

    func stopMonitoring() {
        claudeDetector.stopMonitoring()
        androidStudioDetector.stopMonitoring()
        xcodeDetector.stopMonitoring()
        finderDetector.stopMonitoring()
        opencodeDetector.stopMonitoring()
        codexDetector.stopMonitoring()
        dropboxDetector.stopMonitoring()
        googleDriveDetector.stopMonitoring()
        oneDriveDetector.stopMonitoring()
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

        xcodeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        finderDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        opencodeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        codexDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        dropboxDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        googleDriveDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        oneDriveDetector.$isActive
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

        trackingSettings.$trackXcode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.xcodeDetector.startMonitoring()
                } else {
                    self.xcodeDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackFinder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.finderDetector.startMonitoring()
                } else {
                    self.finderDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackOpencode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.opencodeDetector.startMonitoring()
                } else {
                    self.opencodeDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackCodex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.codexDetector.startMonitoring()
                } else {
                    self.codexDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackDropbox
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.dropboxDetector.startMonitoring()
                } else {
                    self.dropboxDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackGoogleDrive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.googleDriveDetector.startMonitoring()
                } else {
                    self.googleDriveDetector.stopMonitoring()
                }
                self.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackOneDrive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.oneDriveDetector.startMonitoring()
                } else {
                    self.oneDriveDetector.stopMonitoring()
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

        if trackingSettings.trackXcode && xcodeDetector.isActive {
            processes.append(.xcode)
        }

        if trackingSettings.trackFinder && finderDetector.isActive {
            processes.append(.finder)
        }

        if trackingSettings.trackOpencode && opencodeDetector.isActive {
            processes.append(.opencode)
        }

        if trackingSettings.trackCodex && codexDetector.isActive {
            processes.append(.codex)
        }

        if trackingSettings.trackDropbox && dropboxDetector.isActive {
            processes.append(.dropbox)
        }

        if trackingSettings.trackGoogleDrive && googleDriveDetector.isActive {
            processes.append(.googleDrive)
        }

        if trackingSettings.trackOneDrive && oneDriveDetector.isActive {
            processes.append(.oneDrive)
        }

        activeProcesses = processes
    }

    deinit {
        stopMonitoring()
    }
}
