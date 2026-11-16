import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Intercepts scroll and side-button events system-wide.
///
/// The tap lives on the main run loop and its callback does very little. It only
/// exists while there's something to do (see `MouseSettings.needsEventTap`), and
/// the smooth-scrolling timer only runs while a glide is in progress.
final class MouseEventTap {
    /// Marks events CmdPlus posts itself, so the tap lets them through untouched.
    nonisolated static let syntheticMarker: Int64 = 0x434D_4450 // "CMDP"

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

        let input = ScrollPlanner.Input(
            wholeVertical: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            acceleratedVertical: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            wholeHorizontal: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            acceleratedHorizontal: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            flags: event.flags
        )

        switch ScrollPlanner.plan(input, settings: settings) {
        case .zoom(let zoomIn):
            KeyCombo(zoomIn ? kVK_ANSI_Equal : kVK_ANSI_Minus, .maskCommand).post()
            return nil

        case .scroll(let vertical, let horizontal, let removeFlags):
            var flags = event.flags
            flags.subtract(removeFlags)

            guard let fraction = settings.smoothness.stepFraction else {
                Self.write(event, vertical: vertical, horizontal: horizontal)
                event.flags = flags
                return event
            }

            // Replace the notch with a glide.
            scroller.stepFraction = fraction
            scroller.add(dx: horizontal * ScrollPlanner.pixelsPerLine, dy: vertical * ScrollPlanner.pixelsPerLine)
            glideFlags = flags
            glideLocation = event.location
            startGlide()
            return nil
        }
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
        scroller = SmoothScroller(stepFraction: scroller.stepFraction)
    }

    private func glideFrame() {
        guard let step = scroller.step() else {
            stopGlide()
            return
        }
        let simulateTrackpad = settings.trackpadSimulation
        // Without trackpad phases there's nothing to "end".
        if step.phase == .ended && !simulateTrackpad { return }
        if step.phase != .ended && step.dx == 0 && step.dy == 0 { return }
        guard let event = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel,
                                  wheelCount: 2, wheel1: step.dy, wheel2: step.dx, wheel3: 0)
        else { return }
        if simulateTrackpad {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Self.phaseValue(step.phase))
        }
        event.flags = glideFlags
        event.location = glideLocation
        event.post(tap: .cghidEventTap)
    }

    /// Values of `kCGScrollPhase…` (began 1, changed 2, ended 4).
    nonisolated static func phaseValue(_ phase: SmoothScroller.Phase) -> Int64 {
        switch phase {
        case .began: 1
        case .changed: 2
        case .ended: 4
        }
    }

    /// Classic wheel mice send line-based, non-continuous scrolling. Trackpads and
    /// Magic Mouse send continuous scrolling, so they keep the system behavior.
    nonisolated static func isFromScrollWheel(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
    }

    /// Rewrites a notch to scroll the given number of lines on each axis.
    nonisolated static func write(_ event: CGEvent, vertical: Double, horizontal: Double) {
        write(event, lines: vertical, line: .scrollWheelEventDeltaAxis1,
              point: .scrollWheelEventPointDeltaAxis1, fixed: .scrollWheelEventFixedPtDeltaAxis1)
        write(event, lines: horizontal, line: .scrollWheelEventDeltaAxis2,
              point: .scrollWheelEventPointDeltaAxis2, fixed: .scrollWheelEventFixedPtDeltaAxis2)
    }

    /// Setting one field makes macOS recompute the others, so the fractional
    /// value goes last.
    nonisolated private static func write(_ event: CGEvent, lines: Double,
                                          line: CGEventField, point: CGEventField, fixed: CGEventField) {
        var whole = lines.rounded()
        // A notch should never vanish when slowed down.
        if whole == 0 && lines != 0 { whole = lines < 0 ? -1 : 1 }
        event.setIntegerValueField(line, value: Int64(whole))
        event.setIntegerValueField(point, value: Int64((lines * 10).rounded()))
        event.setDoubleValueField(fixed, value: lines)
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
