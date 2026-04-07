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

## Test

```bash
xcodebuild test -project TouchPoint.xcodeproj -scheme TouchPoint -destination 'platform=macOS'
```

## Architecture

- `AppDelegate.swift` — App lifecycle, menu bar, global hotkey (Cmd+Shift+T), size controls, cursor hiding
- `OverlayWindow.swift` — NSPanel overlay that follows the mouse with click animations
- `CursorHider.swift` — CGS private API wrapper for hiding/showing the system cursor

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

## Important Notes

- Never use CGS private APIs to *replace* the system cursor image — only hide/show. The reset APIs don't reliably restore the cursor on macOS 26.
- The app requires Accessibility permission for global event monitoring.
- `CGDisplayHideCursor` only works globally when `SetsCursorInBackground` is set via CGS.
- Private API declarations use `@_silgen_name` and are isolated in `CursorHider.swift`.
- Debug builds use automatic signing. Release builds use manual Developer ID signing with hardened runtime.
