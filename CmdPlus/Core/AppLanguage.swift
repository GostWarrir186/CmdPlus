import AppKit

/// The app's interface language. macOS picks the language when the app starts,
/// so a change applies after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    static let storageKey = "app.language"
    /// The system key that overrides the language list for this app only.
    private static let appleLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    /// Language names are always shown in their own language.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .russian: "Русский"
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: storageKey).flatMap(AppLanguage.init) ?? .system
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
        if self == .system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// The language the running app actually uses.
    static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Whether this choice differs from what's on screen right now.
    var needsRelaunch: Bool {
        switch self {
        case .system:
            let systemPreferred = Bundle.preferredLocalizations(
                from: Bundle.main.localizations,
                forPreferences: Locale.preferredLanguages
            ).first ?? "en"
            return systemPreferred != Self.current
        default:
            return rawValue != Self.current
        }
    }

    /// Starts a fresh copy of CmdPlus and quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
