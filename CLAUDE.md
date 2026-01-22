# Notchification - Claude Code Notes

## CRITICAL: Detector Design Principles

**DO NOT CHANGE** the core detection approach for any detector without explicit user approval. The detection methods have been carefully chosen for reliability.

### Authoritative vs Heuristic Detection

Always prefer **authoritative sources** over **heuristic approaches**:

| Authoritative (GOOD) | Heuristic (BAD) |
|---------------------|-----------------|
| `gradle --status` → BUSY/IDLE | CPU monitoring via `ps` |
| Accessibility API status text | Process count |
| Daemon status commands | Memory usage |
| CLI output patterns | Timing-based detection |

**Why this matters:**
- CPU monitoring is unreliable (threshold tuning, varies by machine, misses low-CPU operations)
- Daemon/status commands give the actual state directly from the tool
- AX API status text is what the user sees - it's authoritative

### Current Detection Methods (DO NOT CHANGE)

| Detector | Method | Why |
|----------|--------|-----|
| **Android Studio** | `gradle --status` → BUSY/IDLE | Direct daemon state, version-agnostic |
| **Xcode** | AX API status text only | Status bar shows "Building...", "Compiling..." |
| **Claude Code** | Terminal content scanning | Looks for spinner + "esc to interrupt" pattern |
| **Claude App** | AX API status text | Looks for "Claude is thinking" in UI |

### If You're Tempted to "Simplify" Detection

**STOP.** The current approaches were chosen after testing alternatives:
- CPU monitoring was tried and rejected - too unreliable
- Process counting was tried and rejected - doesn't indicate active work
- The current methods work because they query the actual tool's state

If detection isn't working, the problem is likely:
1. Missing permissions (Accessibility, Automation)
2. Path/environment issues (JAVA_HOME, gradle path)
3. Changed UI/output format in the target app

**Fix the root cause, don't replace the detection method.**

---

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

## AndroidStudioDetector Architecture

The detector uses `gradle --status` to check if Gradle daemons are BUSY or IDLE:
- **Location**: `Services/AndroidStudioDetector.swift`
- **Color**: #2BA160 (Android green)

### Why `gradle --status` (not CPU monitoring)

**`gradle --status` is authoritative** - it returns the actual daemon state:
```
PID   STATUS   INFO
12345 BUSY     8.0
12346 IDLE     8.0
```

CPU monitoring was tried and rejected because:
- Threshold (e.g., >5% CPU) varies by machine and build type
- Some builds don't spike CPU significantly
- Idle daemons can occasionally show CPU activity
- It's a heuristic, not the actual state

### How it works:
1. Check if Android Studio is running (NSWorkspace, cheap)
2. Find gradle path (Homebrew or ~/.gradle/wrapper/dists)
3. Run `gradle --status` with proper JAVA_HOME
4. Parse output for "BUSY" or "IDLE"
5. Use consecutive readings to debounce (1 to show, 3 to hide)

### Debugging Android Studio:
1. Check Console.app for "🤖" logs
2. Verify gradle is found at startup
3. Verify JAVA_HOME is set or auto-detected
4. Run `gradle --status` manually to test

---

## CodexDetector Architecture

The detector identifies OpenAI's Codex CLI by looking for its specific output pattern:
- **Location**: `Services/CodexDetector.swift`
- **Color**: #F9F9F9 (OpenAI light gray)

### Pattern Matching (IMPORTANT)

Codex output format: `• Working (5s • esc to interrupt)`

The detector requires **BOTH**:
1. Line starts with `•` bullet point
2. Line contains timing pattern `(\d+s •` (e.g., "(1s •", "(9s •", "(54s •")

**Why both checks are required:**
- Claude CLI also uses "esc to interrupt" but WITHOUT the timing pattern
- Just checking for `•` prefix would cause false positives with Claude
- The `(Xs •` timing pattern is unique to Codex

**DO NOT simplify this to just check for `•`** - it was tried and caused Claude/Codex confusion.

---

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

## Permissions Architecture

**Design Principle**: Permissions are requested when the user enables features, NOT at app launch.

### Why:
- Asking for multiple permissions on first launch is overwhelming
- Users don't understand why permissions are needed without context
- Requesting in context (when enabling a feature) has higher grant rates

### Permission Summary

| Permission | When Requested | Trigger Location |
|------------|----------------|------------------|
| **Calendar** | User enables "Calendar" toggle | `SettingsView.swift` → `handleCalendarPermission()` |
| **Camera** | User enables "Microsoft Teams" toggle | `SettingsView.swift` → `handleCameraPermission()` |
| **Accessibility** | Never prompted (read-only check) | User must manually grant in System Settings |
| **Automation** | Only checked in DEBUG builds | `PermissionsChecker` (does not run in release) |
| **Downloads folder** | Never (app not sandboxed) | N/A |

### Entitlements (`Notchification.entitlements`)

```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- App is NOT sandboxed - no file access prompts -->

<key>com.apple.security.device.camera</key>
<true/>   <!-- For Teams camera preview -->

<key>com.apple.security.personal-information.calendars</key>
<true/>   <!-- For calendar reminders -->
```

### Permission Request Flow

1. **Calendar Permission**:
   - User toggles "Enable" in Calendar settings tab
   - `handleCalendarPermission()` checks `EKEventStore.authorizationStatus(for: .event)`
   - If `.notDetermined`, calls `requestFullAccessToEvents()`
   - If `.denied`, opens System Settings Privacy pane

