import AppKit
import Darwin

// Install in the current user's Applications folder, without administrator access.
// Copy to a sibling first so a failed copy never replaces a working installation.
enum Installation {
    static var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/QuitOnClose.app", isDirectory: true)
    }

    static func isInstalled(_ bundle: URL = Bundle.main.bundleURL) -> Bool {
        bundle.resolvingSymlinksInPath().standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL
    }

    static func installAndLaunch() throws {
        // Replacing the same bundle identity is an explicit update. Stop the
        // old instance before replacing its executable, keeping permission intact
        // when macOS's signing policy permits it.
        if let identifier = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                guard app.terminate() else {
                    throw NSError(domain: "QuitOnClose", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Quit the existing QuitOnClose process in Activity Monitor, then try again."])
                }
                let deadline = Date().addingTimeInterval(5)
                while kill(app.processIdentifier, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                guard kill(app.processIdentifier, 0) == -1 && errno == ESRCH else {
                    throw NSError(domain: "QuitOnClose", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "The existing QuitOnClose process is still running. Please quit it and try again."])
                }
            }
        }
        try installBundle(from: Bundle.main.bundleURL, to: destination)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--setup"]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            if let error {
                let alert = NSAlert()
                alert.messageText = "Couldn’t start QuitOnClose"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            NSApp.terminate(nil)
        }
    }

    static func installBundle(from source: URL, to target: URL) throws {
        guard let identifier = Bundle(url: source)?.bundleIdentifier else {
            throw NSError(domain: "QuitOnClose", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "The installer is not a valid application bundle."])
        }
        let manager = FileManager.default
        let parent = target.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(".QuitOnClose-" + UUID().uuidString + ".app")
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: source, to: staged)
        if manager.fileExists(atPath: target.path) {
            // Do not replace an unrelated application or directory.
            guard Bundle(url: target)?.bundleIdentifier == identifier else {
                throw NSError(domain: "QuitOnClose", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Another item already exists at " + target.path])
            }
            _ = try manager.replaceItemAt(target, withItemAt: staged)
        } else {
            try manager.moveItem(at: staged, to: target)
        }
    }

}
