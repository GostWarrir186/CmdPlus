import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import CmdPlus

@Suite("Mouse settings")
struct MouseSettingsTests {
    @Test("Defaults: regular smoothness, medium speed, standard modifiers, no button rows")
    func defaults() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        #expect(settings.smoothness == .regular)
        #expect(settings.trackpadSimulation)
        #expect(settings.speed == .medium)
        #expect(!settings.precision)
        #expect(settings.reverseVertical)
        #expect(!settings.reverseHorizontal)
        #expect(settings.modifiers == [.horizontal: .shift, .zoom: .command, .swift: .control, .precise: .option])
        #expect(settings.bindings.isEmpty)
    }

    @Test("Everything persists across launches, including recorded shortcuts")
    func persistence() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.smoothness = .high
        settings.speed = .high
        settings.precision = true
        settings.setModifier(nil, for: .zoom)
        settings.reverseHorizontal = true
        let id = try #require(settings.addBinding(button: 3, trigger: .click))
        let index = try #require(settings.bindings.firstIndex { $0.id == id })
        settings.bindings[index].action = .keyboardShortcut
        settings.bindings[index].shortcut = ShortcutBinding(combo: KeyCombo(kVK_ANSI_4, [.maskAlternate, .maskCommand]), display: "⌥⌘4")

        let reloaded = MouseSettings(defaults: env.defaults)
        #expect(reloaded.smoothness == .high)
        #expect(reloaded.speed == .high)
        #expect(reloaded.precision)
        #expect(reloaded.modifiers[.zoom] == nil)
        #expect(reloaded.modifiers[.horizontal] == .shift)
        #expect(reloaded.reverseHorizontal)
        #expect(reloaded.bindings == settings.bindings)
        #expect(reloaded.bindings.first?.shortcut?.display == "⌥⌘4")
    }

    @Test("Migration: old on/off smoothing and speed slider", arguments: [
        (false, 0.5, ScrollSmoothness.off, ScrollSpeed.low),
        (true, 1.0, .regular, .medium),
        (true, 2.5, .regular, .high),
    ])
    func legacyScrollSettings(smooth: Bool, speed: Double, smoothness: ScrollSmoothness, expectedSpeed: ScrollSpeed) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.defaults.set(smooth, forKey: "mouse.smoothScrolling")
        env.defaults.set(speed, forKey: "mouse.scrollSpeed")
        let settings = MouseSettings(defaults: env.defaults)
        #expect(settings.smoothness == smoothness)
        #expect(settings.speed == expectedSpeed)
        #expect(env.defaults.object(forKey: "mouse.smoothScrolling") == nil)
    }

    @Test("A modifier key can only do one thing")
    func modifierUnique() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.setModifier(.shift, for: .zoom)
        #expect(settings.modifiers[.zoom] == .shift)
        #expect(settings.modifiers[.horizontal] == nil)
    }

    @Test("No event tap when there's nothing to do")
    func tapOnlyWhenNeeded() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = MouseSettings(defaults: env.defaults)
        settings.reverseVertical = false
        settings.smoothness = .off
        for role in ScrollModifierRole.allCases { settings.setModifier(nil, for: role) }
        #expect(!settings.needsEventTap)

        // A row left on "System Default" still costs nothing.
        let id = try #require(settings.addBinding(button: 3, trigger: .click))
        #expect(!settings.needsEventTap)
        settings.bindings[settings.bindings.firstIndex { $0.id == id }!].action = .missionControl
        #expect(settings.needsEventTap)

        settings.removeBinding(id)
        settings.speed = .high
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
        settings.smoothness = .off
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

    private func settings(_ env: TestEnvironment) -> MouseSettings {
        let settings = MouseSettings(defaults: env.defaults)
        settings.reverseVertical = false
        return settings
    }

    private func notch(_ vertical: Double = 1, accelerated: Double? = nil, flags: CGEventFlags = []) -> ScrollPlanner.Input {
        .init(wholeVertical: vertical, acceleratedVertical: accelerated ?? vertical,
              wholeHorizontal: 0, acceleratedHorizontal: 0, flags: flags)
    }

    @Test("Wheel mice are detected; continuous (trackpad-like) scrolling isn't")
    func wheelDetection() throws {
        #expect(MouseEventTap.isFromScrollWheel(try scrollEvent(units: .line, vertical: 1, horizontal: 0)))
        #expect(!MouseEventTap.isFromScrollWheel(try scrollEvent(units: .pixel, vertical: 10, horizontal: 0)))
    }

    @Test("A slow notch scrolls a whole line; with Precision it stays small")
    func slowNotch() {
        #expect(ScrollPlanner.lines(whole: 1, accelerated: 0.1, precise: false) == 1)
        #expect(ScrollPlanner.lines(whole: 1, accelerated: 0.1, precise: true) == 0.1)
        #expect(ScrollPlanner.lines(whole: 1, accelerated: -6.5, precise: false) == -6.5)
        #expect(ScrollPlanner.lines(whole: 1, accelerated: 6.5, precise: true) == 6.5)
    }

    @Test("Speed presets scale the distance", arguments: [(ScrollSpeed.low, 0.6), (.medium, 1.0), (.high, 1.8)])
    func speed(speed: ScrollSpeed, expected: Double) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = settings(env)
        settings.speed = speed
        #expect(ScrollPlanner.plan(notch(), settings: settings) == .scroll(vertical: expected, horizontal: 0, removeFlags: []))
    }

    @Test("Reverse flips the direction")
    func reverse() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = settings(env)
        settings.reverseVertical = true
        #expect(ScrollPlanner.plan(notch(2), settings: settings) == .scroll(vertical: -2, horizontal: 0, removeFlags: []))
    }

    @Test("⇧ turns the wheel horizontal and isn't passed on to the app")
    func horizontalModifier() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let plan = ScrollPlanner.plan(notch(1, flags: .maskShift), settings: settings(env))
        #expect(plan == .scroll(vertical: 0, horizontal: 1, removeFlags: .maskShift))
    }

    @Test("⌃ scrolls swiftly, ⌥ precisely")
    func swiftAndPrecise() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = settings(env)
        #expect(ScrollPlanner.plan(notch(1, flags: .maskControl), settings: settings)
                == .scroll(vertical: 3, horizontal: 0, removeFlags: .maskControl))
        #expect(ScrollPlanner.plan(notch(1, flags: .maskAlternate), settings: settings)
                == .scroll(vertical: 0.25, horizontal: 0, removeFlags: .maskAlternate))
    }

    @Test("⌘ zooms in the direction the wheel moves")
    func zoom() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = settings(env)
        #expect(ScrollPlanner.plan(notch(1, flags: .maskCommand), settings: settings) == .zoom(zoomIn: true))
        #expect(ScrollPlanner.plan(notch(-1, flags: .maskCommand), settings: settings) == .zoom(zoomIn: false))
    }

    @Test("Removed modifiers do nothing special")
    func removedModifier() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = settings(env)
        settings.setModifier(nil, for: .zoom)
        #expect(ScrollPlanner.plan(notch(1, flags: .maskCommand), settings: settings)
                == .scroll(vertical: 1, horizontal: 0, removeFlags: []))
    }

    @Test("Rewriting a notch sets every field, fractional value intact")
    func write() throws {
        let event = try scrollEvent(units: .line, vertical: 1, horizontal: 0)
        MouseEventTap.write(event, vertical: -2.5, horizontal: 0.3)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -2.5)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -25)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 1) // never drop a notch
    }
}

