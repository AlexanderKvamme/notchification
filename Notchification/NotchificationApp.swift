//
//  NotchificationApp.swift
//  Notchification
//

import SwiftUI
import Combine
import Sparkle
import ApplicationServices  // For AXIsProcessTrusted()
import AVFoundation  // For camera permission
import EventKit  // For calendar permission

/// Sparkle delegate that gates updates to licensed users only
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) -> Bool {
        // Only allow updates for licensed users
        return LicenseManager.shared.state == .licensed
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            AppState.shared.updateAvailable = true
        }
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
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @ObservedObject private var appState = AppState.shared
    private let updaterDelegate = UpdaterDelegate()
    private var updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
    }

    var body: some Scene {
        MenuBarExtra("Notchification", image: "MenuBarIcon") {
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
                .onAppear {
                    // Option-click on ladybug triggers calendar
                    if NSEvent.modifierFlags.contains(.option) {
                        DebugSettings.shared.showMorningOverview = true
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.close()
                        }
                    }
                }
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
                .toggleStyle(.switch)
                .padding(.trailing, 8)

            Divider()

            Text("Debug Logging").font(.caption).foregroundColor(.secondary)
            Toggle("Claude Code", isOn: $debugSettings.debugClaudeCode)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Claude App", isOn: $debugSettings.debugClaudeApp)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Android Studio", isOn: $debugSettings.debugAndroid)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Xcode", isOn: $debugSettings.debugXcode)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Finder", isOn: $debugSettings.debugFinder)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Opencode", isOn: $debugSettings.debugOpencode)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Codex", isOn: $debugSettings.debugCodex)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Automator", isOn: $debugSettings.debugAutomator)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Downloads", isOn: $debugSettings.debugDownloads)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("DaVinci Resolve", isOn: $debugSettings.debugDaVinciResolve)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Teams", isOn: $debugSettings.debugTeams)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Calendar", isOn: $debugSettings.debugCalendar)
                .toggleStyle(.switch)
                .padding(.trailing, 8)

            Divider()

            Text("View Debug").font(.caption).foregroundColor(.secondary)
            Toggle("Show View Colors", isOn: $debugSettings.debugViewColors)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Toggle("Show Morning Overview", isOn: $debugSettings.showMorningOverview)
                .toggleStyle(.switch)
                .padding(.trailing, 8)

            Divider()

            Text("Welcome Message").font(.caption).foregroundColor(.secondary)
            Toggle("Show Every Launch", isOn: $debugSettings.alwaysShowWelcomeMessage)
                .toggleStyle(.switch)
                .padding(.trailing, 8)
            Button("Show Now") {
                WelcomeMessageWindowController.shared.show()
            }

            Divider()

            Text("Calendar").font(.caption).foregroundColor(.secondary)
            Button("Show Calendar Onboarding") {
                CalendarOnboardingWindowController.shared.resetOnboarding()
                CalendarOnboardingWindowController.shared.showOnboarding()
            }
            Button("Reset Morning Shown Today") {
                CalendarSettings.shared.resetMorningOverviewShown()
            }

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

    @Published var debugClaudeCode: Bool {
        didSet { UserDefaults.standard.set(debugClaudeCode, forKey: "debugClaudeCode") }
    }
    @Published var debugClaudeApp: Bool {
        didSet { UserDefaults.standard.set(debugClaudeApp, forKey: "debugClaudeApp") }
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
    @Published var debugCalendar: Bool {
        didSet { UserDefaults.standard.set(debugCalendar, forKey: "debugCalendar") }
    }
    /// When true, shows the morning overview calendar view for testing
    @Published var showMorningOverview: Bool {
        didSet { UserDefaults.standard.set(showMorningOverview, forKey: "showMorningOverview") }
    }
    /// When true, uses mock calendar data instead of real events (for Mock Type picker)
    @Published var useMockCalendarData: Bool = false
    /// When true, scans all terminal sessions. When false (default), only scans frontmost session (faster).
    @Published var claudeScanAllSessions: Bool {
        didSet { UserDefaults.standard.set(claudeScanAllSessions, forKey: "claudeScanAllSessions") }
    }
    /// Show debug colors on views (red=fill, blue=stroke, green=frame)
    @Published var debugViewColors: Bool {
        didSet { UserDefaults.standard.set(debugViewColors, forKey: "debugViewColors") }
    }
    /// When true, shows the welcome message on every launch (for design testing)
    @Published var alwaysShowWelcomeMessage: Bool {
        didSet { UserDefaults.standard.set(alwaysShowWelcomeMessage, forKey: "alwaysShowWelcomeMessage") }
    }
    /// When true, shows the welcome message in the notch (set by WelcomeMessageWindowController)
    @Published var showWelcomeMessage: Bool {
        didSet { UserDefaults.standard.set(showWelcomeMessage, forKey: "showWelcomeMessage") }
    }

    private init() {
        self.debugClaudeCode = UserDefaults.standard.object(forKey: "debugClaudeCode") as? Bool ?? false
        self.debugClaudeApp = UserDefaults.standard.object(forKey: "debugClaudeApp") as? Bool ?? false
        self.debugAndroid = UserDefaults.standard.object(forKey: "debugAndroid") as? Bool ?? true
        self.debugXcode = UserDefaults.standard.object(forKey: "debugXcode") as? Bool ?? true
        self.debugFinder = UserDefaults.standard.object(forKey: "debugFinder") as? Bool ?? true
        self.debugOpencode = UserDefaults.standard.object(forKey: "debugOpencode") as? Bool ?? false
        self.debugCodex = UserDefaults.standard.object(forKey: "debugCodex") as? Bool ?? false
        self.debugAutomator = UserDefaults.standard.object(forKey: "debugAutomator") as? Bool ?? false
        self.debugDownloads = UserDefaults.standard.object(forKey: "debugDownloads") as? Bool ?? false
        self.debugDaVinciResolve = UserDefaults.standard.object(forKey: "debugDaVinciResolve") as? Bool ?? false
        self.debugTeams = UserDefaults.standard.object(forKey: "debugTeams") as? Bool ?? false
        self.debugCalendar = UserDefaults.standard.object(forKey: "debugCalendar") as? Bool ?? false
        self.showMorningOverview = UserDefaults.standard.object(forKey: "showMorningOverview") as? Bool ?? false
        self.claudeScanAllSessions = UserDefaults.standard.object(forKey: "claudeScanAllSessions") as? Bool ?? false
        self.debugViewColors = UserDefaults.standard.object(forKey: "debugViewColors") as? Bool ?? false
        self.alwaysShowWelcomeMessage = UserDefaults.standard.object(forKey: "alwaysShowWelcomeMessage") as? Bool ?? false
        self.showWelcomeMessage = UserDefaults.standard.object(forKey: "showWelcomeMessage") as? Bool ?? false
    }
}

