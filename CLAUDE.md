# TouchPoint

macOS menu bar app that replaces the system cursor with a translucent circle overlay.

## Build

Open `TouchPoint.xcodeproj` in Xcode and build (Cmd+B), or:

```bash
xcodebuild -project TouchPoint.xcodeproj -scheme TouchPoint -configuration Debug build
```

## Architecture

- `AppDelegate.swift` — App lifecycle, menu bar, global hotkey (Cmd+Shift+T), cursor hiding
- `OverlayWindow.swift` — NSPanel overlay that follows the mouse with click animations
- `CursorHider.swift` — CGS private API wrapper for hiding/showing the system cursor

## Conventions

- Swift style enforced by SwiftLint (`.swiftlint.yml`)
- Use `MARK:` comments to organize sections within files
- Private API declarations use `@_silgen_name` and are isolated in `CursorHider.swift`
- The overlay uses Core Animation layers, not images

## Important notes

- Never use CGS private APIs to *replace* the system cursor image — only hide/show. See memory: the reset APIs don't reliably restore the cursor on macOS 26.
- The app requires Accessibility permission for global event monitoring.
- `CGDisplayHideCursor` only works globally when `SetsCursorInBackground` is set via CGS.
