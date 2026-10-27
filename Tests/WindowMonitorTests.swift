extension WindowMonitor {
    func installTestGesture(_ value: CloseGesture) { gesture = value }
    func testFilter(_ type: CGEventType, _ event: CGEvent) -> Bool { filter(type, event) == nil }
    func configureTest(snapshot: @escaping (CloseButton) -> WindowSnapshot,
                       scheduler: @escaping (TimeInterval, @escaping () -> Void) -> Void,
                       quit: @escaping (NSRunningApplication) -> Void) {
        readSnapshot = snapshot
        schedule = scheduler
        requestQuit = quit
        isRunning = { _ in true }
    }
    func testClose(_ button: CloseButton) { checkAfterClose(button) }
    func testSetRunning(_ running: Bool) { isRunning = { _ in running } }
}

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("FAILED: " + name) }
    checks += 1
}
let app = NSRunningApplication.current
let button = CloseButton(window: AXUIElementCreateApplication(22222), application: app,
                         bounds: CGRect(x: 10, y: 10, width: 16, height: 16))
let inside = CGPoint(x: 18, y: 18)
let outside = CGPoint(x: 500, y: 500)
var hit: CloseButton? = button
var clicks = 0
let gesture = CloseGesture(identify: { point in
    guard let candidate = hit, candidate.bounds.contains(point) else { return nil }
    return candidate
}, didClickClose: { target in
    expect(target.application.processIdentifier == app.processIdentifier, "track original application")
    clicks += 1
})

expect(!gesture.handle(.down, at: outside), "ordinary down passes through")
expect(!gesture.handle(.drag, at: outside), "ordinary drag passes through")
expect(!gesture.handle(.up, at: outside), "ordinary up passes through")
expect(clicks == 0, "ordinary click is ignored")
expect(!gesture.handle(.down, at: inside), "close down passes through")
expect(clicks == 0, "no close follow-up on mouse-down")
expect(!gesture.handle(.up, at: inside), "close up passes through")
expect(clicks == 1, "one follow-up for completed close click")
_ = gesture.handle(.up, at: inside)
expect(clicks == 1, "extra up does not repeat follow-up")

_ = gesture.handle(.down, at: inside)
expect(!gesture.handle(.drag, at: outside), "drag away passes through")
_ = gesture.handle(.up, at: outside)
expect(clicks == 1, "drag away cancels auto-quit tracking")
_ = gesture.handle(.down, at: inside)
_ = gesture.handle(.drag, at: outside)
_ = gesture.handle(.drag, at: inside)
_ = gesture.handle(.up, at: inside)
expect(clicks == 1, "drag back does not rearm tracking")
_ = gesture.handle(.down, at: inside)
_ = gesture.handle(.up, at: outside)
expect(clicks == 1, "outside release without drag cancels tracking")
_ = gesture.handle(.down, at: inside)
gesture.cancel()
_ = gesture.handle(.up, at: inside)
expect(clicks == 1, "disabled-tap cancellation cancels tracking")

_ = gesture.handle(.down, at: inside)
hit = nil
_ = gesture.handle(.up, at: inside)
expect(clicks == 2, "passive tap can follow up after native close destroys button")
expect(!gesture.handle(.down, at: inside), "unknown down passes through")
expect(!gesture.handle(.up, at: inside), "unknown up passes through")
expect(clicks == 2, "unknown click never starts follow-up")
hit = button

func snapshot(_ ax: Int?, _ server: Int?, destroyed: Bool = true) -> WindowSnapshot {
    WindowSnapshot(accessibilityCount: ax, windowServerCount: server, clickedWindowClosed: destroyed)
}
let empty = snapshot(0, 0)

final class Scenario {
    let engine = WindowMonitor()
    var jobs: [() -> Void] = []
    var snapshots: [WindowSnapshot]
    var reads = 0
    var quits = 0

    init(_ snapshots: [WindowSnapshot]) {
        self.snapshots = snapshots
        engine.configureTest(snapshot: { [unowned self] target in
            expect(CFEqual(target.window, button.window), "census uses clicked window")
            let result = self.snapshots[min(self.reads, self.snapshots.count - 1)]
            self.reads += 1
            return result
        }, scheduler: { [unowned self] delay, job in
            expect(delay > 0, "wait for native close before checking")
            self.jobs.append(job)
        }, quit: { [unowned self] target in
            expect(target.processIdentifier == app.processIdentifier, "quit targets original app")
            self.quits += 1
        })
    }
    func next() { jobs.removeFirst()() }
    func drain() {
        var limit = 10
        while !jobs.isEmpty {
            precondition(limit > 0)
            limit -= 1
            next()
        }
    }
}

