import AppKit
import ApplicationServices

/// Moves and resizes the focused window of the frontmost app via the
/// Accessibility API. Only does work when an action is triggered.
final class WindowMover {
    /// Frames to go back to with "Restore", per window.
    private var history: [(window: AXUIElement, original: CGRect, applied: CGRect)] = []
    private static let historyLimit = 50

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Returns `false` if there's no window to act on or the app refused.
    @discardableResult
    func perform(_ action: WindowAction, gap: CGFloat) -> Bool {
        guard let window = Self.focusedWindow(), let current = Self.frame(of: window) else { return false }
        guard let screen = Self.screen(containing: current) else { return false }

        let target: CGRect
        switch action {
        case .restore:
            guard let index = history.firstIndex(where: { CFEqual($0.window, window) }) else { return false }
            target = history.remove(at: index).original
            Self.setFrame(target, of: window)
            return true
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return false }
            let next = screens[(index + 1) % screens.count]
            target = ScreenCoordinates.move(current, from: screen.visibleFrame, to: next.visibleFrame)
        default:
            guard let frame = action.frame(in: screen.visibleFrame, current: current, gap: gap) else { return false }
            target = frame
        }

        remember(window, current: current, applied: target)
        Self.setFrame(target, of: window)
        return true
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

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
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
        let axFrame = ScreenCoordinates.flip(frame, mainScreenHeight: mainScreenHeight)
        set(window, kAXSizeAttribute, axFrame.size, type: .cgSize)
        set(window, kAXPositionAttribute, axFrame.origin, type: .cgPoint)
        set(window, kAXSizeAttribute, axFrame.size, type: .cgSize)
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
}
