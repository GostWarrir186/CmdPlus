import CoreGraphics
import Foundation
import Observation

/// Mouse module settings, stored in UserDefaults.
@Observable
final class MouseSettings {
    private enum Key {
        static let reverseVertical = "mouse.reverseVertical"
        static let reverseHorizontal = "mouse.reverseHorizontal"
        static let smoothness = "mouse.smoothness"
        static let trackpadSimulation = "mouse.trackpadSimulation"
        static let speed = "mouse.speed"
        static let precision = "mouse.precision"
        static let modifiers = "mouse.modifiers"
        static let buttonBindings = "mouse.buttonBindings"
        // Older builds.
        static let legacySmooth = "mouse.smoothScrolling"
        static let legacySpeed = "mouse.scrollSpeed"
    }

    var reverseVertical: Bool {
        didSet { defaults.set(reverseVertical, forKey: Key.reverseVertical); onChange() }
    }

    var reverseHorizontal: Bool {
        didSet { defaults.set(reverseHorizontal, forKey: Key.reverseHorizontal); onChange() }
    }

    var smoothness: ScrollSmoothness {
        didSet { defaults.set(smoothness.rawValue, forKey: Key.smoothness); onChange() }
    }

    /// Smooth scrolling sends trackpad-style gesture phases, so apps like Safari
    /// react to the wheel as they would to a trackpad.
    var trackpadSimulation: Bool {
        didSet { defaults.set(trackpadSimulation, forKey: Key.trackpadSimulation); onChange() }
    }

    var speed: ScrollSpeed {
        didSet { defaults.set(speed.rawValue, forKey: Key.speed); onChange() }
    }

    /// Slow wheel movement scrolls in small steps.
    var precision: Bool {
        didSet { defaults.set(precision, forKey: Key.precision); onChange() }
    }

    /// Which key does what while scrolling. A role without a key is off.
    var modifiers: [ScrollModifierRole: ScrollModifierKey] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: modifiers.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: Key.modifiers)
            onChange()
        }
    }

    /// Button assignments, in the order they were added.
    var bindings: [ButtonBinding] {
        didSet {
            if let data = try? JSONEncoder().encode(bindings) {
                defaults.set(data, forKey: Key.buttonBindings)
            }
            onChange()
        }
    }

    /// True while the "+" field in Settings is waiting for a click, so the event
    /// tap lets every button through to it.
    @ObservationIgnored var isCapturingButtons = false
    /// The module uses this to start or stop the event tap.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reverseVertical = defaults.object(forKey: Key.reverseVertical) as? Bool ?? true
        reverseHorizontal = defaults.object(forKey: Key.reverseHorizontal) as? Bool ?? false
        trackpadSimulation = defaults.object(forKey: Key.trackpadSimulation) as? Bool ?? true
        precision = defaults.object(forKey: Key.precision) as? Bool ?? false

        // Migration: older builds had an on/off switch and a 0.5–3× slider.
        if let saved = defaults.string(forKey: Key.smoothness).flatMap(ScrollSmoothness.init) {
            smoothness = saved
        } else if let legacy = defaults.object(forKey: Key.legacySmooth) as? Bool {
            smoothness = legacy ? .regular : .off
        } else {
            smoothness = .regular
        }
        if let saved = defaults.string(forKey: Key.speed).flatMap(ScrollSpeed.init) {
            speed = saved
        } else if let legacy = defaults.object(forKey: Key.legacySpeed) as? Double {
            speed = .nearest(to: legacy)
        } else {
            speed = .medium
        }
        defaults.removeObject(forKey: Key.legacySmooth)
        defaults.removeObject(forKey: Key.legacySpeed)

        if let saved = defaults.dictionary(forKey: Key.modifiers) as? [String: String] {
            modifiers = Dictionary(uniqueKeysWithValues: saved.compactMap { role, key in
                guard let role = ScrollModifierRole(rawValue: role), let key = ScrollModifierKey(rawValue: key) else { return nil }
                return (role, key)
            })
        } else {
            modifiers = Dictionary(uniqueKeysWithValues: ScrollModifierRole.allCases.map { ($0, $0.defaultKey) })
        }

        bindings = defaults.data(forKey: Key.buttonBindings)
            .flatMap { try? JSONDecoder().decode([ButtonBinding].self, from: $0) }
            ?? Self.migrateFixedButtons(in: defaults)
    }

    /// Nothing to do means no event tap at all — zero cost.
    var needsEventTap: Bool {
        reverseVertical || reverseHorizontal || smoothness != .off || speed != .medium || precision
            || !modifiers.isEmpty || bindings.contains { $0.action.interceptsButton }
    }

    /// Assigns a key to a role. A key can only do one thing, so it's taken off any other role.
    func setModifier(_ key: ScrollModifierKey?, for role: ScrollModifierRole) {
        var updated = modifiers
        if let key {
            for (other, otherKey) in updated where otherKey == key && other != role {
                updated[other] = nil
            }
        }
        updated[role] = key
        modifiers = updated
    }

    /// Roles whose key is held in these flags.
    func activeRoles(for flags: CGEventFlags) -> Set<ScrollModifierRole> {
        Set(modifiers.filter { flags.contains($0.value.eventFlag) }.map(\.key))
    }

    func bindings(forButton button: Int64) -> [ButtonBinding] {
        bindings.filter { $0.button == button }
    }

    /// Adds a row for a button and trigger, unless it's already there.
    /// Returns the row's id either way.
    @discardableResult
    func addBinding(button: Int64, trigger: ButtonTrigger) -> UUID? {
        guard ButtonBinding.isAssignable(button) else { return nil }
        if let existing = bindings.first(where: { $0.button == button && $0.trigger == trigger }) {
            return existing.id
        }
        let binding = ButtonBinding(button: button, trigger: trigger, action: .systemDefault)
        bindings.append(binding)
        return binding.id
    }

    func removeBinding(_ id: UUID) {
        bindings.removeAll { $0.id == id }
    }

    /// Migration: early builds had two fixed pickers for buttons 4 and 5.
    private static func migrateFixedButtons(in defaults: UserDefaults) -> [ButtonBinding] {
        var result: [ButtonBinding] = []
        for (key, button) in [("mouse.backButton", Int64(3)), ("mouse.forwardButton", Int64(4))] {
            if let action = defaults.string(forKey: key).flatMap(MouseButtonAction.init), action != .systemDefault {
                result.append(ButtonBinding(button: button, trigger: .click, action: action))
            }
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "mouse.backShortcut")
        defaults.removeObject(forKey: "mouse.forwardShortcut")
        return result
    }
}
