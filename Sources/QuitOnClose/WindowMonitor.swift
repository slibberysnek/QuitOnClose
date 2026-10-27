import AppKit
import ApplicationServices
import Darwin

func report(_ message: String) {
    fputs(message + "\n", stderr)
}

let protectedBundles: Set<String> = [
    "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
    "com.apple.loginwindow", "com.apple.controlcenter",
    "com.apple.notificationcenterui", "com.apple.spotlight"
]

func isProtected(bundleID: String, bundlePath: String) -> Bool {
    protectedBundles.contains(bundleID.lowercased()) || bundlePath.hasPrefix("/System/Library/")
}

struct CloseButton {
    let window: AXUIElement
    let application: NSRunningApplication
    let bounds: CGRect
}

// Observe clicks without consuming or replacing any mouse event.
final class CloseGesture {
    enum Phase { case down, drag, up }
    private var button: CloseButton?
    private var captured = false
    private var canceled = false
    var identify: (CGPoint) -> CloseButton?
    var didClickClose: (CloseButton) -> Void

    init(identify: @escaping (CGPoint) -> CloseButton?,
         didClickClose: @escaping (CloseButton) -> Void) {
        self.identify = identify
        self.didClickClose = didClickClose
    }

    func cancel() { canceled = true }

    // Always returns false: even close-button clicks pass through unchanged.
    func handle(_ phase: Phase, at point: CGPoint) -> Bool {
        switch phase {
        case .down:
            button = identify(point)
            captured = button != nil
            canceled = false
            return false
        case .drag:
            if let button, !button.bounds.contains(point) { canceled = true }
            return false
        case .up:
            let wasCaptured = captured
            let original = button
            button = nil
            captured = false
            if wasCaptured, !canceled, let original,
               original.bounds.contains(point) {
                // With a passive event tap, the native button may already be gone.
                // A later fresh window census decides whether a quit is permitted.
                didClickClose(original)
            }
            return false
        }
    }
}

struct WindowSnapshot {
    let accessibilityCount: Int?
    let windowServerCount: Int?
    let clickedWindowClosed: Bool

    var isConfirmedLastClose: Bool {
        clickedWindowClosed && accessibilityCount == 0 && windowServerCount == 0
    }
}

// Require two consecutive fresh, successful empty snapshots.
struct LastWindowCheck {
    private var emptySnapshots = 0

    mutating func observe(_ snapshot: WindowSnapshot) -> Bool {
        guard snapshot.isConfirmedLastClose else {
            emptySnapshots = 0
            return false
        }
        emptySnapshots += 1
        return emptySnapshots == 2
    }
}

// Read-only Window Server SPI. Public window lists include closed backing
// objects and do not distinguish them from windows on another Space. Resolve
// this optional query dynamically; if unavailable, leave the application open.
enum WindowOrder {
    typealias Connection = @convention(c) () -> Int32
    typealias Ordered = @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt8>) -> Int32
    private static let functions: (Connection, Ordered)? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let connection = dlsym(handle, "SLSMainConnectionID"),
              let ordered = dlsym(handle, "SLSWindowIsOrderedIn") else { return nil }
        return (unsafeBitCast(connection, to: Connection.self), unsafeBitCast(ordered, to: Ordered.self))
    }()

    static func isOrderedIn(_ window: UInt32) -> Bool? {
        guard let (connection, ordered) = functions else { return nil }
        var value: UInt8 = 0
        guard ordered(connection(), window, &value) == 0 else { return nil }
        return value != 0
    }
}

func countOpenServerWindows(_ windows: [[String: Any]], pid: pid_t,
                            orderedIn: (UInt32) -> Bool? = WindowOrder.isOrderedIn) -> Int? {
    var count = 0
    for window in windows {
        guard let owner = window[kCGWindowOwnerPID as String] as? Int else { return nil }
        guard owner == Int(pid) else { continue }
        guard let layer = window[kCGWindowLayer as String] as? Int else { return nil }
        guard layer == 0 else { continue }
        guard let number = window[kCGWindowNumber as String] as? NSNumber,
              let isOpen = orderedIn(number.uint32Value) else { return nil }
        if isOpen { count += 1 }
    }
    return count
}

final class WindowMonitor {
    private let desktop = AXUIElementCreateSystemWide()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var generation = 0
    private var pendingChecks: [pid_t: UUID] = [:]
    private var isRunning: (NSRunningApplication) -> Bool = { !$0.isTerminated }
    private var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
    private lazy var readSnapshot: (CloseButton) -> WindowSnapshot = { [unowned self] in
        self.windowSnapshot(for: $0)
    }
    private var requestQuit: (NSRunningApplication) -> Void = { application in
        let name = application.localizedName ?? "application"
        if application.terminate() {
            print("Last window closed; quit requested: \(name)")
        } else {
            report("Could not request Quit for \(name); no force-quit attempted.")
        }
    }
    private lazy var gesture = CloseGesture(
        identify: { [weak self] in self?.closeButton(at: $0) },
        didClickClose: { [weak self] in self?.checkAfterClose($0) }
    )

