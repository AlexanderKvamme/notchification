# Notchification - Claude Code Notes

## IMPORTANT: Debug Output Rules

**NEVER REMOVE debug statements** - they are essential for diagnosing detection issues.

### Adding Debug Logging to Detectors

Every detector MUST have a corresponding debug toggle in `DebugSettings` (in `NotchificationApp.swift`). When adding a new detector:

1. **Add a debug setting** in `DebugSettings`:
   ```swift
   @Published var debugMyDetector: Bool {
       didSet { UserDefaults.standard.set(debugMyDetector, forKey: "debugMyDetector") }
   }
   // Initialize in init():
   self.debugMyDetector = UserDefaults.standard.object(forKey: "debugMyDetector") as? Bool ?? false
   ```

2. **Add a menu toggle** in the Debug menu (ladybug icon):
   ```swift
   Toggle("My Detector", isOn: $debugSettings.debugMyDetector)
   ```

3. **Use verbose logging** in the detector when debug is enabled:
   ```swift
   private var debug: Bool { DebugSettings.shared.debugMyDetector }

   // In init:
   if debug { print("🔍 MyDetector init - status: ...") }

   // In poll/detection:
   if debug { print("🔍 MyDetector checking... result=\(result)") }
   ```

4. **Use an emoji prefix** for each detector (makes log filtering easier):
   - Claude: 🔶
   - Android Studio: 🤖
   - Xcode: 🔨
   - etc.

### Existing Debug Settings

- `debugClaude` - Claude CLI detection (🔶)
- `debugAndroid` - Android Studio / Gradle detection (🤖)
- `debugXcode` - Xcode build detection (🔨)
- `debugFinder` - Finder copy operations
- `debugOpencode` - Opencode CLI detection
- `debugCodex` - Codex CLI detection
- `debugAutomator` - Automator workflow detection
- `debugCalendar` - Calendar event detection (📅)

## Adding a New Detector Checklist

When adding a new detector, you MUST complete ALL of these steps:

1. **Create the detector** in `Services/` (e.g., `MyDetector.swift`)
2. **Add ProcessType** case in `Models/ProcessType.swift` with:
   - Raw value, displayName, color, waveColor, grayscalePattern
3. **Add tracking setting** in `TrackingSettings` (NotchificationApp.swift):
   - `@Published var trackMyDetector: Bool` with UserDefaults persistence
4. **Add debug setting** in `DebugSettings` (NotchificationApp.swift)
5. **Wire up in ProcessMonitor.swift**:
   - Create detector instance
   - Add poll() call in tick()
   - Add isActive binding in setupBindings()
   - Add to updateActiveProcesses()
   - Add tracking settings listener
6. **Add toggle to MenuBarView** in the "Track Apps" section:
   ```swift
   Toggle("My Detector", isOn: $trackingSettings.trackMyDetector)
   ```
   **IMPORTANT: Every tracker MUST have a toggle in the menu bar!**
7. **Add debug toggle** to DebugMenuView (ladybug menu)
8. **Add logo** in NotchView.swift if using a custom icon

## ClaudeDetector Architecture

The detector:
- Uses AppleScript to read iTerm2/Terminal.app content
- Looks for the `searchPattern` (built from ["esc", "to", "interrupt"]) in the last 10 non-empty lines
- The pattern is built at runtime to avoid false positives when source code is visible in terminal
- Has a 2-second timeout on osascript calls
- Uses a serial queue to prevent overlapping checks

## CalendarService Architecture

The calendar feature uses EventKit to show meeting reminders at user-selected intervals:
- **Location**: `Services/CalendarService.swift`
- **Settings**: `Models/CalendarSettings.swift`
- **Color**: #007AFF (Calendar blue)

### How it works:
1. Uses `EKEventStore` to query upcoming calendar events
2. User selects which reminder intervals to show (1 hour, 30 min, 15 min, 10 min, 5 min, 1 min)
3. Notch appears when current time matches a selected interval before a meeting
4. Shows countdown time (e.g., "15m", "30m") with animated progress bar
5. Respects user-selected calendars (or all calendars if none selected)

### Files:
- `Services/CalendarService.swift` - EventKit integration, event fetching
- `Models/CalendarSettings.swift` - User preferences (reminder intervals, calendar selection)
- Settings UI in `Views/SettingsView.swift` (SmartFeaturesTab)

### Settings:
- Checkbox for each reminder interval (1 hour, 30 min, 15 min, 10 min, 5 min, 1 min)
- Calendar picker to select which calendars to monitor
- Requires `NSCalendarsUsageDescription` in Info.plist
- Works with any calendar synced to macOS Calendar.app (Outlook, iCloud, Google, etc.)

### Debugging Calendar:
1. Enable `debugCalendar` in settings (📅 emoji prefix in logs)
2. Check that calendar access is granted in System Settings > Privacy > Calendars
3. Verify events exist in the look-ahead window
4. Check Console.app for "📅 Calendar" logs

### Morning Overview Feature:
The morning overview shows a larger calendar view with today's events:
- **All-day events** displayed at the top
- **Timed meetings** listed below with time, title, and meeting room
- **Debug flag**: Enable "Show Morning Overview" in Debug menu to test

Files:
- `Views/MorningOverviewView.swift` - The expanded calendar view
- `Services/CalendarService.swift` - `getMorningOverviewData()` fetches today's events
- Data types: `MorningEvent`, `MorningOverviewData`

## Debugging Checklist

When Claude detection isn't working:
1. Enable `debugClaude` in settings
2. Check Console.app for logs from "ClaudeDetector"
3. Verify Accessibility permissions for the app
4. Check if iTerm2/Terminal is actually running
5. Look at the actual terminal content being read
6. Check the permissions output on launch (printed in Xcode console in DEBUG builds)
