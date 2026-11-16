import CoreGraphics
import Foundation

/// Intercepts scroll and side-button events system-wide.
///
/// The tap lives on the main run loop and its callback does very little:
/// flip a couple of numbers, or post a shortcut. It only exists while there's
/// something to do (see `MouseSettings.needsEventTap`).
final class MouseEventTap {
    private let settings: MouseSettings
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Buttons whose press we swallowed, so we swallow the release too.
    private var swallowedButtons: Set<Int64> = []

    init(settings: MouseSettings) {
        self.settings = settings
    }

    var isRunning: Bool { tap != nil }

    /// Returns `false` if the system refused (usually: no Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.scrollWheel, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swallowedButtons = []
    }

    /// Returns `nil` to drop the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches slow or interrupted taps off — switch it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event

        case .scrollWheel:
            if Self.isFromScrollWheel(event) {
                Self.reverse(event, vertical: settings.reverseVertical, horizontal: settings.reverseHorizontal)
            }
            return event

        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let action = settings.action(forButton: button)
            guard action.interceptsButton else { return event }
            swallowedButtons.insert(button)
            action.keyCombo?.post()
            return nil

        case .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            return swallowedButtons.remove(button) == nil ? event : nil

        default:
            return event
        }
    }

    // MARK: - Scrolling

    /// Classic wheel mice send line-based, non-continuous scrolling. Trackpads and
    /// Magic Mouse send continuous scrolling, so they keep the system direction.
    nonisolated static func isFromScrollWheel(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
    }

    /// Flips every delta field macOS and apps may read.
    nonisolated static func reverse(_ event: CGEvent, vertical: Bool, horizontal: Bool) {
        if vertical {
            flip(event, line: .scrollWheelEventDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1,
                 fixed: .scrollWheelEventFixedPtDeltaAxis1)
        }
        if horizontal {
            flip(event, line: .scrollWheelEventDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2,
                 fixed: .scrollWheelEventFixedPtDeltaAxis2)
        }
    }

    /// Setting one delta field makes macOS recompute the others, so read all
    /// three first and only then write them back negated.
    nonisolated private static func flip(_ event: CGEvent, line: CGEventField, point: CGEventField, fixed: CGEventField) {
        let lineValue = event.getIntegerValueField(line)
        let pointValue = event.getIntegerValueField(point)
        let fixedValue = event.getDoubleValueField(fixed)
        event.setIntegerValueField(line, value: -lineValue)
        event.setIntegerValueField(point, value: -pointValue)
        event.setDoubleValueField(fixed, value: -fixedValue)
    }
}

/// C callback for the tap. It runs on the main run loop, so stepping onto the
/// main actor is safe.
private func mouseEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let result = MainActor.assumeIsolated { tap.handle(type, event) }
    return result.map { Unmanaged.passUnretained($0) }
}
