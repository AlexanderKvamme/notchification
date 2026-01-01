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
        windowController.hide()
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    // MARK: - Mock Mode

    func startMock(duration: TimeInterval, processes: [ProcessType] = [.claude]) {
        stopMock() // Cancel any existing mock
        isMocking = true
        windowController.update(with: processes)

        mockTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopMock()
        }
    }

    func stopMock() {
        mockTimer?.invalidate()
        mockTimer = nil
        isMocking = false
        windowController.hide()
    }
}

/// Menu bar dropdown view
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Toggle(appState.isMonitoring ? "Monitoring Active" : "Monitoring Paused",
                   isOn: Binding(
                    get: { appState.isMonitoring },
                    set: { _ in appState.toggleMonitoring() }
                   ))

            Divider()

            Text("Mock Mode")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Mock Claude (3s)") {
                appState.startMock(duration: 3, processes: [.claude])
            }

            Button("Mock Claude (10s)") {
                appState.startMock(duration: 10, processes: [.claude])
            }

            Button("Mock All (5s)") {
                appState.startMock(duration: 5, processes: [.claude, .xcode, .androidStudio])
            }

            if appState.isMocking {
                Button("Stop Mock") {
                    appState.stopMock()
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
