import Carbon
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var overlayWindow: OverlayWindow?
  private var isActive = false
  private var hotKeyRef: EventHotKeyRef?

  private var trackingTimer: DispatchSourceTimer?
  private var clickDownMonitor: Any?
  private var clickUpMonitor: Any?

  private static let sizeKey = "circleSize"
  private static let defaultSize: CGFloat = 40
  private static let sizeStep: CGFloat = 5
  private static let minSize: CGFloat = 15
  private static let maxSize: CGFloat = 80

  private var circleSize: CGFloat {
    get {
      let saved = UserDefaults.standard.double(forKey: Self.sizeKey)
      return saved > 0 ? saved : Self.defaultSize
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.sizeKey)
    }
  }

  // MARK: - App Lifecycle

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }

  func applicationDidFinishLaunching(_: Notification) {
    setupStatusItem()
    registerHotKey()
  }

  // MARK: - Menu Bar

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    updateStatusIcon()
    statusItem?.menu = buildMenu()
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()

    menu.addItem(NSMenuItem(title: "Toggle TouchPoint", action: #selector(toggleOverlay), keyEquivalent: "t"))
    menu.items.last?.keyEquivalentModifierMask = [.command, .shift]

    menu.addItem(NSMenuItem.separator())

    let sizeMenu = NSMenu()

    let increaseItem = NSMenuItem(title: "Increase", action: #selector(increaseSize), keyEquivalent: "=")
    increaseItem.keyEquivalentModifierMask = [.command, .shift]
    increaseItem.isEnabled = circleSize < Self.maxSize
    sizeMenu.addItem(increaseItem)

    let decreaseItem = NSMenuItem(title: "Decrease", action: #selector(decreaseSize), keyEquivalent: "-")
    decreaseItem.keyEquivalentModifierMask = [.command, .shift]
    decreaseItem.isEnabled = circleSize > Self.minSize
    sizeMenu.addItem(decreaseItem)

    sizeMenu.addItem(NSMenuItem.separator())

    let resetItem = NSMenuItem(title: "Reset to Default", action: #selector(resetSize), keyEquivalent: "0")
    resetItem.keyEquivalentModifierMask = [.command, .shift]
    resetItem.isEnabled = circleSize != Self.defaultSize
    sizeMenu.addItem(resetItem)

    sizeMenu.addItem(NSMenuItem.separator())

    let currentItem = NSMenuItem(title: "\(Int(circleSize))pt", action: nil, keyEquivalent: "")
    currentItem.isEnabled = false
    sizeMenu.addItem(currentItem)

    let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
    sizeItem.submenu = sizeMenu
    menu.addItem(sizeItem)

    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

    return menu
  }

  @objc
  private func increaseSize() {
    applySize(min(circleSize + Self.sizeStep, Self.maxSize))
  }

  @objc
  private func decreaseSize() {
    applySize(max(circleSize - Self.sizeStep, Self.minSize))
  }

  @objc
  private func resetSize() {
    applySize(Self.defaultSize)
  }

  private func applySize(_ newSize: CGFloat) {
    circleSize = newSize
    statusItem?.menu = buildMenu()

    if isActive {
      overlayWindow?.orderOut(nil)
      overlayWindow = OverlayWindow(circleSize: circleSize)
      overlayWindow?.moveToMouse()
      overlayWindow?.orderFrontRegardless()
      CursorHider.hide()
    }
  }

  // MARK: - Toggle

  @objc
  func toggleOverlay() {
    if isActive {
      deactivate()
    } else {
      activate()
    }
  }

  private func activate() {
    isActive = true

    CursorHider.hide()

    overlayWindow = OverlayWindow(circleSize: circleSize)
    overlayWindow?.moveToMouse()
    overlayWindow?.orderFrontRegardless()

    // 8ms polling (~120Hz) for smooth tracking
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(8))
    timer.setEventHandler { [weak self] in
      self?.overlayWindow?.moveToMouse()
      CursorHider.hide()
    }
    timer.resume()
    trackingTimer = timer

    // Click monitors
    clickDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
      self?.overlayWindow?.setPressed(true)
    }
    clickUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
      self?.overlayWindow?.setPressed(false)
    }

    updateStatusIcon()
  }

  private func deactivate() {
    isActive = false

    CursorHider.show()

    trackingTimer?.cancel()
    trackingTimer = nil

    if let m = clickDownMonitor { NSEvent.removeMonitor(m) }
    if let m = clickUpMonitor { NSEvent.removeMonitor(m) }
    clickDownMonitor = nil
    clickUpMonitor = nil

    overlayWindow?.orderOut(nil)
    overlayWindow = nil

    updateStatusIcon()
  }

  private func updateStatusIcon() {
    let name = isActive ? "circle.circle.fill" : "circle.circle"
    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: "TouchPoint")
    statusItem?.button?.image = image?.withSymbolConfiguration(config)
    statusItem?.button?.image?.isTemplate = true
  }

  // MARK: - Global Hotkey (Cmd+Shift+T)

  private func registerHotKey() {
    var hotKeyID = EventHotKeyID()
    hotKeyID.signature = OSType(0x5450_4B59)
    hotKeyID.id = 1

    var eventType = EventTypeSpec()
    eventType.eventClass = OSType(kEventClassKeyboard)
    eventType.eventKind = OSType(kEventHotKeyPressed)

    InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
      guard let userData = userData else { return OSStatus(eventNotHandledErr) }
      let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
      DispatchQueue.main.async { appDelegate.toggleOverlay() }
      return noErr
    }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

    RegisterEventHotKey(
      UInt32(kVK_ANSI_T), UInt32(cmdKey | shiftKey),
      hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
    )
  }

  // MARK: - Quit

  @objc
  private func quit() {
    if isActive { deactivate() }
    CursorHider.show()
    NSApplication.shared.terminate(nil)
  }
}
