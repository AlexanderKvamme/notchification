//
//  CalendarSettings.swift
//  Notchification
//
//  User preferences for calendar reminder intervals
//

import Foundation
import EventKit

/// Available reminder intervals before meetings
enum ReminderInterval: Int, CaseIterable, Identifiable, Comparable {
    case oneHour = 60
    case thirtyMinutes = 30
    case fifteenMinutes = 15
    case tenMinutes = 10
    case fiveMinutes = 5
    case oneMinute = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneHour: return "1 hour"
        case .thirtyMinutes: return "30 min"
        case .fifteenMinutes: return "15 min"
        case .tenMinutes: return "10 min"
        case .fiveMinutes: return "5 min"
        case .oneMinute: return "1 min"
        }
    }

    static func < (lhs: ReminderInterval, rhs: ReminderInterval) -> Bool {
        lhs.rawValue > rhs.rawValue  // Sort by time descending (1 hour first)
    }
}

/// Calendar authorization status for UI display
enum CalendarAuthStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    static func from(_ status: EKAuthorizationStatus) -> CalendarAuthStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .fullAccess, .writeOnly: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

/// Calendar settings for the calendar feature
final class CalendarSettings: ObservableObject {
    static let shared = CalendarSettings()

    /// Identifiers of calendars to show events from
    @Published var selectedCalendarIdentifiers: Set<String> {
        didSet {
            let array = Array(selectedCalendarIdentifiers)
            UserDefaults.standard.set(array, forKey: "calendarSelectedIdentifiers")
        }
    }

    /// Which reminder intervals are enabled
    @Published var enabledIntervals: Set<ReminderInterval> {
        didSet {
            let rawValues = enabledIntervals.map { $0.rawValue }
            UserDefaults.standard.set(rawValues, forKey: "calendarEnabledIntervals")
        }
    }

    /// Current authorization status
    @Published private(set) var authorizationStatus: CalendarAuthStatus = .notDetermined

    // MARK: - Morning Overview Settings

    /// Enable automatic morning overview on wake/unlock
    @Published var enableMorningOverview: Bool {
        didSet {
            UserDefaults.standard.set(enableMorningOverview, forKey: "calendarEnableMorningOverview")
        }
    }

    /// Start hour for "morning" (0-23, default 6 = 6 AM)
    @Published var morningStartHour: Int {
        didSet {
            UserDefaults.standard.set(morningStartHour, forKey: "calendarMorningStartHour")
        }
    }

    /// End hour for "morning" (0-23, default 10 = 10 AM)
    @Published var morningEndHour: Int {
        didSet {
            UserDefaults.standard.set(morningEndHour, forKey: "calendarMorningEndHour")
        }
    }

    /// Date when morning overview was last shown (to show only once per day)
    private var lastMorningOverviewDate: Date? {
        didSet {
            UserDefaults.standard.set(lastMorningOverviewDate, forKey: "calendarLastMorningOverviewDate")
        }
    }

    private init() {
        let savedIdentifiers = UserDefaults.standard.array(forKey: "calendarSelectedIdentifiers") as? [String] ?? []
        self.selectedCalendarIdentifiers = Set(savedIdentifiers)

        // Load enabled intervals, default to 15 min and 5 min
        if let savedIntervals = UserDefaults.standard.array(forKey: "calendarEnabledIntervals") as? [Int] {
            self.enabledIntervals = Set(savedIntervals.compactMap { ReminderInterval(rawValue: $0) })
        } else {
            self.enabledIntervals = [.fifteenMinutes, .fiveMinutes]
        }

        // Load morning overview settings
        self.enableMorningOverview = UserDefaults.standard.object(forKey: "calendarEnableMorningOverview") as? Bool ?? true
        self.morningStartHour = UserDefaults.standard.object(forKey: "calendarMorningStartHour") as? Int ?? 6
        self.morningEndHour = UserDefaults.standard.object(forKey: "calendarMorningEndHour") as? Int ?? 10
        self.lastMorningOverviewDate = UserDefaults.standard.object(forKey: "calendarLastMorningOverviewDate") as? Date

        // Get initial auth status
        let status = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = CalendarAuthStatus.from(status)
    }

    /// Update authorization status (called after permission request)
    func updateAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            self.authorizationStatus = CalendarAuthStatus.from(status)
        }
    }

    /// Get the maximum look-ahead time based on enabled intervals
    var maxLookAheadMinutes: Int {
        enabledIntervals.map { $0.rawValue }.max() ?? 15
    }

    /// Check if a given minutes-until-meeting matches any enabled interval (with tolerance)
    func shouldShowReminder(minutesUntilMeeting: Double) -> Bool {
        for interval in enabledIntervals {
            let target = Double(interval.rawValue)
            // Show if within 30 seconds of the interval
            if abs(minutesUntilMeeting - target) < 0.5 {
                return true
            }
        }
        return false
    }

    // MARK: - Morning Overview Logic

    /// Check if we should show the morning overview right now
    /// Returns true if: enabled, authorized, within morning hours, and not shown today yet
    func shouldShowMorningOverview() -> Bool {
        #if DEBUG
        print("📅 shouldShowMorningOverview check:")
        print("  - enableMorningOverview: \(enableMorningOverview)")
        print("  - authorizationStatus: \(authorizationStatus)")
        #endif

        // Must be enabled
        guard enableMorningOverview else {
            #if DEBUG
            print("  ❌ Feature disabled")
            #endif
            return false
        }

        // Must have calendar access
        guard authorizationStatus == .authorized else {
            #if DEBUG
            print("  ❌ Calendar not authorized")
            #endif
            return false
        }

        // Check if current time is within morning hours
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        #if DEBUG
        print("  - Current hour: \(hour), Range: \(morningStartHour)-\(morningEndHour)")
        #endif

        guard hour >= morningStartHour && hour < morningEndHour else {
            #if DEBUG
            print("  ❌ Outside morning hours")
            #endif
            return false
        }

        // Check if we've already shown it today
        if let lastShown = lastMorningOverviewDate {
            #if DEBUG
            print("  - Last shown: \(lastShown)")
            print("  - Is today: \(calendar.isDateInToday(lastShown))")
            #endif
            if calendar.isDateInToday(lastShown) {
                #if DEBUG
                print("  ❌ Already shown today")
                #endif
                return false  // Already shown today
            }
        } else {
            #if DEBUG
            print("  - Last shown: never")
            #endif
        }

        #if DEBUG
        print("  ✅ All conditions met!")
        #endif
        return true
    }

    /// Mark that we've shown the morning overview today
    func markMorningOverviewShown() {
        lastMorningOverviewDate = Date()
    }

    /// Reset the morning overview shown state (for testing)
    func resetMorningOverviewShown() {
        lastMorningOverviewDate = nil
    }
}
