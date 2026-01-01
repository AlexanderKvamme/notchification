//
//  NotchificationApp.swift
//  Notchification
//

import SwiftUI
import Combine

@main
struct NotchificationApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Notchification", systemImage: "bell.badge") {
            MenuBarView(appState: appState)
        }
    }
}

/// Main app state that coordinates monitoring and UI
final class AppState: ObservableObject {
    @Published var isMonitoring: Bool = true
    @Published var isMocking: Bool = false

    private let processMonitor = ProcessMonitor()
    private let windowController = NotchWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var mockTimer: Timer?

    init() {
        setupBindings()
        startMonitoring()
    }

    private func setupBindings() {
        processMonitor.$activeProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                guard let self = self, !self.isMocking else { return }
                self.windowController.update(with: processes)
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        isMonitoring = true
        processMonitor.startMonitoring()
    }

    func stopMonitoring() {
        isMonitoring = false
        processMonitor.stopMonitoring()
        windowController.update(with: [])
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            if isMocking { stopMockLoop() }
            startMonitoring()
        }
    }

    // MARK: - Mock Mode

    func toggleMockMode() {
        if isMocking {
            stopMockLoop()
        } else {
            if isMonitoring { stopMonitoring() }
            startMockLoop()
        }
    }

    private func startMockLoop() {
        isMocking = true
        mockTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.toggleMockState()
        }
        toggleMockState() // Start immediately
    }

    private func toggleMockState() {
        let isShowing = windowController.isShowing
        windowController.update(with: isShowing ? [] : [.claude])
    }

    private func stopMockLoop() {
        mockTimer?.invalidate()
        mockTimer = nil
        isMocking = false
        windowController.update(with: [])
    }
}

/// Menu bar dropdown view
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Toggle("Monitoring", isOn: Binding(
                get: { appState.isMonitoring },
                set: { _ in appState.toggleMonitoring() }
            ))

            Toggle("Mock Mode", isOn: Binding(
                get: { appState.isMocking },
                set: { _ in appState.toggleMockMode() }
            ))

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
