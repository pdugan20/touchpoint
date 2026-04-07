import Testing
@testable import TouchPoint

@Suite("CursorHider")
struct CursorHiderTests {
  @Test("starts not hidden")
  func initialState() {
    #expect(!CursorHider.isHidden)
  }

  @Test("show is idempotent when not hidden")
  func showWhenNotHidden() {
    CursorHider.show()
    #expect(!CursorHider.isHidden)
  }
}
