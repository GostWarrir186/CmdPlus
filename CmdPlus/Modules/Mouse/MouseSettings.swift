import Foundation
import Observation

/// Mouse module settings, stored in UserDefaults.
@Observable
final class MouseSettings {
    static let speedRange = 0.5...3.0

    private enum Key {
        static let reverseVertical = "mouse.reverseVertical"
        static let reverseHorizontal = "mouse.reverseHorizontal"
        static let smoothScrolling = "mouse.smoothScrolling"
        static let scrollSpeed = "mouse.scrollSpeed"
        static let buttonBindings = "mouse.buttonBindings"
    }

    var reverseVertical: Bool {
        didSet { defaults.set(reverseVertical, forKey: Key.reverseVertical); onChange() }
    }

    var reverseHorizontal: Bool {
        didSet { defaults.set(reverseHorizontal, forKey: Key.reverseHorizontal); onChange() }
    }

    var smoothScrolling: Bool {
        didSet { defaults.set(smoothScrolling, forKey: Key.smoothScrolling); onChange() }
    }

    /// Multiplier for how far one wheel notch scrolls. Always within `speedRange`.
    var scrollSpeed: Double {
        didSet {
            let clamped = scrollSpeed.clamped(to: Self.speedRange)
            if clamped != scrollSpeed { scrollSpeed = clamped }
            defaults.set(scrollSpeed, forKey: Key.scrollSpeed)
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
        smoothScrolling = defaults.object(forKey: Key.smoothScrolling) as? Bool ?? true
        scrollSpeed = (defaults.object(forKey: Key.scrollSpeed) as? Double ?? 1).clamped(to: Self.speedRange)
        bindings = defaults.data(forKey: Key.buttonBindings)
            .flatMap { try? JSONDecoder().decode([ButtonBinding].self, from: $0) }
            ?? Self.migrateFixedButtons(in: defaults)
    }

    /// Nothing to do means no event tap at all — zero cost.
    var needsEventTap: Bool {
        reverseVertical || reverseHorizontal || smoothScrolling || scrollSpeed != 1
            || bindings.contains { $0.action.interceptsButton }
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
