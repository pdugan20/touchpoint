# TouchPoint

![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

A minimal macOS menu bar app that replaces the system cursor with a soft, translucent circle overlay — designed for screen recordings, presentations, and demos where you want a cleaner pointer.

## Features

- Translucent circle overlay follows the cursor at ~120Hz
- Click state animation (opacity dims, shadow disappears on press)
- Hides the system cursor when active
- Global hotkey: **Cmd+Shift+T** to toggle on/off
- Menu bar icon indicates active/inactive state
- Lives entirely in the menu bar — no Dock icon

## Install

1. Clone the repo and open `TouchPoint.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. Grant Accessibility permission when prompted (required for global click monitoring)

## Usage

- **Cmd+Shift+T** — Toggle the overlay on/off
- Click the menu bar icon for the toggle menu
- The system cursor is automatically hidden when the overlay is active

## How it works

TouchPoint creates a borderless, click-through `NSPanel` at the screen-saver window level that tracks the mouse position via a high-frequency timer. The cursor is hidden using `CGDisplayHideCursor` with the `SetsCursorInBackground` CGS property to ensure it stays hidden even when other apps are in the foreground.

## License

[MIT](LICENSE)
