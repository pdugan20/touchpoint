import Cocoa
import Carbon

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow?
    private var isActive = false
    private var hotKeyRef: EventHotKeyRef?

    private var trackingTimer: DispatchSourceTimer?
    private var clickDownMonitor: Any?
    private var clickUpMonitor: Any?

    // MARK: - App Lifecycle

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotKey()
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "TouchPoint")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle TouchPoint", action: #selector(toggleOverlay), keyEquivalent: "t"))
        menu.items.first?.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Toggle

    @objc func toggleOverlay() {
        isActive ? deactivate() : activate()
    }

    private func activate() {
        isActive = true

        CursorHider.hide()

        overlayWindow = OverlayWindow()
        overlayWindow?.moveToMouse()
        overlayWindow?.orderFrontRegardless()

        // 8ms polling (~120Hz) for smooth tracking
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            self?.overlayWindow?.moveToMouse()
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
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "TouchPoint")
        statusItem.button?.image?.isTemplate = true
    }

    // MARK: - Global Hotkey (Cmd+Shift+T)

    private func registerHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5450_4B59)
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { appDelegate.toggleOverlay() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Quit

    @objc private func quit() {
        if isActive { deactivate() }
        CursorHider.show()
        NSApplication.shared.terminate(nil)
    }
}
