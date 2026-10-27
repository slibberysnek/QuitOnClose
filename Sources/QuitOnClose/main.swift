import AppKit
import ApplicationServices
import ServiceManagement

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--login-status"] {
    print("Start at Login: " + loginStatusDescription())
    exit(0)
}
if arguments == ["--enable-login"] || arguments == ["--disable-login"] {
    do {
        try setStartAtLogin(arguments == ["--enable-login"])
        print("Start at Login: " + loginStatusDescription())
        exit(SMAppService.mainApp.status == .requiresApproval ? 1 : 0)
    } catch {
        report("Could not change Start at Login: \(error.localizedDescription)")
        exit(1)
    }
}
if arguments == ["--check"] {
    let approved = hasAccessibilityAccess()
    print("Accessibility access: \(approved ? "enabled" : "disabled")")
    exit(approved ? 0 : 1)
}
let app = NSApplication.shared
if let identifier = Bundle.main.bundleIdentifier,
   let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    other.activate(options: [])
    exit(0)
}
let appDelegate = BackgroundAppDelegate(smokeTest: arguments == ["--smoke-test"])
app.delegate = appDelegate
app.run()
