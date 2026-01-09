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

Releases are hosted on featurefest.dev and delivered via Sparkle auto-update.

### 1. Update version numbers

Update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj`:

```bash
# Example: bumping to 1.0.24
sed -i '' 's/MARKETING_VERSION = 1.0.23/MARKETING_VERSION = 1.0.24/g' Notchification.xcodeproj/project.pbxproj
sed -i '' 's/CURRENT_PROJECT_VERSION = 23/CURRENT_PROJECT_VERSION = 24/g' Notchification.xcodeproj/project.pbxproj
```

**Important:** The `CURRENT_PROJECT_VERSION` (build number) must match the `sparkle:version` in the appcast.

### 2. Commit the version bump

```bash
git add -A && git commit -m "Release v1.0.X"
```

### 3. Archive and export

```bash
# Archive
xcodebuild -scheme Notchification -configuration Release \
  -archivePath /tmp/Notchification.xcarchive archive

# Export
xcodebuild -exportArchive \
  -archivePath /tmp/Notchification.xcarchive \
  -exportPath /tmp/NotchificationExport \
  -exportOptionsPlist /dev/stdin << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
</dict>
</plist>
EOF
```

### 4. Create and sign the zip

```bash
# Create zip
cd /tmp/NotchificationExport
zip -r Notchification-1.0.X.zip Notchification.app

# Sign with Sparkle (outputs edSignature and length)
~/Library/Developer/Xcode/DerivedData/Notchification-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
  Notchification-1.0.X.zip
```

Save the `edSignature` and `length` from the output.

### 5. Copy to featurefest

```bash
cp /tmp/NotchificationExport/Notchification-1.0.X.zip \
  ~/Documents/workspaces/code/web/featurefest/notchification/
```

### 6. Update appcast.xml

Edit `~/Documents/workspaces/code/web/featurefest/notchification/appcast.xml`:

Add a new `<item>` at the top with:
- `sparkle:version` = build number (e.g., 24)
- `sparkle:shortVersionString` = marketing version (e.g., 1.0.24)
- `sparkle:edSignature` = signature from step 4
- `length` = file size from step 4

### 7. Push and deploy

```bash
# Push Notchification repo
git push

# Commit and push featurefest
cd ~/Documents/workspaces/code/web/featurefest
git add notchification/appcast.xml
git commit -m "Release Notchification v1.0.X"
git push

# Deploy to Firebase
firebase deploy --only hosting
```

## How Updates Work

The app uses Sparkle for automatic updates:

1. Sparkle checks `https://featurefest.dev/notchification/appcast.xml` for new versions
2. Compares the `sparkle:version` (build number) with the installed version
3. If newer, downloads and installs the update automatically

## License

MIT
