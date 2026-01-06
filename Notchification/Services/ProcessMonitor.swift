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
    static let shared = ProcessMonitor()

    @Published private(set) var activeProcesses: [ProcessType] = []

    /// Processes that were manually dismissed - won't show until they finish and restart
    private(set) var dismissedProcesses: Set<ProcessType> = []

    /// Track which processes were active last tick (to detect when they finish)
    private var previouslyActiveDetectors: Set<ProcessType> = []

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
    private let automatorDetector = AutomatorDetector()
    private let scriptEditorDetector = ScriptEditorDetector()
    private let downloadDetector = DownloadDetector()
    private let davinciResolveDetector = DaVinciResolveDetector()

    private let trackingSettings = TrackingSettings.shared
    private var cancellables = Set<AnyCancellable>()

    // Central timer using DispatchSourceTimer on background queue
    private var timer: DispatchSourceTimer?
    private let pollingInterval: TimeInterval = 1.0
    private let timerQueue = DispatchQueue(label: "com.notchification.timer", qos: .userInitiated)

    private init() {
        setupBindings()
    }

    /// Dismiss a process - removes it from view until it finishes and starts again
    func dismissProcess(_ process: ProcessType) {
        logger.info("Dismissing process: \(process.displayName)")
        dismissedProcesses.insert(process)
        updateActiveProcesses()
    }

    func startMonitoring() {
        guard timer == nil else { return }

        logger.info("ProcessMonitor: Starting central timer (1s interval)")

        let newTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        newTimer.schedule(deadline: .now(), repeating: pollingInterval)
        newTimer.setEventHandler { [weak self] in
            print("⏱️ TICK \(Date())")
            self?.tick()
        }
        newTimer.resume()
        timer = newTimer
        print("⏱️ Timer created and resumed")
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
        automatorDetector.reset()
        scriptEditorDetector.reset()
        downloadDetector.reset()
        davinciResolveDetector.reset()
    }

    /// Central tick - polls all enabled detectors
    private func tick() {

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
        if trackingSettings.trackAutomator {
            automatorDetector.poll()
        }
        if trackingSettings.trackScriptEditor {
            scriptEditorDetector.poll()
        }
        if trackingSettings.trackDownloads {
            downloadDetector.poll()
        }
        if trackingSettings.trackDaVinciResolve {
            davinciResolveDetector.poll()
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

        automatorDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        scriptEditorDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        downloadDetector.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveProcesses() }
            .store(in: &cancellables)

        davinciResolveDetector.$isActive
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

        trackingSettings.$trackAutomator
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.automatorDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackScriptEditor
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.scriptEditorDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackDownloads
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.downloadDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)

        trackingSettings.$trackDaVinciResolve
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.davinciResolveDetector.reset() }
                self?.updateActiveProcesses()
            }
            .store(in: &cancellables)
    }

    private func updateActiveProcesses() {
        // Build list of all currently active detectors (regardless of dismissal)
        var currentlyActive: Set<ProcessType> = []

        if trackingSettings.trackClaude && claudeDetector.isActive {
            currentlyActive.insert(.claude)
            if DebugSettings.shared.debugClaude {
                logger.debug("🔶 Claude detector isActive=true, adding to currentlyActive")
            }
        }
        if trackingSettings.trackAndroidStudio && androidStudioDetector.isActive {
            currentlyActive.insert(.androidStudio)
        }
        if trackingSettings.trackXcode && xcodeDetector.isActive {
            currentlyActive.insert(.xcode)
        }
        if trackingSettings.trackFinder && finderDetector.isActive {
            currentlyActive.insert(.finder)
        }
        if trackingSettings.trackOpencode && opencodeDetector.isActive {
            currentlyActive.insert(.opencode)
        }
        if trackingSettings.trackCodex && codexDetector.isActive {
            currentlyActive.insert(.codex)
        }
        if trackingSettings.trackDropbox && dropboxDetector.isActive {
            currentlyActive.insert(.dropbox)
        }
        if trackingSettings.trackGoogleDrive && googleDriveDetector.isActive {
            currentlyActive.insert(.googleDrive)
        }
        if trackingSettings.trackOneDrive && oneDriveDetector.isActive {
            currentlyActive.insert(.oneDrive)
        }
        if trackingSettings.trackICloud && icloudDetector.isActive {
            currentlyActive.insert(.icloud)
        }
        if trackingSettings.trackInstaller && installerDetector.isActive {
            currentlyActive.insert(.installer)
        }
        if trackingSettings.trackAppStore && appStoreDetector.isActive {
            currentlyActive.insert(.appStore)
        }
        if trackingSettings.trackAutomator && automatorDetector.isActive {
            currentlyActive.insert(.automator)
        }
        if trackingSettings.trackScriptEditor && scriptEditorDetector.isActive {
            currentlyActive.insert(.scriptEditor)
        }
        if trackingSettings.trackDownloads && downloadDetector.isActive {
            currentlyActive.insert(.downloads)
        }
        if trackingSettings.trackDaVinciResolve && davinciResolveDetector.isActive {
            currentlyActive.insert(.davinciResolve)
        }

        // Clear dismissed flag for processes that have finished (were active, now inactive)
        let finishedProcesses = previouslyActiveDetectors.subtracting(currentlyActive)
        for finished in finishedProcesses {
            if dismissedProcesses.contains(finished) {
                logger.info("Process finished, clearing dismissed flag: \(finished.displayName)")
                dismissedProcesses.remove(finished)
            }
        }
        previouslyActiveDetectors = currentlyActive

        // Filter out dismissed processes for the UI
        let visibleProcesses = currentlyActive.subtracting(dismissedProcesses)
        activeProcesses = Array(visibleProcesses).sorted { $0.rawValue < $1.rawValue }

        // Debug: Show what's happening with Claude
        if DebugSettings.shared.debugClaude {
            if currentlyActive.contains(.claude) {
                if dismissedProcesses.contains(.claude) {
                    logger.debug("🔶 Claude is DISMISSED - not showing (will reappear after Claude finishes)")
                } else {
                    logger.debug("🔶 Claude visible in UI, activeProcesses count: \(self.activeProcesses.count)")
                }
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