    init() {
        // Bound Accessibility IPC waits so an unresponsive app cannot freeze input.
        AXUIElementSetMessagingTimeout(desktop, 0.03)
    }

    private func checkAfterClose(_ button: CloseButton) {
        let expectedGeneration = generation
        let pid = button.application.processIdentifier
        let attempt = UUID()
        pendingChecks[pid] = attempt
        var check = LastWindowCheck()
        func poll(_ remaining: Int) {
            guard self.generation == expectedGeneration,
                  self.pendingChecks[pid] == attempt else { return }
            guard self.isRunning(button.application) else {
                self.pendingChecks.removeValue(forKey: pid)
                return
            }
            if check.observe(self.readSnapshot(button)) {
                self.pendingChecks.removeValue(forKey: pid)
                self.requestQuit(button.application)
                return
            }
            guard remaining > 1 else {
                self.pendingChecks.removeValue(forKey: pid)
                return
            }
            self.schedule(0.3) { poll(remaining - 1) }
        }
        schedule(0.4) { [weak self] in
            guard self != nil else { return }
            poll(8)
        }
    }

    private func windowSnapshot(for button: CloseButton) -> WindowSnapshot {
        let pid = button.application.processIdentifier
        let applicationElement = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &rawWindows)
        let axCount: Int?
        if result == .success, let windows = rawWindows as? [AXUIElement] {
            // Count all windows, including dialogs, minimized windows, and utility panels.
            axCount = windows.count
        } else {
            axCount = nil
        }

        // Use all desktops. The ordered-in query excludes retained *closed*
        // backing objects without excluding real windows on another Space.
        var serverCount: Int?
        if let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
            serverCount = countOpenServerWindows(windows, pid: pid)
        }

        // A closed window can remain a valid AX object. Its removal from the
        // application's window list establishes closure; invalidUIElement is not
        // required. A retained object must not prevent an otherwise normal quit.
        let listedWindows = result == .success ? rawWindows as? [AXUIElement] : nil
        let clickedWindowClosed = listedWindows.map { windows in
            !windows.contains(where: { CFEqual($0, button.window) })
        } ?? false
        return WindowSnapshot(accessibilityCount: axCount, windowServerCount: serverCount,
                              clickedWindowClosed: clickedWindowClosed)
    }

    private func closeButton(at point: CGPoint) -> CloseButton? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(desktop, Float(point.x), Float(point.y), &hit) == .success,
              let element = hit else { return nil }

        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXEnabledAttribute,
                          kAXPositionAttribute, kAXSizeAttribute, kAXWindowAttribute] as CFArray
        var rawValues: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &rawValues) == .success,
              let values = rawValues as? [Any], values.count == 6,
              values[0] as? String == kAXButtonRole,
              values[1] as? String == kAXCloseButtonSubrole,
              values[2] as? Bool == true else { return nil }

        let positionValue = values[3] as CFTypeRef
        let sizeValue = values[4] as CFTypeRef
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let axPosition = positionValue as! AXValue
        let axSize = sizeValue as! AXValue
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(axPosition) == .cgPoint,
              AXValueGetType(axSize) == .cgSize,
              AXValueGetValue(axPosition, .cgPoint, &origin),
              AXValueGetValue(axSize, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        let bounds = CGRect(origin: origin, size: size)
        guard bounds.contains(point) else { return nil }

        let windowValue = values[5] as CFTypeRef
        guard CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = windowValue as! AXUIElement
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
              subrole as? String == kAXStandardWindowSubrole else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated, application.isFinishedLaunching,
              application.activationPolicy != .prohibited,
              let bundleID = application.bundleIdentifier,
              let bundlePath = application.bundleURL?.path,
              !isProtected(bundleID: bundleID, bundlePath: bundlePath) else { return nil }
        return CloseButton(window: window, application: application, bounds: bounds)
    }

    private func filter(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gesture.cancel()
            generation += 1
            pendingChecks.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let phase: CloseGesture.Phase
        switch type {
        case .leftMouseDown: phase = .down
        case .leftMouseDragged: phase = .drag
        case .leftMouseUp: phase = .up
        default: return Unmanaged.passUnretained(event)
        }
        _ = gesture.handle(phase, at: event.location)
        return Unmanaged.passUnretained(event)
    }

    func start() -> Bool {
        let mask: CGEventMask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<WindowMonitor>.fromOpaque(context).takeUnretainedValue().filter(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap,
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        generation += 1
        pendingChecks.removeAll()
        gesture.cancel()
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
