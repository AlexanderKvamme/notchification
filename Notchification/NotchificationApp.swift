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

/// Debug settings
final class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    @Published var debugClaude: Bool {
        didSet { UserDefaults.standard.set(debugClaude, forKey: "debugClaude") }
    }
    @Published var debugAndroid: Bool {
        didSet { UserDefaults.standard.set(debugAndroid, forKey: "debugAndroid") }
    }
    @Published var debugXcode: Bool {
        didSet { UserDefaults.standard.set(debugXcode, forKey: "debugXcode") }
    }

    private init() {
        self.debugClaude = UserDefaults.standard.object(forKey: "debugClaude") as? Bool ?? false
        self.debugAndroid = UserDefaults.standard.object(forKey: "debugAndroid") as? Bool ?? true
        self.debugXcode = UserDefaults.standard.object(forKey: "debugXcode") as? Bool ?? true
    }
}

/// Tracking settings - which apps to monitor
final class TrackingSettings: ObservableObject {
    static let shared = TrackingSettings()

    @Published var trackClaude: Bool {
        didSet { UserDefaults.standard.set(trackClaude, forKey: "trackClaude") }
    }
    @Published var trackAndroidStudio: Bool {
        didSet { UserDefaults.standard.set(trackAndroidStudio, forKey: "trackAndroidStudio") }
    }
    @Published var trackXcode: Bool {
        didSet { UserDefaults.standard.set(trackXcode, forKey: "trackXcode") }
    }
    @Published var confettiEnabled: Bool {
        didSet { UserDefaults.standard.set(confettiEnabled, forKey: "confettiEnabled") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    private init() {
        self.trackClaude = UserDefaults.standard.object(forKey: "trackClaude") as? Bool ?? true
        self.trackAndroidStudio = UserDefaults.standard.object(forKey: "trackAndroidStudio") as? Bool ?? true
        self.trackXcode = UserDefaults.standard.object(forKey: "trackXcode") as? Bool ?? true
        self.confettiEnabled = UserDefaults.standard.object(forKey: "confettiEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }
}

/// Which process type to mock on launch
enum MockProcessType: String, CaseIterable {
    case none = "None"
    case claude = "Claude"
    case android = "Android"
    case xcode = "Xcode"
    case all = "All"

    var processType: ProcessType? {
        switch self {
        case .none: return nil
        case .claude: return .claude
        case .android: return .androidStudio
        case .xcode: return .xcode
        case .all: return nil // Handled specially
        }
    }

    var allProcessTypes: [ProcessType] {
        [.claude, .androidStudio, .xcode]
    }
}

/// Main app state that coordinates monitoring and UI
final class AppState: ObservableObject {
    @Published var isMonitoring: Bool = true

    #if DEBUG
    @Published var isMocking: Bool = false
    @Published var mockOnLaunchType: MockProcessType {
        didSet {
            UserDefaults.standard.set(mockOnLaunchType.rawValue, forKey: "mockOnLaunchType")
        }
    }
    #endif

    private let processMonitor = ProcessMonitor()
    private let windowController = NotchWindowController()
    private var cancellables = Set<AnyCancellable>()

    init() {
        #if DEBUG
        // Load settings
        let savedMockType = UserDefaults.standard.string(forKey: "mockOnLaunchType") ?? "None"
        self.mockOnLaunchType = MockProcessType(rawValue: savedMockType) ?? .none

        setupBindings()

        // Show mock on launch if a process type is selected
        if mockOnLaunchType != .none {
            runLaunchMock()
        } else {
            startMonitoring()
        }
        #else
        setupBindings()
        startMonitoring()
        #endif
    }

    private func setupBindings() {
        processMonitor.$activeProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                guard let self = self else { return }
                #if DEBUG
                guard !self.isMocking else { return }
                #endif
                self.windowController.update(with: processes)
            }
            .store(in: &cancellables)
    }

    #if DEBUG
    private func runLaunchMock() {
        // Handle "All" mock type specially
        if mockOnLaunchType == .all {
            runAllMock()
            return
        }

        guard let processType = mockOnLaunchType.processType else {
            startMonitoring()
            return
        }

        isMocking = true
        windowController.update(with: [processType])

        // Hide after 5 seconds and start monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.windowController.update(with: [])
            self?.isMocking = false
            self?.startMonitoring()
        }
    }

    private func runAllMock() {
        isMocking = true
        let allTypes = mockOnLaunchType.allProcessTypes

        // Start with all three processes
        windowController.update(with: allTypes)

        // Remove processes one by one with 1-second delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            // Remove first process (claude)
            self?.windowController.update(with: [.androidStudio, .xcode])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            // Remove second process (android)
            self?.windowController.update(with: [.xcode])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            // Remove last process (xcode)
            self?.windowController.update(with: [])
            self?.isMocking = false
            self?.startMonitoring()
        }
    }
    #endif

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
            startMonitoring()
        }
    }
}

/// Menu bar dropdown view
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var debugSettings = DebugSettings.shared
    @ObservedObject var trackingSettings = TrackingSettings.shared

    var body: some View {
        VStack {
            Toggle("Monitoring", isOn: Binding(
                get: { appState.isMonitoring },
                set: { _ in appState.toggleMonitoring() }
            ))

            Divider()

            Text("Track Apps").font(.caption).foregroundColor(.secondary)
            Toggle("Claude", isOn: $trackingSettings.trackClaude)
            Toggle("Android Studio", isOn: $trackingSettings.trackAndroidStudio)
            Toggle("Xcode", isOn: $trackingSettings.trackXcode)

            Divider()

            Toggle("Confetti", isOn: $trackingSettings.confettiEnabled)
            Toggle("Sound", isOn: $trackingSettings.soundEnabled)

            #if DEBUG
            Divider()

            Text("Mock on Launch").font(.caption).foregroundColor(.secondary)
            Picker("Mock Type", selection: $appState.mockOnLaunchType) {
                ForEach(MockProcessType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Text("Debug Logging").font(.caption).foregroundColor(.secondary)
            Toggle("Claude", isOn: $debugSettings.debugClaude)
            Toggle("Android Studio", isOn: $debugSettings.debugAndroid)
            Toggle("Xcode", isOn: $debugSettings.debugXcode)
            #endif

            Divider()

            Button("Send Feedback") {
                let subject = "Notchification Feedback"
                let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
                if let url = URL(string: "mailto:alexanderkvamme@gmail.com?subject=\(encodedSubject)") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
