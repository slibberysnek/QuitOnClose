import AppKit
import ApplicationServices
import ServiceManagement

func hasAccessibilityAccess() -> Bool {
    if AXIsProcessTrusted() { return true }
    // Approval can take effect before the process's cached trust state refreshes.
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

// The installed process has no status item, menu, Dock icon, or recurring UI.
// Only an explicit first install / --setup invocation may show setup controls.
final class BackgroundAppDelegate: NSObject, NSApplicationDelegate {
    private var engine: WindowMonitor?
    private var timer: Timer?
    private var setupWindow: NSWindow?
    private var setupStatus: NSTextField?
    private let setup: Bool
    private let smokeTest: Bool
    private var registrationError: String?

    init(setup: Bool = false, smokeTest: Bool = false) {
        self.setup = setup
        self.smokeTest = smokeTest
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if smokeTest {
            // Exercise the real silent launch path without registering at login,
            // requesting permissions, or observing the user's input.
            reconcilePermission()
            precondition(engine == nil && setupWindow == nil && NSApp.windows.isEmpty
                && NSApp.mainMenu == nil && NSApp.activationPolicy() == .accessory)
            print("SMOKE: background launch without permission; no windows, Dock icon, or app menu")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        if setup {
            do {
                try setStartAtLogin(true)
            } catch {
                registrationError = error.localizedDescription
            }
            // Save before requesting access: subsequent login launches must stay
            // silent even if access was denied or later revoked.
            UserDefaults.standard.set(true, forKey: "installationConfigured")
        }
        reconcilePermission()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reconcilePermission()
        }
        if setup && (engine == nil || SMAppService.mainApp.status != .enabled) {
            showSetup()
            if !hasAccessibilityAccess() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        engine?.stop()
    }

    // Reopening an already-running helper never brings up an interface.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    private func reconcilePermission() {
        if smokeTest || !hasAccessibilityAccess() {
            engine?.stop()
            engine = nil
        } else if engine == nil {
            let candidate = WindowMonitor()
            if candidate.start() {
                engine = candidate
            } else {
                candidate.stop()
            }
        }
        if engine != nil && SMAppService.mainApp.status == .enabled {
            setupWindow?.close()
        } else if engine == nil {
            setupStatus?.stringValue = "Enable QuitOnClose in the permission list. Setup closes automatically when ready."
        } else {
            setupStatus?.stringValue = registrationError.map { "Could not enable login: " + $0 }
                ?? "Allow QuitOnClose in Login Items to finish setup."
        }
    }

    private func showSetup() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 250),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Install QuitOnClose"
        window.isReleasedWhenClosed = false
        window.center()
        let title = NSTextField(labelWithString: "Approve once. Then it disappears.")
        title.font = .boldSystemFont(ofSize: 21)
        title.frame = NSRect(x: 24, y: 194, width: 452, height: 30)
        let description = NSTextField(wrappingLabelWithString: """
        Enable QuitOnClose in macOS's Accessibility permission list
        (Device Control and Data Access on newer macOS versions).

        It runs silently at login. No menu-bar icon, Dock icon, or
        Terminal window. Closing a window leaves other windows open;
        the application quits only after its last window closes.
        """)
        description.frame = NSRect(x: 24, y: 82, width: 452, height: 104)
        let status = NSTextField(wrappingLabelWithString: "Enable QuitOnClose in the permission list. Setup closes automatically when ready.")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 24, y: 43, width: 452, height: 33)
        let permissions = NSButton(title: "Open Permissions", target: self, action: #selector(openSettings))
        permissions.bezelStyle = .rounded
        permissions.frame = NSRect(x: 313, y: 8, width: 165, height: 32)
        permissions.keyEquivalent = "\r"
        let login = NSButton(title: "Login Items", target: self, action: #selector(openLoginSettings))
        login.bezelStyle = .rounded
        login.frame = NSRect(x: 193, y: 8, width: 120, height: 32)
        for view in [title, description, status, permissions, login] { window.contentView?.addSubview(view) }
        setupStatus = status
        setupWindow = window
        reconcilePermission()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLoginSettings() {
        if SMAppService.mainApp.status != .enabled {
            do { try setStartAtLogin(true); registrationError = nil }
            catch { registrationError = error.localizedDescription }
        }
        SMAppService.openSystemSettingsLoginItems()
    }
}
