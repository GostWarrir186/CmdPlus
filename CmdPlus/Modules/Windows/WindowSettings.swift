import Foundation
import Observation

/// Window module settings, stored in UserDefaults.
@Observable
final class WindowSettings {
    private enum Key {
        static let gap = "windows.gap"
        static let shortcuts = "windows.shortcuts"
    }

    var gap: WindowGap {
        didSet { defaults.set(gap.rawValue, forKey: Key.gap) }
    }

    /// Assigned shortcuts. An action missing here has none.
    var shortcuts: [WindowAction: KeyCombo] {
        didSet {
            let encoded = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(encoded) {
                defaults.set(data, forKey: Key.shortcuts)
            }
            onShortcutsChange()
        }
    }

    /// The module re-registers hotkeys when this fires.
    @ObservationIgnored var onShortcutsChange: () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gap = defaults.string(forKey: Key.gap).flatMap(WindowGap.init) ?? .none
        if let data = defaults.data(forKey: Key.shortcuts),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            shortcuts = Dictionary(uniqueKeysWithValues: saved.compactMap { key, combo in
                WindowAction(rawValue: key).map { ($0, combo) }
            })
        } else {
            shortcuts = Self.defaultShortcuts
        }
    }

    static var defaultShortcuts: [WindowAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: WindowAction.allCases.compactMap { action in
            action.defaultShortcut.map { (action, $0) }
        })
    }

    /// Assigns a shortcut. A shortcut can only trigger one action, so it's taken
    /// off any other action.
    func setShortcut(_ combo: KeyCombo?, for action: WindowAction) {
        var updated = shortcuts
        if let combo {
            for (other, otherCombo) in updated where otherCombo == combo && other != action {
                updated[other] = nil
            }
        }
        updated[action] = combo
        shortcuts = updated
    }

    func resetShortcuts() {
        shortcuts = Self.defaultShortcuts
    }
}
