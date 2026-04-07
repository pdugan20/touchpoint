import Testing
@testable import TouchPoint

@Suite("OverlayWindow Configuration")
struct OverlayWindowTests {
  @Test("circle size is 40pt")
  func circleSize() {
    #expect(OverlayWindow.circleSize == 40)
  }

  @Test("window size is 70pt")
  func windowSize() {
    #expect(OverlayWindow.windowSize == 70)
  }

  @Test("window is larger than circle for shadow room")
  func windowLargerThanCircle() {
    #expect(OverlayWindow.windowSize > OverlayWindow.circleSize)
  }
}
