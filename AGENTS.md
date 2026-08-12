# TouchPoint

## Work modes

- Default to exploration for design iterations, prototypes, and small changes. Make focused edits directly; do not require a formal spec, separate plan, worktree, or TDD.
- Apply production rigor when the user explicitly asks to ship, harden, prepare a release, or use strict TDD. Match verification to risk and obey any stronger test requirements below.
- Ask before deployments, production-data changes, live service mutations, schema migrations, or security-rule changes.

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

## Test

```bash
xcodebuild test -project TouchPoint.xcodeproj -scheme TouchPoint -destination 'platform=macOS'
```

## Architecture

- `AppDelegate.swift` — App lifecycle, menu bar, global hotkeys (Cmd+Shift+T toggle, Cmd+Shift+R record), size controls, cursor hiding
- `OverlayWindow.swift` — NSPanel overlay that follows the mouse with click animations
- `CursorHider.swift` — CGS private API wrapper for hiding/showing the system cursor
- `SimulatorRecorder.swift` — ScreenCaptureKit recording of the booted iOS Simulator + overlay panel at native device resolution; crop follows the window mid-recording
- `SimulatorCapture.swift` — setup helpers: native geometry via `simctl io enumerate`, shareable-content lookup, window→screen-rect math
- `tools/simrec.swift` — standalone CLI variant of the recorder (not part of the app target; compile with `swiftc`)

Recording requires Screen Recording TCC for the app (or, for the CLI, whatever terminal hosts it). The capture filter binds to specific windows at start; `refreshContentFilter()` re-resolves it when the overlay panel is recreated (size changes give it a new window ID).

## Code Style

- **Airbnb Swift Style Guide** enforced via SwiftLint + SwiftFormat
- Config hierarchy: `.swiftlint-airbnb.yml` (parent) -> `.swiftlint.yml`
- SwiftFormat config: `.swiftformat` (Airbnb rules)
- 2-space indentation, 120 char warning, 150 char error
- Run `swiftformat TouchPoint/Sources/` before committing
- Run `swiftlint lint --strict` to check

## Release

Tag a version to trigger the release workflow:

```bash
git tag v1.0.0 && git push --tags
```

The CI workflow will:
1. Sign the app with Developer ID Application certificate
2. Submit to Apple for notarization
3. Staple the notarization ticket
4. Package as a DMG
5. Create a GitHub Release with the DMG attached

### Signing setup

Release builds use manual signing with Developer ID. The following GitHub secrets are required:

- `DEVELOPER_ID_CERT_BASE64` — .p12 certificate, base64-encoded
- `DEVELOPER_ID_CERT_PASSWORD` — .p12 export password
- `NOTARY_API_KEY` — App Store Connect API key (.p8 contents)
- `NOTARY_API_KEY_ID` — API key ID
- `NOTARY_API_ISSUER` — API issuer UUID

Local credentials are stored in `~/private-keys/`.

## Code Review Rules

- Flag cursor-management paths that replace the system cursor through private CGS APIs or
  can exit/crash without restoring visibility after this app hid it.
- Flag recording changes that capture a broader display/window region than the selected
  Simulator and overlay, or that persist/share recordings without explicit user action.
- Flag stale ScreenCaptureKit window identifiers after overlay recreation, coordinate
  transforms that ignore screen origin/scale, or permission failures that leave global
  input/cursor state modified.

## Important Notes

- Never use CGS private APIs to *replace* the system cursor image — only hide/show. The reset APIs don't reliably restore the cursor on macOS 26.
- The app requires Accessibility permission for global event monitoring.
- `CGDisplayHideCursor` only works globally when `SetsCursorInBackground` is set via CGS.
- Private API declarations use `@_silgen_name` and are isolated in `CursorHider.swift`.
- Debug builds use automatic signing. Release builds use manual Developer ID signing with hardened runtime.