/// Tracking settings - which apps to monitor
final class TrackingSettings: ObservableObject {
    static let shared = TrackingSettings()

    @Published var trackClaudeCode: Bool {
        didSet { UserDefaults.standard.set(trackClaudeCode, forKey: "trackClaudeCode") }
    }
    @Published var trackClaudeApp: Bool {
        didSet { UserDefaults.standard.set(trackClaudeApp, forKey: "trackClaudeApp") }
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
    @Published var trackCalendar: Bool {
        didSet { UserDefaults.standard.set(trackCalendar, forKey: "trackCalendar") }
    }
    @Published var confettiEnabled: Bool {
        didSet { UserDefaults.standard.set(confettiEnabled, forKey: "confettiEnabled") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    /// Recently used apps for quick access in menu (max 4)
    @Published var recentlyUsedApps: [ProcessType] = [] {
        didSet {
            let rawValues = recentlyUsedApps.map { $0.rawValue }
            UserDefaults.standard.set(rawValues, forKey: "recentlyUsedApps")
        }
    }

    /// Mark a process type as recently used (called when detection activates)
    func markAsRecentlyUsed(_ processType: ProcessType) {
        // Skip preview and calendar (calendar is not a traditional app)
        guard processType != .preview && processType != .calendar && processType != .teams else { return }

        // Remove if already present, add to front, keep max 4
        recentlyUsedApps.removeAll { $0 == processType }
        recentlyUsedApps.insert(processType, at: 0)
        if recentlyUsedApps.count > 4 {
            recentlyUsedApps = Array(recentlyUsedApps.prefix(4))
        }
    }

    /// Get the tracking binding for a given process type
    func trackingBinding(for processType: ProcessType) -> Binding<Bool> {
        switch processType {
        case .claudeCode: return Binding(get: { self.trackClaudeCode }, set: { self.trackClaudeCode = $0 })
        case .claudeApp: return Binding(get: { self.trackClaudeApp }, set: { self.trackClaudeApp = $0 })
        case .androidStudio: return Binding(get: { self.trackAndroidStudio }, set: { self.trackAndroidStudio = $0 })
        case .xcode: return Binding(get: { self.trackXcode }, set: { self.trackXcode = $0 })
        case .finder: return Binding(get: { self.trackFinder }, set: { self.trackFinder = $0 })
        case .opencode: return Binding(get: { self.trackOpencode }, set: { self.trackOpencode = $0 })
        case .codex: return Binding(get: { self.trackCodex }, set: { self.trackCodex = $0 })
        case .dropbox: return Binding(get: { self.trackDropbox }, set: { self.trackDropbox = $0 })
        case .googleDrive: return Binding(get: { self.trackGoogleDrive }, set: { self.trackGoogleDrive = $0 })
        case .oneDrive: return Binding(get: { self.trackOneDrive }, set: { self.trackOneDrive = $0 })
        case .icloud: return Binding(get: { self.trackICloud }, set: { self.trackICloud = $0 })
        case .installer: return Binding(get: { self.trackInstaller }, set: { self.trackInstaller = $0 })
        case .appStore: return Binding(get: { self.trackAppStore }, set: { self.trackAppStore = $0 })
        case .automator: return Binding(get: { self.trackAutomator }, set: { self.trackAutomator = $0 })
        case .scriptEditor: return Binding(get: { self.trackScriptEditor }, set: { self.trackScriptEditor = $0 })
        case .downloads: return Binding(get: { self.trackDownloads }, set: { self.trackDownloads = $0 })
        case .davinciResolve: return Binding(get: { self.trackDaVinciResolve }, set: { self.trackDaVinciResolve = $0 })
        case .teams: return Binding(get: { self.trackTeams }, set: { self.trackTeams = $0 })
        case .calendar: return Binding(get: { self.trackCalendar }, set: { self.trackCalendar = $0 })
        case .preview: return Binding(get: { false }, set: { _ in })
        }
    }

    private init() {
        self.trackClaudeCode = UserDefaults.standard.object(forKey: "trackClaudeCode") as? Bool ?? false
        self.trackClaudeApp = UserDefaults.standard.object(forKey: "trackClaudeApp") as? Bool ?? false
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
        self.trackCalendar = UserDefaults.standard.object(forKey: "trackCalendar") as? Bool ?? false
        self.confettiEnabled = UserDefaults.standard.object(forKey: "confettiEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true

        // Load recently used apps
        if let rawValues = UserDefaults.standard.array(forKey: "recentlyUsedApps") as? [String] {
            self.recentlyUsedApps = rawValues.compactMap { ProcessType(rawValue: $0) }
        }
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
        didSet {
            UserDefaults.standard.set(notchStyle.rawValue, forKey: "notchStyle")
            NotificationCenter.default.post(name: .notchStyleChanged, object: nil)
        }
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

    /// Stroke width for minimal style (default 4)
    @Published var minimalStrokeWidth: CGFloat {
        didSet { UserDefaults.standard.set(minimalStrokeWidth, forKey: "minimalStrokeWidth") }
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
        self.minimalStrokeWidth = UserDefaults.standard.object(forKey: "minimalStrokeWidth") as? CGFloat ?? 4
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
            // Fallback to built-in display when no external connected
            if let screen = builtInScreen {
                return [screen]
            }
            return NSScreen.screens.isEmpty ? [] : [NSScreen.screens[0]]
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
    static let notchStyleChanged = Notification.Name("notchStyleChanged")
    static let showPositionPreview = Notification.Name("showPositionPreview")
    static let showSettingsPreview = Notification.Name("showSettingsPreview")
    static let hideSettingsPreview = Notification.Name("hideSettingsPreview")
    static let teamsMockDismissed = Notification.Name("teamsMockDismissed")
    static let showTeamsPreview = Notification.Name("showTeamsPreview")
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

/// Shared layout calculations for NotchView and NotchWindow
/// Uses the EXACT same calculations as NotchView to ensure perfect alignment
struct NotchLayout {
    // Normal mode dimensions (must match NotchView)
    static let notchWidth: CGFloat = 300
    static let logoSize: CGFloat = 24
    static let rowSpacing: CGFloat = 8
    static let topPadding: CGFloat = 38

    // Medium mode dimensions (must match NotchView)
    static let mediumLogoSize: CGFloat = 14
    static let mediumRowSpacing: CGFloat = 3
    static let mediumTopPaddingBase: CGFloat = 34

    // Teams camera dimensions (must match NotchView)
    static let cameraHeight: CGFloat = 150
    static let cameraWidth: CGFloat = 280

    // Teams hover scale: camera scales 1.8x on hover (anchor: .top)
    // Extra height needed: 150 * 0.8 = 120 pixels
    // Extra width needed: 280 * 0.8 = 224 pixels
    static let teamsHoverExtraHeight: CGFloat = 120
    static let teamsHoverExtraWidth: CGFloat = 224

    /// Calculate effectiveTopPadding exactly as NotchView does
    private static func effectiveTopPadding(notchInfo: NotchInfo, settings: StyleSettings) -> CGFloat {
        if notchInfo.hasNotch {
            if settings.trimTopOnNotchDisplay {
                return notchInfo.height + 4
            }
        } else {
            if settings.trimTopOnExternalDisplay {
                return 8
            }
        }
        return topPadding
    }

    /// Calculate effectiveMediumTopPadding exactly as NotchView does
    private static func effectiveMediumTopPadding(notchInfo: NotchInfo, settings: StyleSettings) -> CGFloat {
        if notchInfo.hasNotch {
            if settings.trimTopOnNotchDisplay {
                return notchInfo.height + 4
            }
        } else {
            if settings.trimTopOnExternalDisplay {
                return 8
            }
        }
        return mediumTopPaddingBase
    }

    /// Calculate the exact window frame for the notch content
    /// Uses the EXACT same formulas as NotchView's .frame() modifiers
    static func windowFrame(
        for processes: [ProcessType],
        style: NotchStyle,
        screen: NSScreen,
        settings: StyleSettings
    ) -> NSRect {
        guard !processes.isEmpty else {
            return .zero
        }

        let notchInfo = NotchInfo.forScreen(screen)
        let horizontalOffset = settings.horizontalOffset
        let hasTeams = processes.contains(.teams)
        let teamsOnly = processes == [.teams]
        let hasCalendar = processes.contains(.calendar)
        let calendarOnly = processes == [.calendar]
        let processCount = processes.count

        let width: CGFloat
        let height: CGFloat

        // Extra space for Teams hover scaling (camera scales 1.8x on hover)
        let teamsExtraHeight = hasTeams ? teamsHoverExtraHeight : 0
        let teamsExtraWidth = hasTeams ? teamsHoverExtraWidth : 0

        // Check if morning overview is showing (calendar in expanded view mode)
        let isMorningOverview = calendarOnly && DebugSettings.shared.showMorningOverview

        // Minimal stroke width from settings
        let minimalStrokeWidth = settings.minimalStrokeWidth

        // Special case: Calendar morning overview needs a larger window
        if isMorningOverview {
            // Calculate calendar content height based on actual data
            let effTopPadding = effectiveTopPadding(notchInfo: notchInfo, settings: settings)
            let data = ProcessMonitor.shared.getMorningOverviewData()
            let allDayCount = data.allDayEvents.count
            let timedCount = data.timedEvents.count
            let hasAllDay = allDayCount > 0

            // Use wider width when there are all-day events (to fit "All day" label)
            let calendarWidth: CGFloat = 340
            let calendarWidthWithAllDay: CGFloat = 380
            let effectiveCalendarWidth = hasAllDay ? calendarWidthWithAllDay : calendarWidth
            let normalEarSpace: CGFloat = 60
            width = effectiveCalendarWidth + normalEarSpace

            let allDayHeight = CGFloat(allDayCount) * 20  // Each all-day row ~20pt
            let allDaySpacing = allDayCount > 1 ? CGFloat(allDayCount - 1) * 14 : 0
            let timedHeight = CGFloat(timedCount) * 32  // Each timed row ~32pt (two lines)
            let timedSpacing = timedCount > 1 ? CGFloat(timedCount - 1) * 14 : 0
            let separatorHeight: CGFloat = (allDayCount > 0 && timedCount > 0) ? 12 : 0
            let emptyHeight: CGFloat = data.isEmpty ? 30 : 0
            let bottomPadding: CGFloat = 30  // Bottom padding
            let contentHeight = allDayHeight + allDaySpacing + separatorHeight + timedHeight + timedSpacing + emptyHeight + bottomPadding
            // Add small buffer for hover scaling (1.02x)
            let hoverExtra: CGFloat = 10
            height = effTopPadding + contentHeight + hoverExtra

            let x = screen.frame.minX + (screen.frame.width - width) / 2 + horizontalOffset
            let y = screen.frame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        }

        switch style {
        case .minimal:
            // From NotchView minimalModeView:
            // Stroke extends strokeWidth/2 on each side
            width = hasTeams ? cameraWidth + 20 + teamsExtraWidth : notchInfo.width + minimalStrokeWidth
            height = hasTeams ? notchInfo.height + 5 + cameraHeight + 16 + teamsExtraHeight : notchInfo.height + minimalStrokeWidth / 2

        case .medium:
            // From NotchView mediumModeView:
            // .frame(width: hasTeams ? cameraWidth + 20 : notchInfo.width, height: mediumExpandedHeight)
            // Medium mode uses MinimalNotchShape (no ears)
            width = hasTeams ? cameraWidth + 20 + teamsExtraWidth : notchInfo.width

            // mediumExpandedHeight calculation from NotchView:
            if teamsOnly {
                height = notchInfo.height + 5 + cameraHeight + 16 + teamsExtraHeight
            } else if hasTeams {
                let otherCount = processCount - 1
                let otherHeight = CGFloat(otherCount) * mediumLogoSize + CGFloat(max(0, otherCount - 1)) * mediumRowSpacing
                height = notchInfo.height + 5 + cameraHeight + 8 + otherHeight + 13 + teamsExtraHeight
            } else {
                let contentHeight = CGFloat(processCount) * mediumLogoSize + CGFloat(processCount - 1) * mediumRowSpacing
                height = effectiveMediumTopPadding(notchInfo: notchInfo, settings: settings) + contentHeight + 13
            }

        case .normal:
            // From NotchView normalModeView:
            // .frame(width: notchWidth, height: teamsExpandedHeight)
            // Add 60 for ears (cornerRadius 30 on each side)
            let normalEarSpace: CGFloat = 60
            width = hasTeams ? notchWidth + teamsExtraWidth + normalEarSpace : notchWidth + normalEarSpace

            // teamsExpandedHeight calculation from NotchView:
            let effTopPadding = effectiveTopPadding(notchInfo: notchInfo, settings: settings)
            if teamsOnly {
                height = effTopPadding + cameraHeight + 16 + teamsExtraHeight
            } else if hasTeams {
                let otherCount = processCount - 1
                let otherHeight = CGFloat(otherCount) * logoSize + CGFloat(max(0, otherCount - 1)) * rowSpacing
                height = effTopPadding + cameraHeight + 8 + otherHeight + 16 + teamsExtraHeight
            } else {
                // expandedHeight calculation
                let contentHeight = CGFloat(processCount) * logoSize + CGFloat(processCount - 1) * rowSpacing
                height = effTopPadding + contentHeight + 16
            }
        }

        // Calculate position: centered on screen with horizontal offset
        let x = screen.frame.minX + (screen.frame.width - width) / 2 + horizontalOffset
        let y = screen.frame.maxY - height

        return NSRect(x: x, y: y, width: width, height: height)
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
    case calendar = "Calendar"
    case claudeAndFinder = "Claude + Finder"
    case threeProcesses = "Claude + Finder + Android"
    case randomFive = "5 Random"

    var processType: ProcessType? {
        switch self {
        case .none: return nil
        case .claude: return .claudeCode
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
        case .calendar: return nil // Handled specially - shows morning overview
        case .claudeAndFinder: return nil // Handled specially
        case .threeProcesses: return nil // Handled specially
        case .randomFive: return nil // Handled specially
        }
    }

    /// Returns 5 random process types for demo purposes
    var fiveRandomProcessTypes: [ProcessType] {
        let allTypes: [ProcessType] = [.claudeCode, .claudeApp, .androidStudio, .xcode, .finder, .opencode, .codex, .dropbox, .googleDrive, .oneDrive, .icloud, .installer, .appStore]
        return Array(allTypes.shuffled().prefix(5))
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
    static let shared = AppState()
    @Published var isMonitoring: Bool = true
    @Published var updateAvailable: Bool = false

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

        // Show welcome message if this is a new version (with slight delay for app to settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            WelcomeMessageWindowController.shared.showIfNeeded()
        }
    }

    private var previewTimer: Timer?

    private func setupBindings() {
        // Observe welcome message debug flag
        DebugSettings.shared.$showWelcomeMessage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showMessage in
                guard let self = self else { return }
                if showMessage {
                    // Show window for welcome message (empty processes, view checks flag)
                    self.windowController.update(with: [.preview])  // Use preview as a trigger
                } else {
                    // Restore normal state
                    let processes = self.processMonitor.activeProcesses
                    self.windowController.update(with: processes)
                }
            }
            .store(in: &cancellables)

        // Observe morning overview debug flag
        // Use dropFirst() to prevent firing on launch with the stored value
        DebugSettings.shared.$showMorningOverview
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showOverview in
                guard let self = self else { return }
                if showOverview {
                    // Show window with calendar type to trigger morning overview
                    self.windowController.update(with: [.calendar])
                } else {
                    // Restore normal state
                    let processes = self.processMonitor.activeProcesses
                    self.windowController.update(with: processes)
                }
            }
            .store(in: &cancellables)

        processMonitor.$activeProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                guard let self = self else { return }
                // Skip updates when welcome message or morning overview is showing
                guard !DebugSettings.shared.showWelcomeMessage else { return }
                guard !DebugSettings.shared.showMorningOverview else { return }
                print("📡 App received activeProcesses update: \(processes.map { $0.displayName })")
                #if DEBUG
                // If mocking with a timed mock, skip real updates entirely
                guard !self.isMocking else {
                    print("📡 Skipping update - isMocking is true")
                    return
                }
                // Combine mock processes (like Teams) with real processes
                let combined = Array(Set(processes + self.mockProcesses)).sorted { $0.rawValue < $1.rawValue }
                self.windowController.update(with: combined)
                #else
                self.windowController.update(with: processes)
                #endif
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

        // Listen for style changes to reset preview animation
        NotificationCenter.default.addObserver(
            forName: .notchStyleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetSettingsPreview()
        }

        #if DEBUG
        // Listen for Teams mock dismissal to clean up mockProcesses
        NotificationCenter.default.addObserver(
            forName: .teamsMockDismissed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.mockProcesses.removeAll { $0 == .teams }
        }
        #endif

        // Listen for Teams preview request from Smart Features settings
        NotificationCenter.default.addObserver(
            forName: .showTeamsPreview,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showTeamsPreview()
        }
    }

    /// Show Teams camera preview (triggered from Smart Features settings)
    private func showTeamsPreview() {
        CameraManager.shared.startSession()

        #if DEBUG
        // Add to mockProcesses so it persists
        if !mockProcesses.contains(.teams) {
            mockProcesses.append(.teams)
        }
        #endif

        // Combine with any existing processes
        let realProcesses = processMonitor.activeProcesses
        var combined = Array(Set(realProcesses))
        if !combined.contains(.teams) {
            combined.append(.teams)
        }
        combined.sort { $0.rawValue < $1.rawValue }
        windowController.update(with: combined)
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

        // Only show mock if no real processes are active
        if processMonitor.activeProcesses.isEmpty {
            windowController.update(with: [.preview])
        }

        // Hide mock after 1.5 seconds (only if no real processes)
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            if self?.processMonitor.activeProcesses.isEmpty == true {
                self?.windowController.update(with: [])
            }
        }
    }

    /// Show preview while settings are open
    private func showSettingsPreviewPersistent() {
        isShowingSettingsPreview = true
        previewTimer?.invalidate()
        // Always show preview when settings are open
        windowController.update(with: [.preview])
    }

    /// Reset and re-show preview (for style changes)
    private func resetSettingsPreview() {
        guard isShowingSettingsPreview else { return }
        // Clear first, then show fresh to restart animation
        windowController.update(with: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard self?.isShowingSettingsPreview == true else { return }
            self?.windowController.update(with: [.preview])
        }
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
        // Handle "5 Random" mock type specially
        if mockOnLaunchType == .randomFive {
            runRandomFiveMock()
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

        // Handle "Calendar" mock type - shows morning overview
        if mockOnLaunchType == .calendar {
            runCalendarMock()
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
            // Add to mockProcesses so binding combines it with real processes
            if !mockProcesses.contains(processType) {
                mockProcesses.append(processType)
            }
            // Reset isMocking so real process updates work alongside Teams mock
            isMocking = false
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
        windowController.update(with: [.claudeCode, .finder])

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
        windowController.update(with: [.claudeCode, .finder, .androidStudio])

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

    private func runCalendarMock() {
        // Show morning overview with mock data
        // It stays until user clicks to dismiss (no auto-dismiss)
        DebugSettings.shared.useMockCalendarData = true
        DebugSettings.shared.showMorningOverview = true
        // Start monitoring so other detectors still work
        startMonitoring()
    }

    private func runRandomFiveMock() {
        isMocking = true
        let randomTypes = mockOnLaunchType.fiveRandomProcessTypes

        // Start with 5 random processes
        windowController.update(with: randomTypes)

        // Remove processes one by one with delays
        for index in 0..<randomTypes.count {
            let remaining = Array(randomTypes.dropFirst(index + 1))
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(2 + index)) { [weak self] in
                self?.windowController.update(with: remaining)

                // When all removed, handle repeat or cleanup
                if remaining.isEmpty {
                    if self?.mockRepeat == true {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            self?.runRandomFiveMock()
                        }
                    } else {
                        self?.isMocking = false
                        self?.startMonitoring()
                    }
                }
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

        // Combine mock processes with real active processes
        let realProcesses = ProcessMonitor.shared.activeProcesses
        let combined = Array(Set(realProcesses + mockProcesses)).sorted { $0.rawValue < $1.rawValue }
        windowController.update(with: combined)

        // Teams is dismissed via hover interaction, not timeout
        // Don't set isMocking for Teams - real process updates should still work alongside
        if process == .teams {
            return
        }

        #if DEBUG
        isMocking = true
        #endif

        // Remove this specific process after 5 seconds (non-Teams)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.mockProcesses.removeAll { $0 == process }
            // Combine remaining mocks with real active processes
            let realProcesses = ProcessMonitor.shared.activeProcesses
            let combined = Array(Set(realProcesses + (self?.mockProcesses ?? []))).sorted { $0.rawValue < $1.rawValue }
            self?.windowController.update(with: combined)

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

/// Menu item button with icon and hover highlight
struct MenuItemButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    var shortcut: String? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.accentColor : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            isHovered = hovering
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
        VStack(alignment: .leading, spacing: 2) {
            // License status
            licenseStatusView
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            // Toggle calendar button at top if calendar tracking is enabled
            if trackingSettings.trackCalendar {
                MenuItemButton(label: "Today's Calendar", icon: "calendar") {
                    DebugSettings.shared.showMorningOverview.toggle()
                }
            }

            Divider()
                .padding(.vertical, 4)

            HStack {
                Text("Enabled")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { appState.isMonitoring },
                    set: { _ in appState.toggleMonitoring() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Recent apps section (only show if there are recently used apps)
            if !trackingSettings.recentlyUsedApps.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Recent")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                ForEach(trackingSettings.recentlyUsedApps, id: \.self) { processType in
                    HStack {
                        Text(processType.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("", isOn: trackingSettings.trackingBinding(for: processType))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .disabled(!appState.isMonitoring)
            }

            Divider()
                .padding(.vertical, 4)

            MenuItemButton(label: "Settings...", icon: "gearshape", shortcut: "⌘,") {
                SettingsWindowController.shared.showSettings()
            }

            HStack(spacing: 4) {
                MenuItemButton(label: "Check for Updates...", icon: "arrow.clockwise") {
                    updater.checkForUpdates()
                }
                if appState.updateAvailable {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
            }

            Divider()
                .padding(.vertical, 4)

            MenuItemButton(label: "Send Feedback", icon: "envelope") {
                let subject = "Notchification Feedback"
                let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
                if let url = URL(string: "mailto:alexanderkvamme@gmail.com?subject=\(encodedSubject)") {
                    NSWorkspace.shared.open(url)
                }
            }

            MenuItemButton(label: "Quit", icon: "xmark.circle", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var licenseStatusView: some View {
        switch licenseManager.state {
        case .licensed:
            Label("Licensed", systemImage: "checkmark.seal.fill")
                .font(.body.weight(.medium))
                .foregroundColor(.green)

        case .trial(let daysRemaining):
            Label("Trial: \(daysRemaining) days left", systemImage: "clock")
                .font(.body.weight(.medium))
                .foregroundColor(.orange)

        case .expired:
            HStack(spacing: 8) {
                Label("Trial expired", systemImage: "xmark.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundColor(.red)

                Button("Buy") {
                    NSWorkspace.shared.open(licenseManager.purchaseURL)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}
