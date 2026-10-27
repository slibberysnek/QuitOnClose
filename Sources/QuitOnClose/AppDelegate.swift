import AppKit
import ApplicationServices
import ServiceManagement

func hasAccessibilityAccess() -> Bool {
    if AXIsProcessTrusted() { return true }
    // A running process may keep reporting its pre-approval trust state. Verify
    // the actual API capability too, so approval can take effect without relaunch.
    let desktop = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(desktop, 0.1)
    var focused: CFTypeRef?
    return AXUIElementCopyAttributeValue(desktop, kAXFocusedApplicationAttribute as CFString, &focused) == .success
}

func setStartAtLogin(_ enabled: Bool) throws {
    let service = SMAppService.mainApp
    if enabled {
        if service.status != .enabled { try service.register() }
    } else if service.status != .notRegistered {
        try service.unregister()
    }
}

func loginStatusDescription() -> String {
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requires approval in System Settings > General > Login Items"
    case .notRegistered: return "disabled"
    case .notFound: return "not found"
    @unknown default: return "unknown"
    }
}

final class BackgroundAppDelegate: NSObject, NSApplicationDelegate {
    private var engine: WindowMonitor?
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var timer: Timer?
    private var setupWindow: NSWindow?
    private var setupStatus: NSTextField?
    private var paused = false
    private var askedForPermission = false
    private let smokeTest: Bool

    init(smokeTest: Bool = false) { self.smokeTest = smokeTest }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMenu()
        if smokeTest {
            showSetup()
            print("SMOKE: accessory app, menu bar, and setup window created")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        reconcilePermission()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.reconcilePermission()
        }
        if !hasAccessibilityAccess() { requestPermission() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        engine?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if engine == nil && !paused { showSetup() }
        return true
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "QuitOnClose")
            button.image?.isTemplate = true
            button.toolTip = "QuitOnClose"
        }
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Waiting for Accessibility approval", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        updateLoginItem()
        let settings = NSMenuItem(title: "Open Permission Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit QuitOnClose", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setStatus(_ text: String) {
        stateItem.title = text
        statusItem.button?.toolTip = "QuitOnClose — " + text
        setupStatus?.stringValue = text
    }

    private func reconcilePermission() {
        updateLoginItem()
        guard !paused else { return }
        guard hasAccessibilityAccess() else {
            engine?.stop()
            engine = nil
            setStatus("Waiting for Accessibility approval")
            if setupWindow == nil { showSetup() }
            return
        }
        guard engine == nil else { return }
        let candidate = WindowMonitor()
        guard candidate.start() else {
            candidate.stop()
            setStatus("Waiting for click access — see setup")
            showSetup(activate: false)
            setupStatus?.stringValue = "Access is enabled. If this message persists, quit and reopen QuitOnClose."
            return
        }
        engine = candidate
        setStatus("Running — quit only after last window closes")
        setupWindow?.close()
    }

    private func requestPermission() {
        guard !askedForPermission else { return }
        askedForPermission = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func showSetup(activate: Bool = true) {
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "QuitOnClose"
            window.isReleasedWhenClosed = false
            window.center()
            let title = NSTextField(labelWithString: "One-time permission")
            title.font = .boldSystemFont(ofSize: 22)
            title.frame = NSRect(x: 28, y: 245, width: 444, height: 30)
            let description = NSTextField(wrappingLabelWithString: """
            Click Open Settings, then turn on QuitOnClose in the permission list.

            It starts automatically after approval and runs without Terminal.
            Closing a window leaves other windows open. The app quits only
            after its last window closes. Save/cancel prompts stay normal.

            Use the ⓧ menu-bar button to pause or quit QuitOnClose.
            """)
            description.font = .systemFont(ofSize: 13)
            description.frame = NSRect(x: 28, y: 89, width: 444, height: 146)
            let status = NSTextField(wrappingLabelWithString: "Waiting for Accessibility approval")
            status.textColor = .secondaryLabelColor
            status.font = .systemFont(ofSize: 11)
            status.frame = NSRect(x: 28, y: 52, width: 444, height: 32)
            let open = NSButton(title: "Open Settings", target: self, action: #selector(openSettings))
            open.bezelStyle = .rounded
            open.keyEquivalent = "\r"
            open.frame = NSRect(x: 340, y: 14, width: 136, height: 32)
            let quit = NSButton(title: "Quit", target: self, action: #selector(quitApp))
            quit.bezelStyle = .rounded
            quit.frame = NSRect(x: 246, y: 14, width: 88, height: 32)
            for view in [title, description, status, open, quit] { window.contentView?.addSubview(view) }
            setupStatus = status
            setupWindow = window
        }
        if activate {
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettings() {
        requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Resume" : "Pause"
        if paused {
            engine?.stop()
            engine = nil
            setStatus("Paused")
        } else {
            reconcilePermission()
        }
    }

    private func updateLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.toolTip = "Start at Login: " + loginStatusDescription()
    }

    @objc private func toggleStartAtLogin() {
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            try setStartAtLogin(SMAppService.mainApp.status != .enabled)
            updateLoginItem()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Start at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
