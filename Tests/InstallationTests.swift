import Foundation

let manager = FileManager.default
let scratch = manager.temporaryDirectory.appendingPathComponent("QuitOnClose-tests-" + UUID().uuidString)
try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: scratch) }
var checks = 0
func expect(_ condition: Bool, _ description: String) {
    precondition(condition, description)
    checks += 1
}
func fixture(_ name: String, identifier: String = "org.quitonclose.fixture", content: String) throws -> URL {
    let path = scratch.appendingPathComponent(name + ".app")
    try manager.createDirectory(at: path.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let info = ["CFBundleIdentifier": identifier, "CFBundleName": name, "CFBundlePackageType": "APPL"]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: path.appendingPathComponent("Contents/Info.plist"))
    try content.write(to: path.appendingPathComponent("Contents/payload"), atomically: true, encoding: .utf8)
    return path
}
let first = try fixture("First", content: "version one")
let second = try fixture("Second", content: "version two")
let destination = scratch.appendingPathComponent("Applications/QuitOnClose.app")
try Installation.installBundle(from: first, to: destination)
expect(try String(contentsOf: destination.appendingPathComponent("Contents/payload"), encoding: .utf8) == "version one", "fresh install copies payload")
expect(manager.fileExists(atPath: first.path), "install preserves downloaded source")
try Installation.installBundle(from: second, to: destination)
expect(try String(contentsOf: destination.appendingPathComponent("Contents/payload"), encoding: .utf8) == "version two", "update replaces payload")
let unrelated = try fixture("Unrelated", identifier: "org.unrelated.fixture", content: "keep me")
do {
    try Installation.installBundle(from: first, to: unrelated)
    fatalError("unrelated bundle was replaced")
} catch {
    expect(try String(contentsOf: unrelated.appendingPathComponent("Contents/payload"), encoding: .utf8) == "keep me", "unrelated app preserved")
}
let plain = scratch.appendingPathComponent("Plain.app")
try manager.createDirectory(at: plain, withIntermediateDirectories: true)
do {
    try Installation.installBundle(from: first, to: plain)
    fatalError("unrelated directory was replaced")
} catch { expect(manager.fileExists(atPath: plain.path), "unrelated directory preserved") }
do {
    try Installation.installBundle(from: scratch.appendingPathComponent("Missing.app"), to: destination)
    fatalError("invalid source accepted")
} catch {
    expect(try String(contentsOf: destination.appendingPathComponent("Contents/payload"), encoding: .utf8) == "version two", "failed update preserves installed app")
}
let siblings = try manager.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
expect(siblings == ["QuitOnClose.app"], "temporary staging directories cleaned")
expect(Installation.isInstalled(Installation.destination), "installed location recognized")
expect(!Installation.isInstalled(first), "downloaded location recognized")
print("PASS: \(checks) installation checks; only disposable bundles changed.")
