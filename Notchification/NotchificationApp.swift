//
//  NotchificationApp.swift
//  Notchification
//

import SwiftUI
import Combine
import Sparkle

/// Sparkle delegate that gates updates to licensed users only
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) -> Bool {
        // Only allow updates for licensed users
        return LicenseManager.shared.state == .licensed
    }
}

/// App delegate to handle single-instance enforcement
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for other running instances after launch
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        let otherInstances = runningApps.filter { $0 != NSRunningApplication.current }

        if !otherInstances.isEmpty {
            // Another instance is running - activate it and quit this one
            otherInstances.first?.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
        }
    }
}

@main
struct NotchificationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    private let updaterDelegate = UpdaterDelegate()
    private var updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
    }

    var body: some Scene {
        MenuBarExtra("Notchification", systemImage: "bell.badge") {
            MenuBarView(appState: appState, updater: updaterController.updater)
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
    @Published var debugFinder: Bool {
        didSet { UserDefaults.standard.set(debugFinder, forKey: "debugFinder") }
    }
    @Published var debugOpencode: Bool {
        didSet { UserDefaults.standard.set(debugOpencode, forKey: "debugOpencode") }
    }
    @Published var debugCodex: Bool {
        didSet { UserDefaults.standard.set(debugCodex, forKey: "debugCodex") }
    }

    private init() {
        self.debugClaude = UserDefaults.standard.object(forKey: "debugClaude") as? Bool ?? false
        self.debugAndroid = UserDefaults.standard.object(forKey: "debugAndroid") as? Bool ?? true
        self.debugXcode = UserDefaults.standard.object(forKey: "debugXcode") as? Bool ?? true
        self.debugFinder = UserDefaults.standard.object(forKey: "debugFinder") as? Bool ?? true
        self.debugOpencode = UserDefaults.standard.object(forKey: "debugOpencode") as? Bool ?? false
        self.debugCodex = UserDefaults.standard.object(forKey: "debugCodex") as? Bool ?? false
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
    @Published var trackFinder: Bool {
        didSet { UserDefaults.standard.set(trackFinder, forKey: "trackFinder") }
    }
    @Published var trackOpencode: Bool {
        didSet { UserDefaults.standard.set(trackOpencode, forKey: "trackOpencode") }
    }
    @Published var trackCodex: Bool {
        didSet { UserDefaults.standard.set(trackCodex, forKey: "trackCodex") }
    }
    @Published var trackDropbox: Bool {
        didSet { UserDefaults.standard.set(trackDropbox, forKey: "trackDropbox") }
    }
    @Published var trackGoogleDrive: Bool {
        didSet { UserDefaults.standard.set(trackGoogleDrive, forKey: "trackGoogleDrive") }
    }
    @Published var trackOneDrive: Bool {
        didSet { UserDefaults.standard.set(trackOneDrive, forKey: "trackOneDrive") }
    }
    @Published var trackICloud: Bool {
        didSet { UserDefaults.standard.set(trackICloud, forKey: "trackICloud") }
    }
    @Published var trackInstaller: Bool {
        didSet { UserDefaults.standard.set(trackInstaller, forKey: "trackInstaller") }
    }
    @Published var trackAppStore: Bool {
        didSet { UserDefaults.standard.set(trackAppStore, forKey: "trackAppStore") }
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
        self.trackFinder = UserDefaults.standard.object(forKey: "trackFinder") as? Bool ?? true
        self.trackOpencode = UserDefaults.standard.object(forKey: "trackOpencode") as? Bool ?? true
        self.trackCodex = UserDefaults.standard.object(forKey: "trackCodex") as? Bool ?? true
        self.trackDropbox = UserDefaults.standard.object(forKey: "trackDropbox") as? Bool ?? true
        self.trackGoogleDrive = UserDefaults.standard.object(forKey: "trackGoogleDrive") as? Bool ?? true
        self.trackOneDrive = UserDefaults.standard.object(forKey: "trackOneDrive") as? Bool ?? true
        self.trackICloud = UserDefaults.standard.object(forKey: "trackICloud") as? Bool ?? true
        self.trackInstaller = UserDefaults.standard.object(forKey: "trackInstaller") as? Bool ?? true
        self.trackAppStore = UserDefaults.standard.object(forKey: "trackAppStore") as? Bool ?? true
        self.confettiEnabled = UserDefaults.standard.object(forKey: "confettiEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }
}

/// CPU threshold settings - customizable per detector
final class ThresholdSettings: ObservableObject {
    static let shared = ThresholdSettings()

    // Claude thresholds (default: LOW 0-10, MED 10-20, HIGH 20+)
    @Published var claudeLowThreshold: Double {
        didSet { UserDefaults.standard.set(claudeLowThreshold, forKey: "claudeLowThreshold") }
    }
    @Published var claudeHighThreshold: Double {
        didSet { UserDefaults.standard.set(claudeHighThreshold, forKey: "claudeHighThreshold") }
    }

    // Opencode thresholds (default: LOW 0-1, MED 1-3, HIGH 3+)
    @Published var opencodeLowThreshold: Double {
        didSet { UserDefaults.standard.set(opencodeLowThreshold, forKey: "opencodeLowThreshold") }
    }
    @Published var opencodeHighThreshold: Double {
        didSet { UserDefaults.standard.set(opencodeHighThreshold, forKey: "opencodeHighThreshold") }
    }

    // Xcode threshold (default: 5%)
    @Published var xcodeThreshold: Double {
        didSet { UserDefaults.standard.set(xcodeThreshold, forKey: "xcodeThreshold") }
    }

    // Default values
    static let defaultClaudeLow: Double = 10.0
    static let defaultClaudeHigh: Double = 20.0
    static let defaultOpencodeLow: Double = 0.5
    static let defaultOpencodeHigh: Double = 2.0
    static let defaultXcode: Double = 5.0

    private init() {
        self.claudeLowThreshold = UserDefaults.standard.object(forKey: "claudeLowThreshold") as? Double ?? Self.defaultClaudeLow
        self.claudeHighThreshold = UserDefaults.standard.object(forKey: "claudeHighThreshold") as? Double ?? Self.defaultClaudeHigh
        self.opencodeLowThreshold = UserDefaults.standard.object(forKey: "opencodeLowThreshold") as? Double ?? Self.defaultOpencodeLow
        self.opencodeHighThreshold = UserDefaults.standard.object(forKey: "opencodeHighThreshold") as? Double ?? Self.defaultOpencodeHigh
        self.xcodeThreshold = UserDefaults.standard.object(forKey: "xcodeThreshold") as? Double ?? Self.defaultXcode
    }

    func resetToDefaults() {
        claudeLowThreshold = Self.defaultClaudeLow
        claudeHighThreshold = Self.defaultClaudeHigh
        opencodeLowThreshold = Self.defaultOpencodeLow
        opencodeHighThreshold = Self.defaultOpencodeHigh
        xcodeThreshold = Self.defaultXcode
    }
}

/// Visual style settings for the notch indicator
final class StyleSettings: ObservableObject {
    static let shared = StyleSettings()

    /// When true, shows only a 2px colored border around the notch (no icons/progress bars)
    @Published var minimalStyle: Bool {
        didSet { UserDefaults.standard.set(minimalStyle, forKey: "minimalStyle") }
    }

    private init() {
        self.minimalStyle = UserDefaults.standard.object(forKey: "minimalStyle") as? Bool ?? false
    }
}

/// Information about the physical notch on the current screen
/// Uses NSScreen APIs available on macOS 12+ to get exact dimensions
struct NotchInfo {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    /// Default fallback dimensions for Macs without a notch
    static let defaultWidth: CGFloat = 200
    static let defaultHeight: CGFloat = 32

    /// Get notch info for the given screen (or main screen if nil)
    static func forScreen(_ screen: NSScreen? = nil) -> NotchInfo {
        let targetScreen = screen ?? NSScreen.main

        guard let screen = targetScreen else {
            return NotchInfo(width: defaultWidth, height: defaultHeight, hasNotch: false)
        }

        // Check for notch using safeAreaInsets (available macOS 12+)
        if #available(macOS 12.0, *) {
            let safeArea = screen.safeAreaInsets

            // If there's a top safe area inset, there's a notch
            guard safeArea.top > 0 else {
                return NotchInfo(width: defaultWidth, height: defaultHeight, hasNotch: false)
            }

            // Calculate notch width from auxiliary areas
            // auxiliaryTopLeftArea and auxiliaryTopRightArea define the unobscured
            // regions on either side of the notch
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea {
                // Notch width is the gap between the two auxiliary areas
                let notchWidth = rightArea.minX - leftArea.maxX
                let notchHeight = safeArea.top

                print("📐 Notch dimensions: width=\(notchWidth), height=\(notchHeight)")
                print("📐 Left area: \(leftArea), Right area: \(rightArea)")
                print("📐 Safe area top: \(safeArea.top)")

                return NotchInfo(
                    width: notchWidth,
                    height: notchHeight,
                    hasNotch: true
                )
            }

            // Fallback: use safe area height with default width
            return NotchInfo(
                width: defaultWidth,
                height: safeArea.top,
                hasNotch: true
            )
        }

        // macOS 11 or earlier - no notch
        return NotchInfo(width: defaultWidth, height: defaultHeight, hasNotch: false)
    }
}

/// Which process type to mock on launch
enum MockProcessType: String, CaseIterable {
    case none = "None"
    case claude = "Claude"
    case android = "Android"
    case xcode = "Xcode"
    case finder = "Finder"
    case opencode = "Opencode"
    case codex = "Codex"
    case dropbox = "Dropbox"
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"
    case icloud = "iCloud"
    case installer = "Installer"
    case appStore = "App Store"
    case claudeAndFinder = "Claude + Finder"
    case threeProcesses = "Claude + Finder + Android"
    case all = "All"

    var processType: ProcessType? {
        switch self {
        case .none: return nil
        case .claude: return .claude
        case .android: return .androidStudio
        case .xcode: return .xcode
        case .finder: return .finder
        case .opencode: return .opencode
        case .codex: return .codex
        case .dropbox: return .dropbox
        case .googleDrive: return .googleDrive
        case .oneDrive: return .oneDrive
        case .icloud: return .icloud
        case .installer: return .installer
        case .appStore: return .appStore
        case .claudeAndFinder: return nil // Handled specially
        case .threeProcesses: return nil // Handled specially
        case .all: return nil // Handled specially
        }
    }

    var allProcessTypes: [ProcessType] {
        [.claude, .androidStudio, .xcode, .finder, .opencode, .codex, .dropbox, .googleDrive, .oneDrive, .icloud, .installer, .appStore]
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
    @Published var mockRepeat: Bool {
        didSet {
            UserDefaults.standard.set(mockRepeat, forKey: "mockRepeat")
        }
    }
    #endif

    private let processMonitor = ProcessMonitor()
    private let windowController = NotchWindowController()
    private let licenseManager = LicenseManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        #if DEBUG
        // IMPORTANT: Debug logs use os.Logger, not print()!
        // To see debug output, open Console.app or run:
        //   log stream --predicate 'subsystem == "com.hoi.Notchification"' --level debug
        print("""

        ╔═══════════════════════════════════════════════════════════════════════════════╗
        ║  IMPORTANT: Debug logs are in Console.app, NOT Xcode console!                ║
        ║                                                                               ║
        ║  Run this in Terminal to see live debug logs:                                 ║
        ║                                                                               ║
        ║  log stream --predicate 'subsystem == "com.hoi.Notchification"' --level debug ║
        ╚═══════════════════════════════════════════════════════════════════════════════╝

        """)

        // Load settings
        let savedMockType = UserDefaults.standard.string(forKey: "mockOnLaunchType") ?? "None"
        self.mockOnLaunchType = MockProcessType(rawValue: savedMockType) ?? .none
        self.mockRepeat = UserDefaults.standard.object(forKey: "mockRepeat") as? Bool ?? false

        setupBindings()

        // Show mock on launch if a process type is selected
        if mockOnLaunchType != .none {
            runLaunchMock()
        } else {
            startMonitoringIfLicensed()
        }
        #else
        setupBindings()
        startMonitoringIfLicensed()
        #endif
    }

    private func startMonitoringIfLicensed() {
        // Always start monitoring - we show a nag message if expired
        startMonitoring()
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

        // Handle "Claude + Finder" mock type
        if mockOnLaunchType == .claudeAndFinder {
            runClaudeAndFinderMock()
            return
        }

        // Handle "Three Processes" mock type
        if mockOnLaunchType == .threeProcesses {
            runThreeProcessesMock()
            return
        }

        guard let processType = mockOnLaunchType.processType else {
            startMonitoring()
            return
        }

        isMocking = true
        windowController.update(with: [processType])

        // Hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.windowController.update(with: [])

            // If repeat is enabled, restart after a brief pause
            if self?.mockRepeat == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.runLaunchMock()
                }
            } else {
                self?.isMocking = false
                self?.startMonitoring()
            }
        }
    }

    private func runClaudeAndFinderMock() {
        isMocking = true
        windowController.update(with: [.claude, .finder])

        // Keep showing for 10 seconds then hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.windowController.update(with: [])

            // If repeat is enabled, restart after a brief pause
            if self?.mockRepeat == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.runClaudeAndFinderMock()
                }
            } else {
                self?.isMocking = false
                self?.startMonitoring()
            }
        }
    }

    private func runThreeProcessesMock() {
        isMocking = true
        windowController.update(with: [.claude, .finder, .androidStudio])

        // Keep showing for 15 seconds then hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.windowController.update(with: [])

            // If repeat is enabled, restart after a brief pause
            if self?.mockRepeat == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.runThreeProcessesMock()
                }
            } else {
                self?.isMocking = false
                self?.startMonitoring()
            }
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

            // If repeat is enabled, restart after a brief pause
            if self?.mockRepeat == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.runAllMock()
                }
            } else {
                self?.isMocking = false
                self?.startMonitoring()
            }
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
    let updater: SPUUpdater
    @ObservedObject var debugSettings = DebugSettings.shared
    @ObservedObject var trackingSettings = TrackingSettings.shared
    @ObservedObject var licenseManager = LicenseManager.shared

    var body: some View {
        VStack {
            // License status
            licenseStatusView

            Divider()

            Toggle("Monitoring", isOn: Binding(
                get: { appState.isMonitoring },
                set: { _ in appState.toggleMonitoring() }
            ))

            Divider()

            Text("Track Apps").font(.caption).foregroundColor(.secondary)
            Toggle("Claude", isOn: $trackingSettings.trackClaude)
            Toggle("Android Studio", isOn: $trackingSettings.trackAndroidStudio)
            Toggle("Xcode", isOn: $trackingSettings.trackXcode)
            Toggle("Finder", isOn: $trackingSettings.trackFinder)
            Toggle("Opencode", isOn: $trackingSettings.trackOpencode)
            Toggle("Codex", isOn: $trackingSettings.trackCodex)
            Toggle("Dropbox", isOn: $trackingSettings.trackDropbox)
            Toggle("Google Drive", isOn: $trackingSettings.trackGoogleDrive)
            Toggle("OneDrive", isOn: $trackingSettings.trackOneDrive)
            Toggle("iCloud", isOn: $trackingSettings.trackICloud)
            Toggle("Installer", isOn: $trackingSettings.trackInstaller)
            Toggle("App Store", isOn: $trackingSettings.trackAppStore)

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
            Toggle("Repeat", isOn: $appState.mockRepeat)

            Divider()

            Text("Debug Logging").font(.caption).foregroundColor(.secondary)
            Toggle("Claude", isOn: $debugSettings.debugClaude)
            Toggle("Android Studio", isOn: $debugSettings.debugAndroid)
            Toggle("Xcode", isOn: $debugSettings.debugXcode)
            Toggle("Finder", isOn: $debugSettings.debugFinder)
            Toggle("Opencode", isOn: $debugSettings.debugOpencode)
            Toggle("Codex", isOn: $debugSettings.debugCodex)

            Divider()

            Text("License Debug").font(.caption).foregroundColor(.secondary)
            Button("Reset Trial") {
                licenseManager.resetTrial()
            }
            Button("Expire Trial") {
                licenseManager.expireTrial()
            }
            #endif

            Divider()

            Button("License...") {
                LicenseWindowController.shared.showLicenseWindow()
            }

            Button("Settings...") {
                SettingsWindowController.shared.showSettings()
            }

            Button("Send Feedback") {
                let subject = "Notchification Feedback"
                let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
                if let url = URL(string: "mailto:alexanderkvamme@gmail.com?subject=\(encodedSubject)") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Check for Updates...") {
                updater.checkForUpdates()
            }

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var licenseStatusView: some View {
        switch licenseManager.state {
        case .licensed:
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("Licensed")
                    .font(.caption)
            }

        case .trial(let daysRemaining):
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                Text("Trial: \(daysRemaining) days left")
                    .font(.caption)
            }

        case .expired:
            Label("Trial expired", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}
