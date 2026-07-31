import CoreGraphics
import Testing
@testable import TouchPoint

@Suite("SimulatorCapture Geometry")
struct SimulatorCaptureTests {
  // iPhone 17 Pro: 1206x2622 native. A bezel-free Simulator window is the
  // screen plus 20-100pt of title-bar chrome on top.
  private let native = NativeGeometry(width: 1206, height: 2622)

  @Test("crops title bar from a bezel-free window")
  func cropsTitleBar() {
    let window = CGRect(x: 100, y: 50, width: 603, height: 1311 + 40)
    let screen = SimulatorCapture.deviceScreenRect(windowFrame: window, native: native)
    #expect(screen != nil)
    #expect(screen?.width == 603)
    #expect(screen?.height == 1311)
    // Screen is bottom-anchored: chrome occupies the top of the window.
    #expect(screen?.maxY == window.maxY)
    #expect(screen?.minX == window.minX)
  }

  @Test("pixel-accurate window maps 1:1")
  func pixelAccurateWindow() {
    let window = CGRect(x: 0, y: 24, width: 603, height: 1311 + 28)
    let screen = SimulatorCapture.deviceScreenRect(windowFrame: window, native: native)
    #expect(screen?.width == 603)
    #expect(screen?.height == 1311)
  }

  @Test("rejects a window with device bezels")
  func rejectsBezels() {
    // Bezels add width without adding chrome height, so the expected screen
    // height overshoots the window: chrome comes out negative.
    let window = CGRect(x: 0, y: 0, width: 700, height: 1400)
    #expect(SimulatorCapture.deviceScreenRect(windowFrame: window, native: native) == nil)
  }

  @Test("rejects a window with excessive chrome")
  func rejectsExcessiveChrome() {
    let window = CGRect(x: 0, y: 0, width: 603, height: 1311 + 150)
    #expect(SimulatorCapture.deviceScreenRect(windowFrame: window, native: native) == nil)
  }
}
