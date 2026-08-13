# TouchPoint

[![Release](https://img.shields.io/github/v/release/pdugan20/touchpoint?logo=github&logoColor=white)](https://github.com/pdugan20/touchpoint/releases/latest)
[![CI](https://github.com/pdugan20/touchpoint/actions/workflows/ci.yml/badge.svg)](https://github.com/pdugan20/touchpoint/actions/workflows/ci.yml)

TouchPoint is a macOS menu bar app that replaces the system pointer with a
translucent touch-style circle. It is built for recording iOS Simulator
interactions, prototype demos, and presentations.

## Install

TouchPoint requires macOS 26 or newer.

Download the latest DMG from
[GitHub Releases](https://github.com/pdugan20/touchpoint/releases/latest),
open it, and drag TouchPoint to Applications. Release builds are signed and
notarized.

TouchPoint runs in the menu bar and does not appear in the Dock. It requires
Accessibility permission for global click detection.

## Usage

| Action | Shortcut |
| --- | --- |
| Toggle TouchPoint | `Cmd+Shift+T` |
| Start or stop Simulator recording | `Cmd+Shift+R` |
| Increase or decrease circle size | `Cmd+Shift+=` / `Cmd+Shift+-` |
| Reset circle size | `Cmd+Shift+0` |

Size controls are also available from the TouchPoint menu and persist between
launches.

## Simulator recording

Press `Cmd+Shift+R` to record the booted iOS Simulator at native device
resolution, up to 60 fps, with the TouchPoint overlay and click animations.
The finished HEVC `.mov` is saved to the Desktop and revealed in Finder.

Before recording:

- Turn off Simulator → Window → Show Device Bezels.
- Grant TouchPoint Screen Recording permission.
- Use Simulator → Window → Pixel Accurate.

## Development

Requirements are Xcode 26 or newer and Homebrew.

```bash
brew bundle
pre-commit install
```

Build and test:

```bash
xcodebuild -project TouchPoint.xcodeproj -scheme TouchPoint -configuration Debug build
xcodebuild test -project TouchPoint.xcodeproj -scheme TouchPoint -destination 'platform=macOS'
```

Run the repository checks:

```bash
pre-commit run --all-files
```
