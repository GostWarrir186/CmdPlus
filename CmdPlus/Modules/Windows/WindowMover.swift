import AppKit
import ApplicationServices

/// Moves and resizes the focused window of the frontmost app via the
/// Accessibility API. Only does work when an action is triggered.
final class WindowMover {
    /// Frames to go back to with "Restore", per window.
    private var history: [(window: AXUIElement, original: CGRect, applied: CGRect)] = []
    private static let historyLimit = 50

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Returns where the windows went (to highlight it), or `nil` if there's
    /// no window to act on.
    @discardableResult
    func perform(_ action: WindowAction, gap: CGFloat) -> [CGRect]? {
        guard let window = focusedWindow(), let current = Self.frame(of: window) else { return nil }
        guard let screen = Self.screen(containing: current) else { return nil }

        if let layouts = action.arrangement {
            return arrange(layouts, first: window, screen: screen, gap: gap)
        }

        let target: CGRect
        switch action {
        case .restore:
            guard let index = history.firstIndex(where: { CFEqual($0.window, window) }) else { return nil }
            target = history.remove(at: index).original
            Self.setFrame(target, of: window)
            return [target]
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return nil }
            let next = screens[(index + 1) % screens.count]
            target = ScreenCoordinates.move(current, from: screen.visibleFrame, to: next.visibleFrame)
        default:
            guard let frame = action.frame(in: screen.visibleFrame, current: current, gap: gap) else { return nil }
            target = frame
        }

        remember(window, current: current, applied: target)
        Self.setFrame(target, of: window)
        return [target]
    }

    /// Lays out the focused window and the ones right behind it, front to back.
    private func arrange(_ layouts: [WindowAction], first: AXUIElement, screen: NSScreen, gap: CGFloat) -> [CGRect]? {
        let windows = [first] + Self.windowsBehind(first, count: layouts.count - 1)
        var placed: [CGRect] = []
        for (window, layout) in zip(windows, layouts) {
            guard let current = Self.frame(of: window),
                  let target = layout.frame(in: screen.visibleFrame, current: current, gap: gap) else { continue }
            remember(window, current: current, applied: target)
            Self.setFrame(target, of: window)
            placed.append(target)
        }
        return placed.isEmpty ? nil : placed
    }

    /// Other apps' and the same app's windows in front-to-back order, matched
    /// from the window server's list to Accessibility elements by owner and frame.
    private static func windowsBehind(_ first: AXUIElement, count: Int) -> [AXUIElement] {
        guard count > 0,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var result: [AXUIElement] = []
        var appWindows: [pid_t: [AXUIElement]] = [:]
        for entry in info {
            guard result.count < count,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if appWindows[pid] == nil {
                var list: CFTypeRef?
                AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &list)
                appWindows[pid] = (list as? [AXUIElement]) ?? []
            }
            // Window-server bounds use the same top-left origin as Accessibility.
            let match = appWindows[pid]?.first { window in
                guard isStandardWindow(window), !CFEqual(window, first),
                      !result.contains(where: { CFEqual($0, window) }),
                      let position: CGPoint = value(of: window, kAXPositionAttribute, type: .cgPoint),
                      let size: CGSize = value(of: window, kAXSizeAttribute, type: .cgSize) else { return false }
                return CGRect(origin: position, size: size).isClose(to: bounds, tolerance: 4)
            }
            if let match { result.append(match) }
        }
        return result
    }

    /// Keeps the frame from before the first layout, so "Restore" goes back to
    /// where the user had the window — unless they've moved it by hand since.
    private func remember(_ window: AXUIElement, current: CGRect, applied: CGRect) {
        if let index = history.firstIndex(where: { CFEqual($0.window, window) }) {
            let entry = history[index]
            let movedByHand = !entry.applied.insetBy(dx: -2, dy: -2).contains(current)
            history[index] = (window, movedByHand ? current : entry.original, applied)
        } else {
            history.append((window, current, applied))
            if history.count > Self.historyLimit { history.removeFirst() }
        }
    }

    // MARK: - Accessibility

    /// The app the user was last working in. Clicking the menu bar can make
    /// CmdPlus itself the frontmost app, so we keep track of the one before.
    private var lastOtherApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            lastOtherApp = front
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            return front
        }
        return lastOtherApp.flatMap { $0.isTerminated ? nil : $0 }
    }

    /// The focused window, or the main one, or the first regular window —
    /// the focused element is sometimes a sheet or a panel.
    private func focusedWindow() -> AXUIElement? {
        guard let app = targetApp() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window: AXUIElement = Self.element(element, attribute), Self.isStandardWindow(window) {
                return window
            }
        }
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return nil }
        return list.first(where: Self.isStandardWindow)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        let value = subrole as? String
        return value == nil || value == kAXStandardWindowSubrole || value == kAXDialogSubrole
    }

    /// The window's frame in Cocoa coordinates.
    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position: CGPoint = value(of: window, kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = value(of: window, kAXSizeAttribute, type: .cgSize) else { return nil }
        return ScreenCoordinates.flip(CGRect(origin: position, size: size), mainScreenHeight: mainScreenHeight)
    }

    /// Size, then position, then size again: apps limit sizes based on where the
    /// window is, and this order works when moving between screens too.
    private static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        // Apps with "enhanced user interface" on animate changes and drop some of
        // them. Turn it off while we move the window, then put it back.
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        let enhanced = boolValue(of: app, "AXEnhancedUserInterface")
        if enhanced == true { setBool(app, "AXEnhancedUserInterface", false) }
        defer { if enhanced == true { setBool(app, "AXEnhancedUserInterface", true) } }

        apply(frame, to: window)
        // Some apps adjust the frame their own way first — try once more if so.
        if let result = self.frame(of: window), !result.isClose(to: frame) {
            apply(frame, to: window)
        }
    }

    private static func apply(_ frame: CGRect, to window: AXUIElement) {
        let axFrame = ScreenCoordinates.flip(frame, mainScreenHeight: mainScreenHeight)
        set(window, kAXSizeAttribute, axFrame.size, type: .cgSize)
        set(window, kAXPositionAttribute, axFrame.origin, type: .cgPoint)
        set(window, kAXSizeAttribute, axFrame.size, type: .cgSize)
    }

    private static func boolValue(of element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean)
    }

    private static var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }

    private static func value<T>(of element: AXUIElement, _ attribute: String, type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AXValueGetValue(raw as! AXValue, type, pointer) else { return nil }
        return pointer.pointee
    }

    private static func set<T>(_ element: AXUIElement, _ attribute: String, _ value: T, type: AXValueType) {
        var copy = value
        guard let axValue = AXValueCreate(type, &copy) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }

    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
