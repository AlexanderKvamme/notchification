# Notchification

A macOS menu bar app that displays visual indicators in the notch area when development tools are actively building.

## Features

- Monitors Claude CLI, Xcode, and Android Studio build processes
- Animated notch indicator with per-app colors
- Confetti celebration when builds complete
- Optional completion sound
- Update notifications via Sparkle (redirects to download page)

## Requirements

- macOS 14.0+
- Mac with notch display (works on other Macs too)

## Installation

Download the latest release from [Releases](https://github.com/AlexanderKvamme/notchification/releases).

## Building from Source

1. Clone the repo
2. Open `Notchification.xcodeproj` in Xcode
3. Build and run

## Releasing a New Version

### 1. Update version number

In Xcode: Project → Target → General → Version and Build

### 2. Archive and Export (Notarized)

1. **Archive**: Product → Archive
2. **Export**: Distribute App → Direct Distribution → Upload (auto-notarizes)
3. Wait for notarization (1-5 minutes)
4. Click "Export Notarized App" and save to Desktop

### 3. Create zip

Right-click the exported `Notchification.app` → Compress

Rename to include version:
```bash
mv ~/Desktop/Notchification.zip ~/Desktop/Notchification-1.0.X.zip
```

### 4. Create GitHub Release

```bash
gh release create v1.0.X ~/Desktop/Notchification-1.0.X.zip \
  --title "v1.0.X" \
  --notes "Release notes here"
```

### 5. Update appcast.xml

Update `appcast.xml` with the new version:
```xml
<sparkle:version>X</sparkle:version>
<sparkle:shortVersionString>1.0.X</sparkle:shortVersionString>
<link>https://github.com/AlexanderKvamme/notchification/releases/tag/v1.0.X</link>
```

### 6. Push changes

```bash
git add appcast.xml
git commit -m "Update appcast for v1.0.X"
git push
```

## How Updates Work

The app uses Sparkle for update notifications, but with a simplified "informational-only" approach:

1. Sparkle checks `appcast.xml` for new versions
2. If a newer version is found, it opens the GitHub releases page
3. Users download and install manually (no auto-install)

This avoids complexities with code signing and macOS Gatekeeper while still providing update notifications.

## License

MIT
