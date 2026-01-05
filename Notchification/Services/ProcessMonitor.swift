//
//  ProcessMonitor.swift
//  Notchification
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "ProcessMonitor")

/// Aggregates all process detectors and publishes the list of active processes
/// Uses a single central timer to poll all enabled detectors
final class ProcessMonitor: ObservableObject {
    @Published private(set) var activeProcesses: [ProcessType] = []

    // All detectors
    private let claudeDetector = ClaudeDetector()
    private let androidStudioDetector = AndroidStudioDetector()
    private let xcodeDetector = XcodeDetector()
    private let finderDetector = FinderDetector()
    private let opencodeDetector = OpencodeDetector()
    private let codexDetector = CodexDetector()
    private let dropboxDetector = DropboxDetector()
    private let googleDriveDetector = GoogleDriveDetector()
    private let oneDriveDetector = OneDriveDetector()
    private let icloudDetector = iCloudDetector()
    private let installerDetector = InstallerDetector()
    private let appStoreDetector = AppStoreDetector()

    private let trackingSettings = TrackingSettings.shared
    private var cancellables = Set<AnyCancellable>()

    // Central timer using DispatchSourceTimer on background queue
    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 1.0
    private let timerQueue = DispatchQueue(label: "com.notchification.timer", qos: .userInitiated)

    init() {
        setupBindings()
    }

    func startMonitoring() {
        guard timer == nil else { return }

        logger.info("ProcessMonitor: Starting central timer (1s interval)")

        let newTimer = DispatchSource.makeTimerSource(queue: timerQueue)
        newTimer.schedule(deadline: .now(), repeating: pollingInterval)
        newTimer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        newTimer.resume()
        timer = newTimer
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil

        // Reset all detectors
        claudeDetector.reset()
        androidStudioDetector.reset()
        xcodeDetector.reset()
        finderDetector.reset()
        opencodeDetector.reset()
        codexDetector.reset()
        dropboxDetector.reset()
        googleDriveDetector.reset()
        oneDriveDetector.reset()
        icloudDetector.reset()
        installerDetector.reset()
        appStoreDetector.reset()
    }

    /// Central tick - polls all enabled detectors
    private func tick() {
        logger.debug("[tick]")

        // Poll each enabled detector
        if trackingSettings.trackClaude {
            claudeDetector.poll()
        }
        if trackingSettings.trackAndroidStudio {
            androidStudioDetector.poll()
        }
        if trackingSettings.trackXcode {
            xcodeDetector.poll()
        }
        if trackingSettings.trackFinder {
            finderDetector.poll()
        }
        if trackingSettings.trackOpencode {
            opencodeDetector.poll()
        }
        if trackingSettings.trackCodex {
            codexDetector.poll()
        }
        if trackingSettings.trackDropbox {
            dropboxDetector.poll()
        }
        if trackingSettings.trackGoogleDrive {
            googleDriveDetector.poll()
        }
        if trackingSettings.trackOneDrive {
            oneDriveDetector.poll()
        }
        if trackingSettings.trackICloud {
            icloudDetector.poll()
        }
        if trackingSettings.trackInstaller {
            installerDetector.poll()
        }
        if trackingSettings.trackAppStore {
            appStoreDetector.poll()
        }
    }

    private func setupBindings() {
        // Listen to detector state changes
        claudeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        androidStudioDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        xcodeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        finderDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        opencodeDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        codexDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        dropboxDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        googleDriveDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        oneDriveDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        icloudDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        installerDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        appStoreDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        // Listen to tracking settings changes - reset detector when toggled
        trackingSettings.$trackClaude
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.claudeDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackAndroidStudio
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.androidStudioDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackXcode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.xcodeDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackFinder
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.finderDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackOpencode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.opencodeDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackCodex
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.codexDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackDropbox
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.dropboxDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackGoogleDrive
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.googleDriveDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackOneDrive
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.oneDriveDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackICloud
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.icloudDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackInstaller
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.installerDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackAppStore
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.appStoreDetector.reset() }
                self?.updateActiveProcesses()
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
        if trackingSettings.trackICloud && icloudDetector.isActive {
            processes.append(.icloud)
        }
        if trackingSettings.trackInstaller && installerDetector.isActive {
            processes.append(.installer)
        }
        if trackingSettings.trackAppStore && appStoreDetector.isActive {
            processes.append(.appStore)
        }

        activeProcesses = processes
    }

    deinit {
        stopMonitoring()
    }
}
