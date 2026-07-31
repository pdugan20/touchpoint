# touchpoint

[![CI](https://github.com/pdugan20/touchpoint/actions/workflows/ci.yml/badge.svg)](https://github.com/pdugan20/touchpoint/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/pdugan20/touchpoint?logo=github&logoColor=white)](https://github.com/pdugan20/touchpoint/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26+-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?logo=opensourceinitiative&logoColor=white)](https://opensource.org/licenses/MIT)

A macOS menu bar app that replaces the system cursor with a touch-style circle overlay — like the touch cursor in Figma's prototype mode, but system-wide. Built for recording iOS Simulator interactions, device prototyping demos, and presentations.

## Install

Download the latest DMG from [Releases](https://github.com/pdugan20/touchpoint/releases/latest), open it, and drag TouchPoint to Applications. The app is signed and notarized.

## Usage

- **Cmd+Shift+T** — Toggle the overlay on/off
- **Cmd+Shift+R** — Record the booted iOS Simulator (press again to stop)
- **Cmd+Shift+=/-** — Increase/decrease circle size
- **Cmd+Shift+0** — Reset to default size

## Simulator recording

Cmd+Shift+R records the booted iOS Simulator at **native device resolution**
(e.g. 1206×2622 on iPhone 17 Pro) at up to 60fps, with the live TouchPoint
cursor — press animations included — captured exactly as you see it. The
finished HEVC `.mov` lands on your Desktop and is revealed in Finder.

Requirements:

- A booted simulator with **device bezels off** (Simulator → Window → Show
  Device Bezels unchecked). The recorder errors with instructions otherwise.
- **Screen Recording permission** for TouchPoint (macOS prompts on first use).
- For a pixel-perfect 1:1 capture, put the Simulator window in **Pixel
  Accurate** mode (Cmd+3). The recording is upscaled from the on-screen size
  otherwise. On smaller displays, hide the Dock if Pixel Accurate is greyed
  out.

Starting a recording turns the overlay on automatically, and the crop follows
the Simulator window if you move or resize it mid-take. A standalone CLI
variant lives at `tools/simrec.swift`:

```bash
swiftc -O tools/simrec.swift -o simrec && ./simrec --force ~/Desktop/demo.mov
```
