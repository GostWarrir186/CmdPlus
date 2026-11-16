import Foundation
import Observation

/// Mouse module settings, stored in UserDefaults.
@Observable
final class MouseSettings {
    private enum Key {
        static let reverseVertical = "mouse.reverseVertical"
        static let reverseHorizontal = "mouse.reverseHorizontal"
        static let backButton = "mouse.backButton"
        static let forwardButton = "mouse.forwardButton"
    }

    var reverseVertical: Bool {
        didSet { defaults.set(reverseVertical, forKey: Key.reverseVertical); onChange() }
    }

    var reverseHorizontal: Bool {
        didSet { defaults.set(reverseHorizontal, forKey: Key.reverseHorizontal); onChange() }
    }

    /// Button 4 — the rear side button on most mice.
    var backButton: MouseButtonAction {
        didSet { defaults.set(backButton.rawValue, forKey: Key.backButton); onChange() }
    }

    /// Button 5 — the front side button.
    var forwardButton: MouseButtonAction {
        didSet { defaults.set(forwardButton.rawValue, forKey: Key.forwardButton); onChange() }
    }

    /// The module uses this to start or stop the event tap.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reverseVertical = defaults.object(forKey: Key.reverseVertical) as? Bool ?? true
        reverseHorizontal = defaults.object(forKey: Key.reverseHorizontal) as? Bool ?? false
        backButton = defaults.string(forKey: Key.backButton).flatMap(MouseButtonAction.init) ?? .systemDefault
        forwardButton = defaults.string(forKey: Key.forwardButton).flatMap(MouseButtonAction.init) ?? .systemDefault
    }

    /// Nothing to do means no event tap at all — zero cost.
    var needsEventTap: Bool {
        reverseVertical || reverseHorizontal || backButton.interceptsButton || forwardButton.interceptsButton
    }

    /// Action for a raw mouse button number (3 = button 4, 4 = button 5).
    func action(forButton number: Int64) -> MouseButtonAction {
        switch number {
        case 3: backButton
        case 4: forwardButton
        default: .systemDefault
        }
    }
}
