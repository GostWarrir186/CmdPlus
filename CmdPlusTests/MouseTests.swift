import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import CmdPlus

@Suite("Mouse settings")
struct MouseSettingsTests {
    @Test("Defaults: smooth, 1× speed, vertical reverse on, no button rows")
    func defaults() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        #expect(settings.smoothScrolling)
        #expect(settings.scrollSpeed == 1)
        #expect(settings.reverseVertical)
        #expect(!settings.reverseHorizontal)
        #expect(settings.bindings.isEmpty)
    }

    @Test("Everything persists across launches, including recorded shortcuts")
    func persistence() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.smoothScrolling = false
        settings.scrollSpeed = 2
        settings.reverseHorizontal = true
        let id = try #require(settings.addBinding(button: 3, trigger: .click))
        let index = try #require(settings.bindings.firstIndex { $0.id == id })
        settings.bindings[index].action = .keyboardShortcut
        settings.bindings[index].shortcut = ShortcutBinding(combo: KeyCombo(kVK_ANSI_4, [.maskAlternate, .maskCommand]), display: "⌥⌘4")

        let reloaded = MouseSettings(defaults: env.defaults)
        #expect(!reloaded.smoothScrolling)
        #expect(reloaded.scrollSpeed == 2)
        #expect(reloaded.reverseHorizontal)
        #expect(reloaded.bindings == settings.bindings)
        #expect(reloaded.bindings.first?.shortcut?.display == "⌥⌘4")
    }

    @Test("Speed is clamped to 0.5–3×", arguments: [(0.1, 0.5), (0.75, 0.75), (9.0, 3.0)])
    func speedClamped(input: Double, expected: Double) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.scrollSpeed = input
        #expect(settings.scrollSpeed == expected)
    }

    @Test("No event tap when there's nothing to do")
    func tapOnlyWhenNeeded() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.reverseVertical = false
        settings.smoothScrolling = false
        #expect(!settings.needsEventTap)

        // A row left on "System Default" still costs nothing.
        let id = try #require(settings.addBinding(button: 3, trigger: .click))
        #expect(!settings.needsEventTap)
        settings.bindings[settings.bindings.firstIndex { $0.id == id }!].action = .missionControl
        #expect(settings.needsEventTap)

        settings.removeBinding(id)
        settings.scrollSpeed = 1.5
        #expect(settings.needsEventTap)
    }

    @Test("Adding a row: no duplicates, left and right buttons are refused")
    func addBinding() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        let first = settings.addBinding(button: 4, trigger: .click)
        #expect(settings.addBinding(button: 4, trigger: .click) == first)
        #expect(settings.addBinding(button: 4, trigger: .doubleClick) != first)
        #expect(settings.addBinding(button: 0, trigger: .click) == nil)
        #expect(settings.addBinding(button: 1, trigger: .click) == nil)
        #expect(settings.bindings.count == 2)
    }

    @Test("Changing a setting notifies the module")
    func changeCallback() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        var calls = 0
        settings.onChange = { calls += 1 }
        settings.smoothScrolling = false
        settings.addBinding(button: 3, trigger: .click)
        #expect(calls == 2)
    }

    @Test("Migration: the old fixed button pickers become rows")
    func migration() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.defaults.set("missionControl", forKey: "mouse.backButton")
        env.defaults.set("systemDefault", forKey: "mouse.forwardButton")
        let settings = MouseSettings(defaults: env.defaults)
        #expect(settings.bindings.map(\.button) == [3])
        #expect(settings.bindings.first?.action == .missionControl)
        #expect(env.defaults.object(forKey: "mouse.backButton") == nil)
    }
}

@Suite("Mouse buttons")
struct MouseButtonTests {
    private func row(_ button: Int64, _ trigger: ButtonTrigger, _ action: MouseButtonAction) -> ButtonBinding {
        ButtonBinding(button: button, trigger: trigger, action: action)
    }

    @Test("Unassigned buttons pass through")
    func passThrough() {
        #expect(ButtonPlanner.plan(button: 3, clickCount: 1, bindings: []) == .passThrough)
        let other = [row(4, .click, .back)]
        #expect(ButtonPlanner.plan(button: 3, clickCount: 1, bindings: other) == .passThrough)
        let untouched = [row(3, .click, .systemDefault)]
        #expect(ButtonPlanner.plan(button: 3, clickCount: 1, bindings: untouched) == .passThrough)
    }

    @Test("Click only: runs immediately, even on fast repeated presses")
    func clickOnly() {
        let click = row(3, .click, .missionControl)
        #expect(ButtonPlanner.plan(button: 3, clickCount: 1, bindings: [click]) == .perform(click))
        #expect(ButtonPlanner.plan(button: 3, clickCount: 2, bindings: [click]) == .perform(click))
    }

    @Test("Click and double click: single waits, double runs")
    func both() {
        let click = row(3, .click, .back)
        let double = row(3, .doubleClick, .missionControl)
        #expect(ButtonPlanner.plan(button: 3, clickCount: 1, bindings: [click, double]) == .waitForDoubleClick(click))
        #expect(ButtonPlanner.plan(button: 3, clickCount: 2, bindings: [click, double]) == .perform(double))
    }

    @Test("Double click only: single clicks keep their usual job")
    func doubleOnly() {
        let double = row(4, .doubleClick, .showDesktop)
        #expect(ButtonPlanner.plan(button: 4, clickCount: 1, bindings: [double]) == .passThrough)
        #expect(ButtonPlanner.plan(button: 4, clickCount: 2, bindings: [double]) == .perform(double))
    }