for (name, snapshots) in [
    ("two windows: closing one leaves one", [snapshot(1, 1)]),
    ("another window minimized", [snapshot(1, 1)]),
    ("window on another desktop missing from AX", [snapshot(0, 1)]),
    ("AX sees a window missing from server list", [snapshot(1, 0)]),
    ("Accessibility census fails", [snapshot(nil, 0)]),
    ("window-server census fails", [snapshot(0, nil)]),
    ("both census calls fail", [snapshot(nil, nil)]),
    ("close canceled / unsaved-document dialog", [snapshot(1, 1, destroyed: false)]),
    ("clicked window still exists despite empty lists", [snapshot(0, 0, destroyed: false)]),
    ("new window opens during settle interval", [empty, snapshot(1, 1)]),
    ("second census fails", [empty, snapshot(nil, 0)]),
    ("second server census fails", [empty, snapshot(0, nil)]),
] {
    let test = Scenario(snapshots)
    test.engine.testClose(button)
    expect(test.quits == 0, name + ": no immediate quit")
    test.drain()
    expect(test.quits == 0, name + ": never quit")
}

let last = Scenario([empty, empty])
last.engine.testClose(button)
expect(last.quits == 0 && last.reads == 0, "last window: no synchronous quit")
last.next()
expect(last.quits == 0 && last.reads == 1, "last window: first empty census insufficient")
last.next()
expect(last.quits == 1 && last.reads == 2, "last window: quit once after two empty censuses")

let stopped = Scenario([empty, empty])
stopped.engine.testClose(button)
stopped.next()
stopped.engine.stop()
stopped.drain()
expect(stopped.quits == 0, "Pause/stop cancels already pending quit")

let terminated = Scenario([empty, empty])
terminated.engine.testClose(button)
terminated.next()
terminated.engine.testSetRunning(false)
terminated.drain()
expect(terminated.quits == 0, "already terminated app is never asked to quit")

let duplicate = Scenario([empty, empty])
duplicate.engine.testClose(button)
duplicate.engine.testClose(button)
duplicate.drain()
expect(duplicate.quits == 1, "rapid repeated closes request quit only once")

func mouse(_ type: CGEventType, at point: CGPoint) -> CGEvent {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
}
let interceptor = WindowMonitor()
interceptor.installTestGesture(gesture)
for (type, point) in [(CGEventType.leftMouseDown, outside), (.leftMouseUp, outside),
                      (.leftMouseDown, inside), (.leftMouseDragged, inside), (.leftMouseUp, inside),
                      (.rightMouseDown, inside), (.mouseMoved, inside)] {
    expect(!interceptor.testFilter(type, mouse(type, at: point)), "native adapter never consumes mouse events")
}
let disabled = Scenario([empty, empty])
disabled.engine.testClose(button)
disabled.next()
_ = disabled.engine.testFilter(.tapDisabledByTimeout, mouse(.leftMouseUp, at: inside))
disabled.drain()
expect(disabled.quits == 0, "disabled event tap cancels pending quit")

for bundleID in ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
                 "com.apple.loginwindow", "com.apple.controlcenter",
                 "com.apple.notificationcenterui", "com.apple.spotlight", "COM.APPLE.FINDER"] {
    expect(isProtected(bundleID: bundleID, bundlePath: "/Applications/Test.app"), "protect " + bundleID)
}
expect(isProtected(bundleID: "other.system.helper", bundlePath: "/System/Library/CoreServices/X.app"),
       "protect system-interface bundles by path")
expect(!isProtected(bundleID: "org.mozilla.firefox", bundlePath: "/Applications/Firefox.app"),
       "Firefox is eligible for last-window follow-up")
expect(!isProtected(bundleID: "test.app", bundlePath: "/Applications/Café.app"), "non-ASCII paths supported")

func serverWindow(_ number: Int, owner: Int = 12345, layer: Int = 0) -> [String: Any] {
    [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: owner,
     kCGWindowLayer as String: layer]
}
let retained = [serverWindow(1), serverWindow(2), serverWindow(3)]
expect(countOpenServerWindows(retained, pid: 12345, orderedIn: { _ in false }) == 0,
       "Messages' retained closed server objects do not block last-window quit")
expect(countOpenServerWindows(retained, pid: 12345, orderedIn: { $0 == 2 }) == 1,
       "real off-desktop window still blocks quit among retained closed objects")
expect(countOpenServerWindows(retained, pid: 12345, orderedIn: { _ in nil }) == nil,
       "unsupported window-order query never assumes no windows")
expect(countOpenServerWindows([serverWindow(1, owner: 999), serverWindow(2, layer: 25)],
                              pid: 12345, orderedIn: { _ in true }) == 0,
       "other processes and nonstandard window layers do not block quit")
expect(countOpenServerWindows([[kCGWindowOwnerPID as String: 12345]], pid: 12345,
                              orderedIn: { _ in false }) == nil, "incomplete metadata remains uncertain")
let settling = Scenario([snapshot(1, 1, destroyed: false), empty, empty])
settling.engine.testClose(button)
settling.drain()
expect(settling.quits == 1, "wait for normal close animation before two empty samples")
print("PASS: \(checks) checks; no real clicks posted and no real applications quit.")
