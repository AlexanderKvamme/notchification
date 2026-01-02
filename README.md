# Notchification

A macOS menu bar app that displays visual indicators in the notch area when development tools are actively building.

## Features

- Monitors Claude CLI, Xcode, and Android Studio build processes
- Animated notch indicator with per-app colors
- Confetti celebration when builds complete
- Optional completion sound
- Auto-updates via Sparkle

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

In Xcode, update:
- `MARKETING_VERSION` (e.g., 1.0.3)
- `CURRENT_PROJECT_VERSION` (increment build number)

Or via command line:
```bash
# In project.pbxproj, replace all occurrences
MARKETING_VERSION = 1.0.3;
CURRENT_PROJECT_VERSION = 3;
```

### 2. Build Release

```bash
xcodebuild -scheme Notchification -configuration Release clean build
```

### 3. Zip and Sign

```bash
cd ~/Library/Developer/Xcode/DerivedData/Notchification-*/Build/Products/Release

# Create zip
ditto -c -k --keepParent Notchification.app Notchification-1.0.3.zip

# Sign with Sparkle (outputs signature and length)
/tmp/bin/sign_update Notchification-1.0.3.zip
```

Note: If you don't have the Sparkle tools, download from:
```bash
cd /tmp && curl -L -o sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz" && tar -xf sparkle.tar.xz
```

### 4. Update appcast.xml

Update `appcast.xml` with:
- New version numbers (`sparkle:version` and `sparkle:shortVersionString`)
- New `sparkle:edSignature` from sign_update output
- New `length` from sign_update output
- Updated download URL

### 5. Create GitHub Release

```bash
# Copy zip to project folder
cp Notchification-1.0.3.zip /path/to/project/

# Push updated appcast
git add appcast.xml
git commit -m "Update appcast for v1.0.3"
git push

# Create release
gh release create v1.0.3 Notchification-1.0.3.zip --title "v1.0.3" --notes "Release notes here"
```

## Sparkle Keys

The EdDSA private key is stored in your macOS Keychain. The public key is in `Info.plist` under `SUPublicEDKey`.

To generate new keys (only if needed):
```bash
/tmp/bin/generate_keys
```

## License

MIT
