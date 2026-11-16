import AppKit
import CoreGraphics

/// Intercepts scroll and side-button events system-wide.
///
/// The tap lives on the main run loop and its callback does very little. It only
/// exists while there's something to do (see `MouseSettings.needsEventTap`), and
/// the smooth-scrolling timer only runs while a glide is in progress.
final class MouseEventTap {
    /// Marks events CmdPlus posts itself, so the tap lets them through untouched.
    nonisolated static let syntheticMarker: Int64 = 0x434D_4450 // "CMDP"
    /// Pixels one wheel notch scrolls at 1× speed with smooth scrolling on.
    nonisolated static let pixelsPerLine = 40.0

    private let settings: MouseSettings
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Buttons whose press we swallowed, so we swallow the release too.
    private var swallowedButtons: Set<Int64> = []
    /// Buttons currently held down as a middle click.
    private var middleClickButtons: Set<Int64> = []
    /// A single click waiting to see whether a second one follows.
    private var pendingClick: DispatchWorkItem?

    private var scroller = SmoothScroller()
    private var glideTimer: Timer?
    /// Modifier keys and position of the last real wheel event, reused for the glide.
    private var glideFlags: CGEventFlags = []
    private var glideLocation: CGPoint = .zero

    private lazy var eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = Self.syntheticMarker
        return source
    }()

    init(settings: MouseSettings) {
        self.settings = settings
    }

    var isRunning: Bool { tap != nil }

    /// Returns `false` if the system refused (usually: no Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
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
        stopGlide()
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swallowedButtons = []
        middleClickButtons = []
        pendingClick?.cancel()
        pendingClick = nil
    }

    /// Returns `nil` to drop the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system switches slow or interrupted taps off — switch it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return event
        }

        switch type {
        case .scrollWheel:
            return handleScroll(event)
        case .otherMouseDown:
            return handleButtonDown(event)
        case .otherMouseUp:
            return handleButtonUp(event)
        case .otherMouseDragged:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            return swallowedButtons.contains(button) ? nil : event
        default:
            return event
        }
    }

    // MARK: - Scrolling

    private func handleScroll(_ event: CGEvent) -> CGEvent? {
        guard Self.isFromScrollWheel(event) else { return event }
        let factors = Self.factors(for: settings)

        guard settings.smoothScrolling else {
            Self.scale(event, vertical: factors.vertical, horizontal: factors.horizontal)
            return event
        }

        // Replace the notch with a glide.
        let lines = Self.lineDeltas(of: event)
        scroller.add(dx: lines.horizontal * Self.pixelsPerLine * factors.horizontal,
                     dy: lines.vertical * Self.pixelsPerLine * factors.vertical)
        glideFlags = event.flags
        glideLocation = event.location
        startGlide()
        return nil
    }

    private func startGlide() {
        guard glideTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.glideFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        glideTimer = timer
        glideFrame()
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        scroller = SmoothScroller()
    }

    private func glideFrame() {
        guard let step = scroller.step() else {
            stopGlide()
            return
        }
        guard step.dx != 0 || step.dy != 0,
              let event = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel,
                                  wheelCount: 2, wheel1: step.dy, wheel2: step.dx, wheel3: 0)
        else { return }
        event.flags = glideFlags
        event.location = glideLocation
        event.post(tap: .cghidEventTap)
    }

    /// Classic wheel mice send line-based, non-continuous scrolling. Trackpads and
    /// Magic Mouse send continuous scrolling, so they keep the system direction.
    nonisolated static func isFromScrollWheel(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
    }

    /// Speed times direction for each axis.
    static func factors(for settings: MouseSettings) -> (vertical: Double, horizontal: Double) {
        (settings.scrollSpeed * (settings.reverseVertical ? -1 : 1),
         settings.scrollSpeed * (settings.reverseHorizontal ? -1 : 1))
    }

    /// Lines scrolled, including the system's acceleration.
    nonisolated static func lineDeltas(of event: CGEvent) -> (vertical: Double, horizontal: Double) {
        (event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
         event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
    }

    /// Multiplies every delta field macOS and apps may read. A factor of −1 reverses.
    nonisolated static func scale(_ event: CGEvent, vertical: Double, horizontal: Double) {
        if vertical != 1 {
            scale(event, by: vertical, line: .scrollWheelEventDeltaAxis1,
                  point: .scrollWheelEventPointDeltaAxis1, fixed: .scrollWheelEventFixedPtDeltaAxis1)
        }
        if horizontal != 1 {
            scale(event, by: horizontal, line: .scrollWheelEventDeltaAxis2,
                  point: .scrollWheelEventPointDeltaAxis2, fixed: .scrollWheelEventFixedPtDeltaAxis2)
        }
    }

    /// Setting one delta field makes macOS recompute the others, so read all
    /// three first and only then write them back.
    nonisolated private static func scale(_ event: CGEvent, by factor: Double,
                                          line: CGEventField, point: CGEventField, fixed: CGEventField) {
        let lineValue = event.getIntegerValueField(line)
        let pointValue = event.getIntegerValueField(point)
        let fixedValue = event.getDoubleValueField(fixed)
        var scaledLine = (Double(lineValue) * factor).rounded()
        // A notch should never vanish when slowed down.
        if scaledLine == 0 && lineValue != 0 { scaledLine = factor * Double(lineValue) < 0 ? -1 : 1 }
        event.setIntegerValueField(line, value: Int64(scaledLine))
        event.setIntegerValueField(point, value: Int64((Double(pointValue) * factor).rounded()))
        event.setDoubleValueField(fixed, value: fixedValue * factor)
    }

    // MARK: - Buttons

    private func handleButtonDown(_ event: CGEvent) -> CGEvent? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        // The "+" field in Settings needs to see the real click.
        guard !settings.isCapturingButtons else { return event }

        let clickCount = event.getIntegerValueField(.mouseEventClickState)
        let plan = ButtonPlanner.plan(button: button, clickCount: clickCount, bindings: settings.bindings)

        switch plan {
        case .passThrough:
            return event
        case .perform(let binding):
            pendingClick?.cancel()
            pendingClick = nil
            run(binding, at: event.location, holding: true)
        case .waitForDoubleClick(let binding):
            pendingClick?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.pendingClick = nil
                    self?.run(binding, at: event.location, holding: false)
                }
            }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
        swallowedButtons.insert(button)
        return nil
    }

    private func handleButtonUp(_ event: CGEvent) -> CGEvent? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        if middleClickButtons.remove(button) != nil {
            postMiddle(.otherMouseUp, at: event.location)
        }
        return swallowedButtons.remove(button) == nil ? event : nil
    }

    /// - Parameter holding: the button is still down, so a middle click can be held
    ///   (and released later); otherwise it's a complete click.
    private func run(_ binding: ButtonBinding, at location: CGPoint, holding: Bool) {
        switch binding.action.behavior {
        case .passThrough, .swallow:
            break
        case .keys(let combo):
            combo.post()
        case .middleClick:
            postMiddle(.otherMouseDown, at: location)
            if holding {
                middleClickButtons.insert(binding.button)
            } else {
                postMiddle(.otherMouseUp, at: location)
            }
        case .openApp(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .customShortcut:
            binding.shortcut?.combo.post()
        }
    }

    private func postMiddle(_ type: CGEventType, at location: CGPoint) {
        CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: location, mouseButton: .center)?
            .post(tap: .cghidEventTap)
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
