import Foundation
import Observation

/// Сколько хранить пароли и коды.
enum SecretRetention: String, CaseIterable, Identifiable {
    case oneHour
    case oneDay
    case oneWeek
    case forever

    var id: String { rawValue }

    /// `nil` — хранить всегда.
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

/// Настройки модуля. Лежат в UserDefaults — это обычные параметры,
/// сами пароли сюда никогда не попадают.
@Observable
final class ClipboardSettings {
    /// Готовые варианты лимита в настройках.
    static let limitPresets = [5, 10, 25, 50, 100, 250, 500]
    static let defaultLimit = 10
    /// Допустимые значения для своего числа.
    static let limitRange = 1...500

    private enum Key {
        static let historyLimit = "clipboard.historyLimit"
        static let captureSecrets = "clipboard.captureSecrets"
        static let secretRetention = "clipboard.secretRetention"
    }

    /// Сколько незакреплённых записей хранить. Закреплённые в лимит не входят.
    /// Значение всегда держится в пределах `limitRange`.
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

    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults` можно подменить — например, в тестах.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLimit = defaults.object(forKey: Key.historyLimit) as? Int ?? Self.defaultLimit
        historyLimit = savedLimit.clamped(to: Self.limitRange)
        captureSecrets = defaults.object(forKey: Key.captureSecrets) as? Bool ?? true
        secretRetention = defaults.string(forKey: Key.secretRetention)
            .flatMap(SecretRetention.init(rawValue:)) ?? .oneDay
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
