# Notchification - Claude Code Notes

## IMPORTANT: Debug Output Rules

**NEVER REMOVE these debug statements** - they are essential for debugging Claude detection:

1. In `ClaudeDetector.swift`, the debug logging must always print the **last 5 lines** of terminal content when `debugClaude` is enabled
2. Keep all `logger.debug` and `print` statements related to Claude detection
3. When debugging Claude detection issues, always check:
   - Is `debugClaude` enabled in DebugSettings?
   - What does the terminal content actually show?
   - Are the last 5 lines being printed?

## ClaudeDetector Architecture

The detector:
- Uses AppleScript to read iTerm2/Terminal.app content
- Looks for the `searchPattern` (built from ["esc", "to", "interrupt"]) in the last 10 non-empty lines
- The pattern is built at runtime to avoid false positives when source code is visible in terminal
- Has a 2-second timeout on osascript calls
- Uses a serial queue to prevent overlapping checks

## Debugging Checklist

When Claude detection isn't working:
1. Enable `debugClaude` in settings
2. Check Console.app for logs from "ClaudeDetector"
3. Verify Accessibility permissions for the app
4. Check if iTerm2/Terminal is actually running
5. Look at the actual terminal content being read
6. Check the permissions output on launch (printed in Xcode console in DEBUG builds)
