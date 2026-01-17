//
//  CalendarService.swift
//  Notchification
//
//  EventKit integration for calendar meeting reminders.
//  Shows notch at user-selected intervals before meetings.
//  Color: Calendar blue (#007AFF)
//

import Foundation
import EventKit
import Combine

/// Information about an upcoming calendar event (for reminders)
struct CalendarEventInfo {
    let title: String
    let startDate: Date

    /// Minutes until event starts
    var minutesUntilStart: Double {
        startDate.timeIntervalSinceNow / 60.0
    }

    /// Formatted time until start (e.g., "15m", "1h")
    var formattedTimeUntil: String {
        let minutes = max(0, Int(minutesUntilStart))
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "now"
        }
    }
}

/// Information about a calendar event for the morning overview
struct MorningEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let isAllDay: Bool

    /// Formatted start time (e.g., "09:00", "14:30")
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startDate)
    }

    /// Duration in minutes
    var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    /// Formatted duration (e.g., "45m", "1h", "1h 30m")
    var formattedDuration: String {
        let minutes = durationMinutes
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    /// Extract meeting room from location (often in format "Room Name; Address" or just "Room Name")
    var meetingRoom: String? {
        guard let location = location, !location.isEmpty else { return nil }
        // Take first part before semicolon or the whole string
        let room = location.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
        return room?.isEmpty == true ? nil : room
    }
}

/// Data for the morning overview display
struct MorningOverviewData {
    let allDayEvents: [MorningEvent]
    let timedEvents: [MorningEvent]

    var isEmpty: Bool {
        allDayEvents.isEmpty && timedEvents.isEmpty
    }
}