    @Test("Picker groups list every action exactly once")
    func groupsComplete() {
        let grouped = MouseButtonAction.groups.flatMap { $0 }
        #expect(grouped.count == MouseButtonAction.allCases.count)
        #expect(Set(grouped) == Set(MouseButtonAction.allCases))
    }

    @Test("Shortcut-based actions send the expected keys")
    func shortcuts() {
        #expect(MouseButtonAction.lookUp.behavior == .keys(KeyCombo(kVK_ANSI_D, [.maskControl, .maskCommand])))
        #expect(MouseButtonAction.copy.behavior == .keys(KeyCombo(kVK_ANSI_C, .maskCommand)))
        #expect(MouseButtonAction.systemDefault.behavior == .passThrough)
        #expect(MouseButtonAction.nothing.behavior == .swallow)
        #expect(MouseButtonAction.middleClick.behavior == .middleClick)
    }

    @Test("Launchpad opens the Apps launcher that replaced it")
    func launchpad() {
        guard case .openApp(let url) = MouseButtonAction.launchpad.behavior else {
            Issue.record("expected an app"); return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Arrow shortcuts carry the flags the Dock expects")
    func arrowFlags() {
        guard case .keys(let combo) = MouseButtonAction.missionControl.behavior else {
            Issue.record("expected keys"); return
        }
        #expect(combo.keyCode == CGKeyCode(kVK_UpArrow))
        #expect(combo.flags.contains([.maskControl, .maskSecondaryFn, .maskNumericPad]))
    }

    @Test("Recorded shortcuts keep their modifiers and a readable name")
    func recorder() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option, .command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "4", charactersIgnoringModifiers: "4",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_4)))
        let binding = ShortcutRecorder.binding(for: event)
        #expect(binding.display == "⌥⌘4")
        #expect(binding.combo.keyCode == CGKeyCode(kVK_ANSI_4))
        #expect(binding.combo.flags == [.maskAlternate, .maskCommand])
    }

    @Test("Button names count from 1, like mouse software does")
    func names() {
        #expect(String(localized: ButtonBinding.name(of: 3)).contains("4"))
    }
}

@Suite("Mouse scrolling")
struct MouseScrollTests {
    private func scrollEvent(units: CGScrollEventUnit, vertical: Int32, horizontal: Int32) throws -> CGEvent {
        try #require(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                             wheel1: vertical, wheel2: horizontal, wheel3: 0))
    }

    @Test("Wheel mice are detected; continuous (trackpad-like) scrolling isn't")
    func wheelDetection() throws {
        #expect(MouseEventTap.isFromScrollWheel(try scrollEvent(units: .line, vertical: 1, horizontal: 0)))
        #expect(!MouseEventTap.isFromScrollWheel(try scrollEvent(units: .pixel, vertical: 10, horizontal: 0)))
    }

    @Test("Reversing flips every delta field on one axis only")
    func reverse() throws {
        let event = try scrollEvent(units: .line, vertical: 3, horizontal: -2)
        MouseEventTap.scale(event, vertical: -1, horizontal: 1)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) < 0)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) < 0)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -2)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) < 0)
    }

    @Test("Speed scales the distance; slowing down never drops a notch")
    func speed() throws {
        let fast = try scrollEvent(units: .line, vertical: 2, horizontal: 0)
        let before = fast.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        MouseEventTap.scale(fast, vertical: 2, horizontal: 1)
        #expect(fast.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 4)
        #expect(fast.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == before * 2)

        let slow = try scrollEvent(units: .line, vertical: 1, horizontal: 0)
        MouseEventTap.scale(slow, vertical: 0.5, horizontal: 1)
        #expect(slow.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1)
    }

    @Test("Speed and direction combine into one factor per axis")
    func factors() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.scrollSpeed = 2
        settings.reverseVertical = true
        settings.reverseHorizontal = false
        let factors = MouseEventTap.factors(for: settings)
        #expect(factors.vertical == -2)
        #expect(factors.horizontal == 2)
    }
}

@Suite("Smooth scrolling")
struct SmoothScrollerTests {
    private func run(_ scroller: inout SmoothScroller, maxFrames: Int = 500) -> (x: Int, y: Int, frames: Int) {
        var x = 0, y = 0, frames = 0
        while let step = scroller.step() {
            x += Int(step.dx); y += Int(step.dy); frames += 1
            if frames > maxFrames { break }
        }
        return (x, y, frames)
    }

    @Test("The glide covers exactly the requested distance", arguments: [40.0, 123.0, -80.0, 7.5])
    func exactDistance(distance: Double) {
        var scroller = SmoothScroller()
        scroller.add(dx: distance / 2, dy: distance)
        let result = run(&scroller)
        #expect(result.y == Int(distance.rounded()))
        #expect(abs(result.x - Int((distance / 2).rounded())) <= 1)
    }

    @Test("A glide ends quickly (well under half a second at 120 fps)")
    func ends() {
        var scroller = SmoothScroller()
        scroller.add(dx: 0, dy: 400)
        let result = run(&scroller)
        #expect(result.frames < 60)
        #expect(scroller.isIdle)
    }

    @Test("Steps shrink as the glide eases out")
    func easesOut() {
        var scroller = SmoothScroller()
        scroller.add(dx: 0, dy: 200)
        let first = scroller.step()?.dy ?? 0
        _ = scroller.step(); _ = scroller.step()
        let later = scroller.step()?.dy ?? 0
        #expect(first > later)
    }

    @Test("Reversing direction drops the old glide")
    func directionChange() {
        var scroller = SmoothScroller()
        scroller.add(dx: 0, dy: 200)
        _ = scroller.step()
        scroller.add(dx: 0, dy: -40)
        let result = run(&scroller)
        #expect(result.y == -40)
    }
}
