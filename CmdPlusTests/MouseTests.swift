import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import CmdPlus

@Suite("Mouse")
struct MouseTests {
    // MARK: Settings

    @Test("Defaults: vertical reverse on, horizontal off, buttons untouched")
    func defaults() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        #expect(settings.reverseVertical)
        #expect(!settings.reverseHorizontal)
        #expect(settings.backButton == .systemDefault)
        #expect(settings.forwardButton == .systemDefault)
    }

    @Test("Settings persist across launches")
    func persistence() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.reverseVertical = false
        settings.reverseHorizontal = true
        settings.backButton = .missionControl
        settings.forwardButton = .clipboardHistory

        let reloaded = MouseSettings(defaults: env.defaults)
        #expect(!reloaded.reverseVertical)
        #expect(reloaded.reverseHorizontal)
        #expect(reloaded.backButton == .missionControl)
        #expect(reloaded.forwardButton == .clipboardHistory)
    }

    @Test("No event tap when there's nothing to do")
    func tapOnlyWhenNeeded() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.reverseVertical = false
        #expect(!settings.needsEventTap)
        settings.forwardButton = .nothing
        #expect(settings.needsEventTap)
    }

    @Test("Changing a setting notifies the module")
    func changeCallback() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        var calls = 0
        settings.onChange = { calls += 1 }
        settings.reverseHorizontal = true
        settings.backButton = .back
        #expect(calls == 2)
    }

    @Test("Side buttons map to the right setting")
    func buttonMapping() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.backButton = .back
        settings.forwardButton = .forward
        #expect(settings.action(forButton: 3) == .back)
        #expect(settings.action(forButton: 4) == .forward)
        #expect(settings.action(forButton: 2) == .systemDefault) // middle click is never touched
    }

    // MARK: Actions

    @Test("Every action except the pass-through ones sends a shortcut")
    func actionsHaveShortcuts() {
        for action in MouseButtonAction.allCases {
            let passThrough = action == .systemDefault || action == .nothing
            #expect((action.keyCombo == nil) == passThrough, "\(action)")
        }
    }

    @Test("Picker groups list every action exactly once")
    func groupsComplete() {
        let grouped = MouseButtonAction.groups.flatMap { $0 }
        #expect(grouped.count == MouseButtonAction.allCases.count)
        #expect(Set(grouped) == Set(MouseButtonAction.allCases))
    }

    @Test("Arrow shortcuts carry the flags the Dock expects")
    func arrowFlags() throws {
        let combo = try #require(MouseButtonAction.missionControl.keyCombo)
        #expect(combo.keyCode == CGKeyCode(kVK_UpArrow))
        #expect(combo.flags.contains([.maskControl, .maskSecondaryFn, .maskNumericPad]))
        #expect(KeyCombo(kVK_ANSI_C, .maskCommand).flags == .maskCommand)
    }

    // MARK: Scrolling

    private func scrollEvent(units: CGScrollEventUnit, vertical: Int32, horizontal: Int32) throws -> CGEvent {
        try #require(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                             wheel1: vertical, wheel2: horizontal, wheel3: 0))
    }

    @Test("Wheel mice are detected; continuous (trackpad-like) scrolling isn't")
    func wheelDetection() throws {
        #expect(MouseEventTap.isFromScrollWheel(try scrollEvent(units: .line, vertical: 1, horizontal: 0)))
        #expect(!MouseEventTap.isFromScrollWheel(try scrollEvent(units: .pixel, vertical: 10, horizontal: 0)))
    }

    @Test("Vertical reverse flips only the vertical axis")
    func reverseVerticalOnly() throws {
        let event = try scrollEvent(units: .line, vertical: 3, horizontal: -2)
        MouseEventTap.reverse(event, vertical: true, horizontal: false)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -2)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) < 0)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) < 0)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) < 0)
    }

    @Test("Both axes can be reversed")
    func reverseBoth() throws {
        let event = try scrollEvent(units: .line, vertical: -1, horizontal: 4)
        MouseEventTap.reverse(event, vertical: true, horizontal: true)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -4)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) > 0)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) < 0)
    }
}
