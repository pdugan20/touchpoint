import Cocoa

/// Hides and shows the system cursor globally using CGS private APIs.
/// This is the same technique used by Cursorcerer — it sets a WindowServer
/// connection property that allows CGDisplayHideCursor to work even when
/// other apps are in the foreground.
enum CursorHider {
  // MARK: - CGS Private API

  @_silgen_name("CGSSetConnectionProperty")
  private static func CGSSetConnectionProperty(
    _ connection: Int,
    _ targetConnection: Int,
    _ key: CFString,
    _ value: CFTypeRef
  )

  @_silgen_name("_CGSDefaultConnection")
  private static func CGSDefaultConnection() -> Int

  // MARK: - State

  private(set) static var isHidden = false

  // MARK: - Public

  static func hide() {
    let conn = CGSDefaultConnection()
    CGSSetConnectionProperty(conn, conn, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    CGDisplayHideCursor(CGMainDisplayID())
    isHidden = true
  }

  static func show() {
    guard isHidden else { return }
    CGDisplayShowCursor(CGMainDisplayID())
    isHidden = false
  }
}
