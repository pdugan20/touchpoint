import Cocoa
import ScreenCaptureKit

enum RecorderError: LocalizedError {
  case alreadyRecording
  case noBootedSimulator
  case noSimulatorWindow
  case windowDoesNotLookLikeBareScreen
  case setupFailed(String)

  var errorDescription: String? {
    switch self {
    case .alreadyRecording:
      return "A recording is already in progress."
    case .noBootedSimulator:
      return "No booted simulator found. Boot one in the Simulator app first."
    case .noSimulatorWindow:
      return "Could not find an on-screen Simulator window."
    case .windowDoesNotLookLikeBareScreen:
      return "The Simulator window doesn't look like a bare device screen. "
        + "Turn off Simulator → Window → Show Device Bezels."
    case .setupFailed(let message):
      return message
    }
  }
}

struct NativeGeometry {
  let width: Int
  let height: Int
}

/// Setup helpers for locating the booted Simulator and its on-screen geometry.
enum SimulatorCapture {
  /// The booted device's screen size in pixels, from `simctl io enumerate`.
  static func readNativeGeometry() throws -> NativeGeometry {
    let enumerate = Process()
    let output = Pipe()
    enumerate.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    enumerate.arguments = ["simctl", "io", "booted", "enumerate"]
    enumerate.standardOutput = output
    enumerate.standardError = FileHandle.nullDevice
    do {
      try enumerate.run()
    } catch {
      throw RecorderError.noBootedSimulator
    }
    enumerate.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let description = String(bytes: data, encoding: .utf8) else {
      throw RecorderError.noBootedSimulator
    }
    let pattern = #"(?s)Name:\s+LCD.*?Pixel Size:\s+\{(\d+),\s*(\d+)\}"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
      let widthRange = Range(match.range(at: 1), in: description),
      let heightRange = Range(match.range(at: 2), in: description),
      let width = Int(description[widthRange]),
      let height = Int(description[heightRange])
    else {
      throw RecorderError.noBootedSimulator
    }

    return NativeGeometry(width: width, height: height)
  }

  static func fetchShareableContent() throws -> SCShareableContent {
    var result: Result<SCShareableContent, Error>?
    let semaphore = DispatchSemaphore(value: 0)
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
      if let content {
        result = .success(content)
      } else {
        result = .failure(error ?? RecorderError.setupFailed("Could not enumerate windows."))
      }
      semaphore.signal()
    }
    semaphore.wait()

    switch result! {
    case .success(let content):
      return content
    case .failure(let error):
      throw RecorderError.setupFailed(
        "Could not enumerate windows: \(error.localizedDescription) "
          + "If this is a permissions error, grant Screen Recording to TouchPoint in "
          + "System Settings → Privacy & Security."
      )
    }
  }

  /// The device screen sub-rect of the Simulator window, in top-left-origin
  /// screen points. The window is title-bar chrome on top plus the screen.
  static func deviceScreenRect(windowFrame: CGRect, native: NativeGeometry) -> CGRect? {
    let expectedScreenHeight = windowFrame.width * CGFloat(native.height) / CGFloat(native.width)
    let chromeHeight = windowFrame.height - expectedScreenHeight
    guard expectedScreenHeight <= windowFrame.height + 2, chromeHeight >= 20, chromeHeight <= 100 else {
      return nil
    }

    return CGRect(
      x: windowFrame.minX,
      y: windowFrame.maxY - expectedScreenHeight,
      width: windowFrame.width,
      height: expectedScreenHeight
    )
  }
}
