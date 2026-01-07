//
//  NotchificationApp.swift
//  Notchification
//

import SwiftUI
import Combine
import Sparkle
import ApplicationServices  // For AXIsProcessTrusted()
import AVFoundation  // For camera permission

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
                .frame(width: 200)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
        MenuBarExtra("Debug", systemImage: "ladybug") {
            DebugMenuView(appState: appState)
                .frame(width: 200)
                .padding(8)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if DEBUG
struct DebugMenuView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var debugSettings = DebugSettings.shared
    @ObservedObject var licenseManager = LicenseManager.shared

    var body: some View {
        VStack(alignment: .leading) {
            Text("Mock on Launch").font(.caption).foregroundColor(.secondary)
            Picker("Mock Type", selection: $appState.mockOnLaunchType) {
                ForEach(MockProcessType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
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
            Toggle("Automator", isOn: $debugSettings.debugAutomator)
            Toggle("Downloads", isOn: $debugSettings.debugDownloads)
            Toggle("DaVinci Resolve", isOn: $debugSettings.debugDaVinciResolve)
            Toggle("Teams", isOn: $debugSettings.debugTeams)

            Divider()

            Text("License").font(.caption).foregroundColor(.secondary)
            Button("Reset Trial") { licenseManager.resetTrial() }
            Button("Expire Trial") { licenseManager.expireTrial() }

            Divider()

            Button("Run Demo") {
                if let processType = appState.mockOnLaunchType.processType {
                    appState.runQuickMock(process: processType)
                }
            }
            .disabled(appState.mockOnLaunchType == .none)
        }
    }
}
#endif

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
    @Published var debugAutomator: Bool {
        didSet { UserDefaults.standard.set(debugAutomator, forKey: "debugAutomator") }
    }
    @Published var debugDownloads: Bool {
        didSet { UserDefaults.standard.set(debugDownloads, forKey: "debugDownloads") }
    }
    @Published var debugDaVinciResolve: Bool {
        didSet { UserDefaults.standard.set(debugDaVinciResolve, forKey: "debugDaVinciResolve") }
    }
    @Published var debugTeams: Bool {
        didSet { UserDefaults.standard.set(debugTeams, forKey: "debugTeams") }
    }
    /// When true, scans all terminal sessions. When false (default), only scans frontmost session (faster).
    @Published var claudeScanAllSessions: Bool {
        didSet { UserDefaults.standard.set(claudeScanAllSessions, forKey: "claudeScanAllSessions") }
    }

    private init() {
        self.debugClaude = UserDefaults.standard.object(forKey: "debugClaude") as? Bool ?? false
        self.debugAndroid = UserDefaults.standard.object(forKey: "debugAndroid") as? Bool ?? true
        self.debugXcode = UserDefaults.standard.object(forKey: "debugXcode") as? Bool ?? true
        self.debugFinder = UserDefaults.standard.object(forKey: "debugFinder") as? Bool ?? true
        self.debugOpencode = UserDefaults.standard.object(forKey: "debugOpencode") as? Bool ?? false
        self.debugCodex = UserDefaults.standard.object(forKey: "debugCodex") as? Bool ?? false
        self.debugAutomator = UserDefaults.standard.object(forKey: "debugAutomator") as? Bool ?? false
        self.debugDownloads = UserDefaults.standard.object(forKey: "debugDownloads") as? Bool ?? false
        self.debugDaVinciResolve = UserDefaults.standard.object(forKey: "debugDaVinciResolve") as? Bool ?? false
        self.debugTeams = UserDefaults.standard.object(forKey: "debugTeams") as? Bool ?? false
        self.claudeScanAllSessions = UserDefaults.standard.object(forKey: "claudeScanAllSessions") as? Bool ?? false
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
    @Published var trackAutomator: Bool {
        didSet { UserDefaults.standard.set(trackAutomator, forKey: "trackAutomator") }
    }
    @Published var trackScriptEditor: Bool {
        didSet { UserDefaults.standard.set(trackScriptEditor, forKey: "trackScriptEditor") }
    }
    @Published var trackDownloads: Bool {
        didSet { UserDefaults.standard.set(trackDownloads, forKey: "trackDownloads") }
    }
    @Published var trackDaVinciResolve: Bool {
        didSet { UserDefaults.standard.set(trackDaVinciResolve, forKey: "trackDaVinciResolve") }
    }
    @Published var trackTeams: Bool {
        didSet { UserDefaults.standard.set(trackTeams, forKey: "trackTeams") }
    }
    @Published var confettiEnabled: Bool {
        didSet { UserDefaults.standard.set(confettiEnabled, forKey: "confettiEnabled") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    private init() {
        self.trackClaude = UserDefaults.standard.object(forKey: "trackClaude") as? Bool ?? false
        self.trackAndroidStudio = UserDefaults.standard.object(forKey: "trackAndroidStudio") as? Bool ?? false
        self.trackXcode = UserDefaults.standard.object(forKey: "trackXcode") as? Bool ?? false
        self.trackFinder = UserDefaults.standard.object(forKey: "trackFinder") as? Bool ?? false
        self.trackOpencode = UserDefaults.standard.object(forKey: "trackOpencode") as? Bool ?? false
        self.trackCodex = UserDefaults.standard.object(forKey: "trackCodex") as? Bool ?? false
        self.trackDropbox = UserDefaults.standard.object(forKey: "trackDropbox") as? Bool ?? false
        self.trackGoogleDrive = UserDefaults.standard.object(forKey: "trackGoogleDrive") as? Bool ?? false
        self.trackOneDrive = UserDefaults.standard.object(forKey: "trackOneDrive") as? Bool ?? false
        self.trackICloud = UserDefaults.standard.object(forKey: "trackICloud") as? Bool ?? false
        self.trackInstaller = UserDefaults.standard.object(forKey: "trackInstaller") as? Bool ?? false
        self.trackAppStore = UserDefaults.standard.object(forKey: "trackAppStore") as? Bool ?? false
        self.trackAutomator = UserDefaults.standard.object(forKey: "trackAutomator") as? Bool ?? false
        self.trackScriptEditor = UserDefaults.standard.object(forKey: "trackScriptEditor") as? Bool ?? false
        self.trackDownloads = UserDefaults.standard.object(forKey: "trackDownloads") as? Bool ?? false
        self.trackDaVinciResolve = UserDefaults.standard.object(forKey: "trackDaVinciResolve") as? Bool ?? false
        self.trackTeams = UserDefaults.standard.object(forKey: "trackTeams") as? Bool ?? false
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

/// Notch display style
enum NotchStyle: String, CaseIterable {
    case normal = "normal"      // Full size with icons and progress bars
    case medium = "medium"      // Notch-width with smaller icons and bars
    case minimal = "minimal"    // Just a colored stroke around the notch

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .medium: return "Medium"
        case .minimal: return "Minimal"
        }
    }
}

/// Which screen(s) to show the notch indicator on
enum ScreenMode: String, CaseIterable {
    case builtIn = "builtin"    // MacBook display only
    case external = "external"  // External display only
    case both = "both"          // Both displays

    var displayName: String {
        switch self {
        case .builtIn: return "MacBook"
        case .external: return "External"
        case .both: return "Both"
        }
    }
}

/// Visual style settings for the notch indicator
final class StyleSettings: ObservableObject {
    static let shared = StyleSettings()

    /// The display style for the notch indicator
    @Published var notchStyle: NotchStyle {
        didSet { UserDefaults.standard.set(notchStyle.rawValue, forKey: "notchStyle") }
    }

    /// Convenience property for backward compatibility
    var minimalStyle: Bool {
        notchStyle == .minimal
    }

    /// Which screen(s) to show the indicator on
    @Published var screenMode: ScreenMode {
        didSet {
            UserDefaults.standard.set(screenMode.rawValue, forKey: "screenMode")
            NotificationCenter.default.post(name: .screenSelectionChanged, object: nil)
        }
    }

    /// Trim extra top padding on displays without a notch
    @Published var trimTopOnExternalDisplay: Bool {
        didSet { UserDefaults.standard.set(trimTopOnExternalDisplay, forKey: "trimTopOnExternalDisplay") }
    }

    /// Trim extra top padding on displays with a notch
    @Published var trimTopOnNotchDisplay: Bool {
        didSet { UserDefaults.standard.set(trimTopOnNotchDisplay, forKey: "trimTopOnNotchDisplay") }
    }

    /// Horizontal offset for positioning (useful for external displays)
    @Published var horizontalOffset: CGFloat {
        didSet { UserDefaults.standard.set(horizontalOffset, forKey: "horizontalOffset") }
    }

    private init() {
        // Migrate from old minimalStyle boolean if needed
        if let styleString = UserDefaults.standard.string(forKey: "notchStyle"),
           let style = NotchStyle(rawValue: styleString) {
            self.notchStyle = style
        } else if let oldMinimal = UserDefaults.standard.object(forKey: "minimalStyle") as? Bool {
            self.notchStyle = oldMinimal ? .minimal : .normal
        } else {
            self.notchStyle = .normal
        }
        if let modeString = UserDefaults.standard.string(forKey: "screenMode"),
           let mode = ScreenMode(rawValue: modeString) {
            self.screenMode = mode
        } else {
            self.screenMode = .builtIn
        }
        self.trimTopOnExternalDisplay = UserDefaults.standard.object(forKey: "trimTopOnExternalDisplay") as? Bool ?? true
        self.trimTopOnNotchDisplay = UserDefaults.standard.object(forKey: "trimTopOnNotchDisplay") as? Bool ?? false
        self.horizontalOffset = UserDefaults.standard.object(forKey: "horizontalOffset") as? CGFloat ?? 0
    }

    /// Get the built-in (MacBook) display
    var builtInScreen: NSScreen? {
        NSScreen.screens.first { screen in
            // Built-in displays have localizedName containing "Built-in" or are the only screen
            screen.localizedName.contains("Built-in") || screen.localizedName.contains("Retina")
        } ?? NSScreen.screens.first
    }

    /// Get the first external display
    var externalScreen: NSScreen? {
        NSScreen.screens.first { screen in
            !screen.localizedName.contains("Built-in") && !screen.localizedName.contains("Retina")
        }
    }

    /// Get all screens to show the indicator on based on current mode
    var screensToShow: [NSScreen] {
        switch screenMode {
        case .builtIn:
            if let screen = builtInScreen {
                return [screen]
            }
            return NSScreen.screens.isEmpty ? [] : [NSScreen.screens[0]]
        case .external:
            if let screen = externalScreen {
                return [screen]
            }
            return []  // No external display connected
        case .both:
            return NSScreen.screens
        }
    }

    /// For backward compatibility - returns first screen to show
    var selectedScreen: NSScreen? {
        screensToShow.first
    }
}

extension Notification.Name {
    static let screenSelectionChanged = Notification.Name("screenSelectionChanged")
    static let showPositionPreview = Notification.Name("showPositionPreview")
    static let showSettingsPreview = Notification.Name("showSettingsPreview")
    static let hideSettingsPreview = Notification.Name("hideSettingsPreview")
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
    case teams = "Teams"
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
        case .teams: return .teams
        case .claudeAndFinder: return nil // Handled specially
        case .threeProcesses: return nil // Handled specially
        case .all: return nil // Handled specially
        }
    }

    var allProcessTypes: [ProcessType] {
        [.claude, .androidStudio, .xcode, .finder, .opencode, .codex, .dropbox, .googleDrive, .oneDrive, .icloud, .installer, .appStore, .teams]
    }
}

/// Checks and prints permission status on launch (DEBUG only)
/// NEVER REMOVE THIS - Essential for diagnosing detection issues
enum PermissionsChecker {
    /// Check all required permissions and print status
    /// Called on app launch in DEBUG builds - runs on background queue to avoid blocking main thread
    static func checkAndPrintPermissions() {
        DispatchQueue.global(qos: .utility).async {
            // Small delay to let app finish launching
            Thread.sleep(forTimeInterval: 0.5)

            print("""

            ╔═══════════════════════════════════════════════════════════════╗
            ║                    PERMISSIONS CHECK                          ║
            ╚═══════════════════════════════════════════════════════════════╝
            """)

            // 1. Check Accessibility permission (must be on main thread)
            var accessibilityEnabled = false
            DispatchQueue.main.sync {
                accessibilityEnabled = AXIsProcessTrusted()
            }

            if accessibilityEnabled {
                print("✅ Accessibility: ENABLED")
            } else {
                print("❌ Accessibility: DISABLED")
                print("   → Go to: System Settings > Privacy & Security > Accessibility")
                print("   → Add and enable Notchification")
            }

            // 2. Check Automation permissions for terminal apps
            print("")
            checkAutomationPermission(for: "iTerm", bundleId: "com.googlecode.iterm2")
            checkAutomationPermission(for: "Terminal", bundleId: "com.apple.Terminal")

            print("""

            ═══════════════════════════════════════════════════════════════
            """)
        }
    }

    /// Check if we have automation permission for a specific app
    private static func checkAutomationPermission(for appName: String, bundleId: String) {
        // Try to run a simple AppleScript to check if we have permission
        let script = """
        tell application "\(appName)"
            if running then
                return "RUNNING"
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if output == "RUNNING" {
                    print("✅ Automation (\(appName)): ENABLED - app is running")
                } else {
                    print("✅ Automation (\(appName)): ENABLED - app not running")
                }
            } else if errorOutput.contains("not allowed") || errorOutput.contains("1743") {
                // Error -1743 is "AppleEvent timed out" which often means permission denied
                print("❌ Automation (\(appName)): DISABLED")
                print("   → Go to: System Settings > Privacy & Security > Automation")
                print("   → Enable Notchification → \(appName)")
            } else if errorOutput.contains("Application isn't running") {
                print("⚠️  Automation (\(appName)): Unknown - app not installed or can't check")
            } else {
                print("⚠️  Automation (\(appName)): Unknown (exit code \(task.terminationStatus))")
                if !errorOutput.isEmpty {
                    print("   Error: \(errorOutput.prefix(100))")
                }
            }
        } catch {
            print("⚠️  Automation (\(appName)): Could not check - \(error.localizedDescription)")
        }
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

    private let processMonitor = ProcessMonitor.shared
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

        // DEBUG: Check permissions on launch (NEVER REMOVE THIS)
        PermissionsChecker.checkAndPrintPermissions()

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

    private var previewTimer: Timer?

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

        // Listen for position preview requests from settings
        NotificationCenter.default.addObserver(
            forName: .showPositionPreview,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showPositionPreview()
        }

        // Listen for settings tab appearing/disappearing
        NotificationCenter.default.addObserver(
            forName: .showSettingsPreview,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSettingsPreviewPersistent()
        }

        NotificationCenter.default.addObserver(
            forName: .hideSettingsPreview,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideSettingsPreview()
        }
    }

    private var isShowingSettingsPreview = false

    /// Show a temporary preview when adjusting position in settings
    private func showPositionPreview() {
        // If settings preview is active, it's already showing - just reset the timer
        if isShowingSettingsPreview {
            return
        }

        // Cancel any existing timer
        previewTimer?.invalidate()

        // Show a mock process
        windowController.update(with: [.claude])

        // Hide after 1.5 seconds of no changes
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            // Only hide if there are no real active processes
            if self?.processMonitor.activeProcesses.isEmpty == true {
                self?.windowController.update(with: [])
            } else {
                self?.windowController.update(with: self?.processMonitor.activeProcesses ?? [])
            }
        }
    }

    /// Show preview while Display settings tab is open
    private func showSettingsPreviewPersistent() {
        isShowingSettingsPreview = true
        previewTimer?.invalidate()
        windowController.update(with: [.claude])
    }

    /// Hide preview when Display settings tab closes
    private func hideSettingsPreview() {
        isShowingSettingsPreview = false
        // Restore real active processes or hide
        if processMonitor.activeProcesses.isEmpty {
            windowController.update(with: [])
        } else {
            windowController.update(with: processMonitor.activeProcesses)
        }
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

        // For Teams, start the camera (view shows immediately with black bg)
        if processType == .teams {
            CameraManager.shared.startSession()
        }

        showLaunchMock(processType: processType)
    }

    private func showLaunchMock(processType: ProcessType) {
        windowController.update(with: [processType])

        // Teams is dismissed via hover interaction, not timeout
        if processType == .teams {
            // Start monitoring in background so other detectors work
            startMonitoring()
            return
        }

        // Hide after 5 seconds (non-Teams)
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

    /// Run a quick mock for a specific process (triggered by command-click)
    /// Currently mocked processes (for stacking demos)
    private var mockProcesses: [ProcessType] = []

    func runQuickMock(process: ProcessType = .finder) {
        // For Teams, start camera and show immediately (black bg until frames arrive)
        if process == .teams {
            CameraManager.shared.startSession()
        }

        showMockProcess(process)
    }

    private func showMockProcess(_ process: ProcessType) {
        // Add to mock processes (avoid duplicates)
        if !mockProcesses.contains(process) {
            mockProcesses.append(process)
        }

        windowController.update(with: mockProcesses)

        #if DEBUG
        isMocking = true
        #endif

        // Teams is dismissed via hover interaction, not timeout
        if process == .teams {
            return
        }

        // Remove this specific process after 5 seconds (non-Teams)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.mockProcesses.removeAll { $0 == process }
            self?.windowController.update(with: self?.mockProcesses ?? [])

            #if DEBUG
            if self?.mockProcesses.isEmpty == true {
                self?.isMocking = false
            }
            #endif
        }
    }
}

/// Triggers macOS camera permission prompt by actually accessing the camera
private func triggerCameraPermissionPrompt() {
    // Create and start a capture session - this forces the permission prompt
    let session = AVCaptureSession()

    DispatchQueue.global(qos: .userInitiated).async {
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            print("No camera found")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()

            // Actually start the session briefly to trigger permission
            session.startRunning()

            // Stop after a moment
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                session.stopRunning()
            }
        } catch {
            print("Camera access error: \(error)")
            // If we get here with authorization error, open Settings
            DispatchQueue.main.async {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

/// Toggle that supports ⌘-click to demo the feature
struct DemoableToggle: View {
    let label: String
    @Binding var isOn: Bool
    let processType: ProcessType
    let appState: AppState
    var onChange: ((Bool) -> Void)?

    var body: some View {
        HStack {
            Button(action: {
                if NSEvent.modifierFlags.contains(.command) {
                    appState.runQuickMock(process: processType)
                } else {
                    isOn.toggle()
                }
            }) {
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn) { _, newValue in
                    onChange?(newValue)
                }
        }
        .padding(.trailing, 8)
    }
}

/// Menu bar dropdown view
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    let updater: SPUUpdater
    @ObservedObject var trackingSettings = TrackingSettings.shared
    @ObservedObject var licenseManager = LicenseManager.shared

    var body: some View {
        VStack(alignment: .leading) {
            // License status
            licenseStatusView

            Divider()

            Toggle("Enabled", isOn: Binding(
                get: { appState.isMonitoring },
                set: { _ in appState.toggleMonitoring() }
            ))
            .toggleStyle(.switch)
            .padding(.trailing, 8)

            Divider()

            Group {
                HStack {
                    Text("Track Apps").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘-click to demo").font(.caption2).foregroundColor(.secondary.opacity(0.6))
                }
                DemoableToggle(label: "Claude", isOn: $trackingSettings.trackClaude, processType: .claude, appState: appState)
                DemoableToggle(label: "Android Studio", isOn: $trackingSettings.trackAndroidStudio, processType: .androidStudio, appState: appState)
                DemoableToggle(label: "Xcode", isOn: $trackingSettings.trackXcode, processType: .xcode, appState: appState)
                DemoableToggle(label: "Finder", isOn: $trackingSettings.trackFinder, processType: .finder, appState: appState)
                DemoableToggle(label: "Opencode", isOn: $trackingSettings.trackOpencode, processType: .opencode, appState: appState)
                DemoableToggle(label: "Codex", isOn: $trackingSettings.trackCodex, processType: .codex, appState: appState)
                DemoableToggle(label: "Dropbox", isOn: $trackingSettings.trackDropbox, processType: .dropbox, appState: appState)
                DemoableToggle(label: "Google Drive", isOn: $trackingSettings.trackGoogleDrive, processType: .googleDrive, appState: appState)
                DemoableToggle(label: "OneDrive", isOn: $trackingSettings.trackOneDrive, processType: .oneDrive, appState: appState)
                DemoableToggle(label: "iCloud", isOn: $trackingSettings.trackICloud, processType: .icloud, appState: appState)
            }
            .disabled(!appState.isMonitoring)

            Group {
                DemoableToggle(label: "Installer", isOn: $trackingSettings.trackInstaller, processType: .installer, appState: appState)
                DemoableToggle(label: "App Store", isOn: $trackingSettings.trackAppStore, processType: .appStore, appState: appState)
                DemoableToggle(label: "Automator", isOn: $trackingSettings.trackAutomator, processType: .automator, appState: appState)
                DemoableToggle(label: "Script Editor", isOn: $trackingSettings.trackScriptEditor, processType: .scriptEditor, appState: appState)
                DemoableToggle(label: "Downloads", isOn: $trackingSettings.trackDownloads, processType: .downloads, appState: appState)
                DemoableToggle(label: "DaVinci Resolve", isOn: $trackingSettings.trackDaVinciResolve, processType: .davinciResolve, appState: appState)

                Divider()

                Toggle("Confetti", isOn: $trackingSettings.confettiEnabled)
                    .padding(.trailing, 8)
                Toggle("Sound", isOn: $trackingSettings.soundEnabled)
                    .padding(.trailing, 8)
            }
            .disabled(!appState.isMonitoring)

            Divider()

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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 16)
        .padding(.vertical, 12)
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