2. **Camera Permission**:
   - User toggles "Microsoft Teams" in Apps settings tab
   - `handleCameraPermission()` checks `AVCaptureDevice.authorizationStatus(for: .video)`
   - If `.notDetermined`, calls `AVCaptureDevice.requestAccess(for: .video)`
   - If `.denied`, opens System Settings Privacy pane

3. **Accessibility Permission**:
   - Checked with `AXIsProcessTrusted()` (read-only, no prompt)
   - User must manually enable in System Settings > Privacy & Security > Accessibility
   - Required for: Xcode status detection, Claude App detection, Finder detection

4. **Automation Permission**:
   - Required for terminal scanning (iTerm2, Terminal.app)
   - macOS prompts automatically on first AppleScript execution
   - Only explicitly checked in DEBUG builds via `PermissionsChecker`

### DO NOT add permission requests at app launch

If you're tempted to request permissions early "for convenience":
- **DON'T** - it's bad UX to bombard users with permission dialogs on first launch
- Permissions should only be requested when the user explicitly enables a feature
- The current implementation follows Apple's guidelines for just-in-time permission requests

---

## Debugging Checklist

When Claude detection isn't working:
1. Enable `debugClaude` in settings
2. Check Console.app for logs from "ClaudeDetector"
3. Verify Accessibility permissions for the app
4. Check if iTerm2/Terminal is actually running
5. Look at the actual terminal content being read
6. Check the permissions output on launch (printed in Xcode console in DEBUG builds)

---

## Release Process

When releasing a new version, follow these steps:

### 1. Update CEO Welcome Message (REQUIRED)

**Before every release**, update the welcome message in `Views/WelcomeMessageView.swift`:

```swift
static let current = WelcomeMessage(
    version: "1.0.XX",  // Match the new version
    title: "Welcome to Notchification 1.0.XX",
    body: """
    Your message to users here...
    """,
    signoff: "— Alexander"
)
```

This message shows **once** when users first launch the new version.

### 2. Bump Version

Update `MARKETING_VERSION` in project.pbxproj (both Debug and Release configs).

### 3. Build Release

```bash
xcodebuild -scheme Notchification -configuration Release clean build
```

### 4. Create Signed Zip

```bash
cd ~/Library/Developer/Xcode/DerivedData/Notchification-*/Build/Products/Release
zip -r -y Notchification-X.X.XX.zip Notchification.app
```

### 5. Sign with Sparkle

```bash
# Find sign_update tool
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" | head -1

# Sign the zip (outputs edSignature and length)
/path/to/sign_update Notchification-X.X.XX.zip
```

### 6. Update BOTH appcast.xml files

**IMPORTANT**: There are TWO appcast.xml files that must be updated:

1. **Notchification repo** (`./appcast.xml`) - for reference/backup
2. **Featurefest folder** (`~/Documents/workspaces/code/web/featurefest/notchification/appcast.xml`) - **THIS IS THE ONE SPARKLE READS**

The featurefest appcast.xml is served at `https://featurefest.dev/notchification/appcast.xml` and is what the app actually checks for updates. If you only update the repo's appcast.xml, users won't see the update!

Add new `<item>` at the top of BOTH files with:
- Version number
- Publication date
- EdDSA signature from step 5
- File length from step 5
- Release notes

### 7. Upload and Deploy

1. Copy zip to the featurefest website folder:
   ```bash
   cp ~/Library/Developer/Xcode/DerivedData/Notchification-*/Build/Products/Release/Notchification-X.X.XX.zip \
      ~/Documents/workspaces/code/web/featurefest/notchification/
   ```
2. Deploy featurefest:
   ```bash
   cd ~/Documents/workspaces/code/web/featurefest && firebase deploy --only hosting
   ```
3. Verify the update is live:
   ```bash
   curl -s "https://featurefest.dev/notchification/appcast.xml" | head -10
   ```
4. Copy zip to homeofficesinternational (public download site):
   ```bash
   cp ~/Library/Developer/Xcode/DerivedData/Notchification-*/Build/Products/Release/Notchification-X.X.XX.zip \
      ~/Documents/workspaces/code/web/homeofficesinternational/notchification/
   ```
5. Deploy homeofficesinternational:
   ```bash
   cd ~/Documents/workspaces/code/web/homeofficesinternational && netlify deploy --prod --dir .
   ```
   Or just commit and push to GitHub (auto-deploys via Netlify).
6. Copy zip to Dropbox for backup
7. Commit version bump and appcast.xml in Notchification repo
8. Push to GitHub

### Checklist

- [ ] CEO welcome message updated in WelcomeMessageView.swift
- [ ] Version bumped
- [ ] Release built and signed
- [ ] **BOTH** appcast.xml files updated (repo AND featurefest)
- [ ] Zip copied to `~/Documents/workspaces/code/web/featurefest/notchification/`
- [ ] Featurefest deployed with `firebase deploy --only hosting`
- [ ] Verified appcast.xml is live with curl
- [ ] Zip copied to `~/Documents/workspaces/code/web/homeofficesinternational/notchification/`
- [ ] Homeofficesinternational deployed (Netlify CLI or GitHub push)
- [ ] Committed and pushed
