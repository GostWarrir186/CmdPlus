import Foundation
import Observation

/// Module settings, stored in UserDefaults.
@Observable
final class ClipboardSettings {
    static let limitPresets = [5, 10, 25, 50, 100, 250, 500]
    static let defaultLimit = 10
    static let limitRange = 1...500

    private enum Key {
        static let historyLimit = "clipboard.historyLimit"
        static let pasteDirectly = "clipboard.pasteDirectly"
    }

    /// How many unpinned items to keep (pinned ones don't count).
    /// Always clamped to `limitRange`.
    var historyLimit: Int {
        didSet {
            let clamped = historyLimit.clamped(to: Self.limitRange)
            if clamped != historyLimit { historyLimit = clamped }
            defaults.set(historyLimit, forKey: Key.historyLimit)
        }
    }


    /// Choosing an item pastes it into the previous app. Needs Accessibility
    /// permission; without it the item is only copied.
    var pasteDirectly: Bool {
        didSet { defaults.set(pasteDirectly, forKey: Key.pasteDirectly) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Pass custom defaults in tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLimit = defaults.object(forKey: Key.historyLimit) as? Int ?? Self.defaultLimit
        historyLimit = savedLimit.clamped(to: Self.limitRange)
        pasteDirectly = defaults.object(forKey: Key.pasteDirectly) as? Bool ?? true
        // Migration: password settings from older versions.
        defaults.removeObject(forKey: "clipboard.captureSecrets")
        defaults.removeObject(forKey: "clipboard.secretRetention")
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
