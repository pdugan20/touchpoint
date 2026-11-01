# Threat model

## Scope and protected assets

TouchPoint is a macOS 26+ pointer-overlay and Simulator-recording app with a separate CLI (`README.md`, `TouchPoint/Resources/Info.plist`, `tools/simrec.swift`). Protect captured pictures and sound, recording files, desktop usability, release integrity, and signing credentials. Movies are saved locally (`TouchPoint/Sources/SimulatorRecorderStreams.swift`, `tools/simrec.swift`).

Releases use Developer ID signing, hardened runtime, Apple notarization, and GitHub DMGs (`TouchPoint.xcodeproj/project.pbxproj`, `.github/workflows/release.yml`). The runtime has local capture and output, with no network client or server (`TouchPoint/Sources/`, `tools/simrec.swift`).

## Entry points

- Users invoke menus/hotkeys; mouse location and left-button events drive the overlay (`TouchPoint/Sources/AppDelegate.swift`, `TouchPoint/Sources/OverlayWindow.swift`).
- The local account supplies circle-size preferences, CLI arguments, and termination signals (`TouchPoint/Sources/AppDelegate.swift`, `tools/simrec.swift`).
- Apps supply window metadata and media through macOS. `/usr/bin/xcrun simctl io booted enumerate` supplies device dimensions (`TouchPoint/Sources/SimulatorCapture.swift`, `TouchPoint/Sources/SimulatorRecorder.swift`, `TouchPoint/Sources/SimulatorRecorderStreams.swift`).
- Contributors supply code/PR metadata; tags trigger releases. CI downloads actions, Homebrew and npm tools; releases contact Apple and GitHub (`.github/workflows/ci.yml`, `.github/workflows/pr-lint.yml`, `.github/workflows/release.yml`).

## Trust boundaries and assumptions

The local user session and macOS permissions are the authorization boundary: Accessibility supports global click detection, and Screen Recording authorizes capture. The CLI relies on its terminal host's capture permission (`AGENTS.md`). Permission grants are not consent for every source. File/process operations must remain narrow in this unsandboxed app (`TouchPoint/Resources/TouchPoint.entitlements`).

Validate capture metadata before selection, cropping, and encoding. Preserve Simulator and own-process overlay identity checks; require equivalent CLI identity assurance (`TouchPoint/Sources/SimulatorRecorder.swift`, `tools/simrec.swift`). Local preferences, tool output, filesystem state, and callback timing require validation even within an authorized session (`TouchPoint/Sources/AppDelegate.swift`, `TouchPoint/Sources/SimulatorCapture.swift`).

Release code gains signing and publication authority. Require reviewed source/tools; isolate PR metadata handling from privileged execution (`.github/workflows/release.yml`, `.github/workflows/pr-lint.yml`).

## Sensitive data and privileged actions

Media, frames, and paths can expose session content. Capture changes, file replacement, cursor hiding, and signing are privileged. Keep media local, diagnostics minimal, and overlays click-through; confine CGS calls to hide/show with restoration (`TouchPoint/Sources/SimulatorRecorder.swift`, `tools/simrec.swift`, `TouchPoint/Sources/OverlayWindow.swift`, `TouchPoint/Sources/CursorHider.swift`). Restrict signing/notarization material to releases (`.github/workflows/release.yml`).

## Principal threats and required controls

- Unintended disclosure: enforce intended video and audio scope, clear recording status, and permission failure handling. Treat audio scope independently from the video crop (`TouchPoint/Sources/SimulatorRecorder.swift`, `TouchPoint/Sources/SimulatorRecorderStreams.swift`).
- Capture persisting beyond user intent: stop both streams and release writers, buffers, and timers on partial startup, stream failure, stop, and quit. Serialize lifecycle transitions and finish output before termination (`TouchPoint/Sources/SimulatorRecorder.swift`, `TouchPoint/Sources/AppDelegate.swift`).
- Local data loss or resource exhaustion: require explicit overwrite consent, safe destination handling, finite bounded geometry and preferences, bounded subprocess/callback waits, and actionable writer failures (`tools/simrec.swift`, `TouchPoint/Sources/SimulatorCapture.swift`, `TouchPoint/Sources/AppDelegate.swift`).
- Release compromise: retain pinned action revisions, least-privilege tokens, hardened signing, notarization, protected release authority, and credential cleanup on every exit. Review downloaded build tooling and tag-derived version data as inputs (`.github/workflows/`, `TouchPoint.xcodeproj/project.pbxproj`).

## Review priorities

Review capture scope/lifecycle first, destination and numeric validation second, release execution third. Extend geometry tests with boundary/failure cases (`TouchPointTests/SimulatorCaptureTests.swift`).

## Uncertain assumptions

Local files cannot confirm deployed TCC grants (`AGENTS.md`), release-tag protections or secret access policies (`.github/workflows/release.yml`), or Desktop/output-directory permissions and external syncing (`TouchPoint/Sources/SimulatorRecorderStreams.swift`, `tools/simrec.swift`). Actual capture behavior across displays and multiple Simulator devices also requires runtime confirmation (`TouchPoint/Sources/SimulatorRecorder.swift`, `TouchPoint/Sources/SimulatorRecorderStreams.swift`).

## When to update this model

Update for capture, permission, input, storage, network, cursor, dependency, or release changes; reassess both recorders (`TouchPoint/Sources/`, `tools/simrec.swift`, `.github/workflows/`, `TouchPoint/Resources/`).