/// Service for calendar meeting reminders
final class CalendarService: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var nextEvent: CalendarEventInfo?

    let processType: ProcessType = .calendar

    private let eventStore = EKEventStore()
    private let settings = CalendarSettings.shared
    private let checkQueue = DispatchQueue(label: "com.notchification.calendar-check", qos: .utility)

    // Debouncing
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    private var debug: Bool { DebugSettings.shared.debugCalendar }

    init() {
        // Listen for calendar database changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }

    @objc private func calendarStoreChanged() {
        if debug { print("📅 Calendar store changed, refreshing...") }
        poll()
    }

    /// Request calendar access permission
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                settings.updateAuthorizationStatus()
            }
            if debug { print("📅 Calendar access granted: \(granted)") }
            return granted
        } catch {
            if debug { print("📅 Calendar access error: \(error)") }
            await MainActor.run {
                settings.updateAuthorizationStatus()
            }
            return false
        }
    }

    /// Get all available calendars
    func getAvailableCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    /// Get today's events for the morning overview
    /// When showMorningOverview debug flag is on, returns mock data for testing
    func getMorningOverviewData() -> MorningOverviewData {
        // Return mock data when manually showing morning overview (for testing)
        if DebugSettings.shared.showMorningOverview {
            return Self.mockMorningOverviewData()
        }

        // Check authorization
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            if debug { print("📅 Morning overview: Calendar not authorized") }
            return MorningOverviewData(allDayEvents: [], timedEvents: [])
        }

        // Get selected calendars
        let allCalendars = eventStore.calendars(for: .event)
        let selectedIds = settings.selectedCalendarIdentifiers
        let calendars: [EKCalendar]

        if selectedIds.isEmpty {
            calendars = allCalendars
        } else {
            calendars = allCalendars.filter { selectedIds.contains($0.calendarIdentifier) }
        }

        if calendars.isEmpty {
            if debug { print("📅 Morning overview: No calendars available") }
            return MorningOverviewData(allDayEvents: [], timedEvents: [])
        }

        // Query all events for today
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )

        let events = eventStore.events(matching: predicate)

        // Split into all-day and timed events
        var allDayEvents: [MorningEvent] = []
        var timedEvents: [MorningEvent] = []

        for event in events {
            let morningEvent = MorningEvent(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                isAllDay: event.isAllDay
            )

            if event.isAllDay {
                allDayEvents.append(morningEvent)
            } else {
                timedEvents.append(morningEvent)
            }
        }

        // Sort timed events by start time
        timedEvents.sort { $0.startDate < $1.startDate }

        if debug {
            print("📅 Morning overview: \(allDayEvents.count) all-day, \(timedEvents.count) timed events")
        }

        return MorningOverviewData(allDayEvents: allDayEvents, timedEvents: timedEvents)
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        DispatchQueue.main.async {
            self.isActive = false
            self.nextEvent = nil
        }
    }

    func poll() {
        checkQueue.async { [weak self] in
            self?.checkCalendarEvents()
        }
    }

    private func checkCalendarEvents() {
        // Check authorization
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            if debug { print("📅 Calendar not authorized: \(status.rawValue)") }
            handleInactive()
            return
        }

        // Check if any intervals are enabled
        guard !settings.enabledIntervals.isEmpty else {
            if debug { print("📅 No reminder intervals enabled") }
            handleInactive()
            return
        }

        // Get selected calendars
        let allCalendars = eventStore.calendars(for: .event)
        let selectedIds = settings.selectedCalendarIdentifiers
        let calendars: [EKCalendar]

        if selectedIds.isEmpty {
            calendars = allCalendars
        } else {
            calendars = allCalendars.filter { selectedIds.contains($0.calendarIdentifier) }
        }

        if calendars.isEmpty {
            if debug { print("📅 No calendars available") }
            handleInactive()
            return
        }

        // Query events within max look-ahead window
        let now = Date()
        let maxLookAhead = Double(settings.maxLookAheadMinutes) * 60 + 60  // Add 1 min buffer
        let endDate = now.addingTimeInterval(maxLookAhead)

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: calendars
        )

        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        if debug { print("📅 Found \(events.count) upcoming events") }

        // Find the next upcoming event
        guard let nextEventEK = events.first else {
            if debug { print("📅 No upcoming events") }
            handleInactive()
            return
        }

        let minutesUntil = nextEventEK.startDate.timeIntervalSinceNow / 60.0

        if debug {
            print("📅 Next event: \(nextEventEK.title ?? "Untitled") in \(String(format: "%.1f", minutesUntil)) min")
        }

        // Check if we should show a reminder at the current time
        let shouldShow = settings.shouldShowReminder(minutesUntilMeeting: minutesUntil)

        if debug { print("📅 Should show reminder: \(shouldShow)") }

        if shouldShow {
            let eventInfo = CalendarEventInfo(
                title: nextEventEK.title ?? "Meeting",
                startDate: nextEventEK.startDate
            )
            handleActive(event: eventInfo)
        } else {
            handleInactive()
        }
    }

    private func handleActive(event: CalendarEventInfo) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.consecutiveActiveReadings += 1
            self.consecutiveInactiveReadings = 0
            self.nextEvent = event

            if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                if self.debug { print("📅 Calendar activating - reminder for: \(event.title)") }
                self.isActive = true
            }
        }
    }

    private func handleInactive() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.consecutiveInactiveReadings += 1
            self.consecutiveActiveReadings = 0

            if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                if self.debug { print("📅 Calendar deactivating") }
                self.isActive = false
                self.nextEvent = nil
            }
        }
    }

    // MARK: - Mock Data

    /// Generate mock morning overview data for testing
    static func mockMorningOverviewData() -> MorningOverviewData {
        let calendar = Calendar.current
        let now = Date()

        // Create mock times for today
        let time1 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let time2 = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: now) ?? now
        let time3 = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now

        let allDayEvents = [
            MorningEvent(
                title: "Sarah's birthday",
                startDate: now,
                endDate: now,
                location: nil,
                isAllDay: true
            )
        ]

        let timedEvents = [
            MorningEvent(
                title: "Team standup",
                startDate: time1,
                endDate: calendar.date(byAdding: .minute, value: 15, to: time1) ?? time1,
                location: "Zoom",
                isAllDay: false
            ),
            MorningEvent(
                title: "Design review",
                startDate: time2,
                endDate: calendar.date(byAdding: .hour, value: 1, to: time2) ?? time2,
                location: "Room 4.02",
                isAllDay: false
            ),
            MorningEvent(
                title: "1:1 with Alex",
                startDate: time3,
                endDate: calendar.date(byAdding: .minute, value: 30, to: time3) ?? time3,
                location: "Coffee corner",
                isAllDay: false
            )
        ]

        return MorningOverviewData(allDayEvents: allDayEvents, timedEvents: timedEvents)
    }
}