@Suite("Smooth scrolling")
struct SmoothScrollerTests {
    private func run(_ scroller: inout SmoothScroller, maxFrames: Int = 500) -> (x: Int, y: Int, phases: [SmoothScroller.Phase]) {
        var x = 0, y = 0, phases: [SmoothScroller.Phase] = []
        while let step = scroller.step() {
            x += Int(step.dx); y += Int(step.dy); phases.append(step.phase)
            if phases.count > maxFrames { break }
        }
        return (x, y, phases)
    }

    @Test("The glide covers exactly the requested distance", arguments: [40.0, 123.0, -80.0, 7.5])
    func exactDistance(distance: Double) {
        var scroller = SmoothScroller()
        scroller.add(dx: distance / 2, dy: distance)
        let result = run(&scroller)
        // Whole pixels only, so a fractional distance may land half a pixel off.
        #expect(abs(Double(result.y) - distance) <= 0.5)
        #expect(abs(Double(result.x) - distance / 2) <= 1)
    }

    @Test("Phases go began → changed… → ended, like a trackpad")
    func phases() {
        var scroller = SmoothScroller()
        scroller.add(dx: 0, dy: 120)
        let phases = run(&scroller).phases
        #expect(phases.first == .began)
        #expect(phases.last == .ended)
        #expect(phases.dropFirst().dropLast().allSatisfy { $0 == .changed })
        #expect(scroller.isIdle)
    }

    @Test("High smoothness glides longer than Regular, both end in time",
          arguments: [(ScrollSmoothness.regular, 50), (.high, 100)])
    func glideLength(smoothness: ScrollSmoothness, maxFrames: Int) throws {
        var scroller = SmoothScroller(stepFraction: try #require(smoothness.stepFraction))
        scroller.add(dx: 0, dy: 400)
        #expect(run(&scroller).phases.count < maxFrames)
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
        #expect(run(&scroller).y == -40)
    }

    @Test("Trackpad phase values match macOS")
    func phaseValues() {
        #expect(MouseEventTap.phaseValue(.began) == 1)
        #expect(MouseEventTap.phaseValue(.changed) == 2)
        #expect(MouseEventTap.phaseValue(.ended) == 4)
    }
}
