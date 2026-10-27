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
guard arguments.isEmpty || arguments == ["--setup"] || arguments == ["--smoke-test"] else {
    report("Usage: QuitOnClose [--setup | --check | --login-status | --enable-login | --disable-login]")
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let smokeTest = arguments == ["--smoke-test"]
if !smokeTest && !Installation.isInstalled() {
    do { try Installation.installAndLaunch() }
    catch {
        let alert = NSAlert()
        alert.messageText = "Couldn’t install QuitOnClose"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        exit(1)
    }
    app.run()
    exit(0)
}
if !smokeTest, let identifier = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && $0.bundleURL?.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath() }) {
    exit(0)
}
let setup = !smokeTest && (arguments == ["--setup"] || !UserDefaults.standard.bool(forKey: "installationConfigured"))
let appDelegate = BackgroundAppDelegate(setup: setup, smokeTest: smokeTest)
app.delegate = appDelegate
app.run()
