# TouchPoint

macOS menu bar app that replaces the system cursor with a translucent circle overlay.

## Build

```bash
xcodebuild -project TouchPoint.xcodeproj -scheme TouchPoint -configuration Debug build
```

Or open `TouchPoint.xcodeproj` in Xcode and build (Cmd+B).

## Setup

```bash
brew bundle          # Install SwiftLint, SwiftFormat, Periphery, pre-commit
pre-commit install   # Install git hooks
```

## Architecture

- `AppDelegate.swift` — App lifecycle, menu bar, global hotkey (Cmd+Shift+T), cursor hiding
- `OverlayWindow.swift` — NSPanel overlay that follows the mouse with click animations
- `CursorHider.swift` — CGS private API wrapper for hiding/showing the system cursor

## Code Style

- **Airbnb Swift Style Guide** enforced via SwiftLint + SwiftFormat
- Config hierarchy: `.swiftlint-airbnb.yml` (parent) -> `.swiftlint.yml`
- SwiftFormat config: `.swiftformat` (Airbnb rules)
- 2-space indentation, 120 char warning, 150 char error
- Run `swiftformat TouchPoint/Sources/` before committing
- Run `swiftlint lint --strict` to check

## Important Notes

- Never use CGS private APIs to *replace* the system cursor image — only hide/show. The reset APIs don't reliably restore the cursor on macOS 26.
- The app requires Accessibility permission for global event monitoring.
- `CGDisplayHideCursor` only works globally when `SetsCursorInBackground` is set via CGS.
- Private API declarations use `@_silgen_name` and are isolated in `CursorHider.swift`.

## Release

Tag a version to trigger the release workflow:

```bash
git tag v1.0.0 && git push --tags
```

This builds a DMG and creates a GitHub Release automatically.
