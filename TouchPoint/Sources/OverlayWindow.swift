import Cocoa
import QuartzCore

class OverlayWindow: NSPanel {
  static let circleSize: CGFloat = 40
  static let windowSize: CGFloat = 70

  private let circleLayer = CALayer()

  init() {
    let s = Self.windowSize
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: s, height: s),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .screenSaver
    isOpaque = false
    backgroundColor = .clear
    ignoresMouseEvents = true
    hasShadow = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isMovableByWindowBackground = false

    setupLayers()
  }

  private func setupLayers() {
    let root = contentView!
    root.wantsLayer = true
    root.layer?.masksToBounds = false

    let s = Self.windowSize
    let cs = Self.circleSize
    let offset = (s - cs) / 2

    circleLayer.frame = NSRect(x: offset, y: offset, width: cs, height: cs)
    circleLayer.cornerRadius = cs / 2
    circleLayer.backgroundColor = NSColor(red: 0.953, green: 0.953, blue: 0.953, alpha: 0.8).cgColor
    circleLayer.borderWidth = 1.5
    circleLayer.borderColor = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0).cgColor

    circleLayer.shadowColor = NSColor.black.cgColor
    circleLayer.shadowOpacity = Float(0.09)
    circleLayer.shadowOffset = CGSize(width: 0, height: -4)
    circleLayer.shadowRadius = 4
    circleLayer.masksToBounds = false

    root.layer?.addSublayer(circleLayer)
  }

  func moveToMouse() {
    let mouse = NSEvent.mouseLocation
    let s = Self.windowSize
    setFrameOrigin(NSPoint(x: mouse.x - s / 2, y: mouse.y - s / 2))
  }

  func setPressed(_ pressed: Bool) {
    CATransaction.begin()
    CATransaction.setAnimationDuration(pressed ? 0.06 : 0.15)
    circleLayer.backgroundColor = NSColor(red: 0.953, green: 0.953, blue: 0.953, alpha: pressed ? 0.5 : 0.8).cgColor
    circleLayer.borderColor = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: pressed ? 0.5 : 1.0).cgColor
    circleLayer.shadowOpacity = pressed ? 0 : Float(0.09)
    circleLayer.shadowRadius = pressed ? 0 : 4
    CATransaction.commit()
  }
}
