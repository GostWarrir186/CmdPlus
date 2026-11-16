import Foundation
import Observation

enum SecretRetention: String, CaseIterable, Identifiable {
    case oneHour
    case oneDay
    case oneWeek
    case forever

    var id: String { rawValue }

    /// `nil` means keep forever.
    var interval: TimeInterval? {
        switch self {
        case .oneHour: 60 * 60
        case .oneDay: 24 * 60 * 60
        case .oneWeek: 7 * 24 * 60 * 60
        case .forever: nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .oneHour: "1 Hour"
        case .oneDay: "24 Hours"
        case .oneWeek: "7 Days"
        case .forever: "Forever"
        }
    }
}

/// Module settings, stored in UserDefaults. Passwords never end up here.
@Observable
final class ClipboardSettings {
    static let limitPresets = [5, 10, 25, 50, 100, 250, 500]
    static let defaultLimit = 10
    static let limitRange = 1...500

    private enum Key {
        static let historyLimit = "clipboard.historyLimit"
        static let captureSecrets = "clipboard.captureSecrets"
        static let secretRetention = "clipboard.secretRetention"
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

    var captureSecrets: Bool {
        didSet { defaults.set(captureSecrets, forKey: Key.captureSecrets) }
    }

    var secretRetention: SecretRetention {
        didSet { defaults.set(secretRetention.rawValue, forKey: Key.secretRetention) }
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
        captureSecrets = defaults.object(forKey: Key.captureSecrets) as? Bool ?? true
        secretRetention = defaults.string(forKey: Key.secretRetention)
            .flatMap(SecretRetention.init(rawValue:)) ?? .oneDay
        pasteDirectly = defaults.object(forKey: Key.pasteDirectly) as? Bool ?? true
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
