import Foundation
import Testing
@testable import CmdPlus

@Suite("App language")
struct AppLanguageTests {
    @Test("Defaults to the system language")
    func defaultIsSystem() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        #expect(AppLanguage.saved(in: env.defaults) == .system)
    }

    @Test("A chosen language overrides the app's language list", arguments: [AppLanguage.english, .russian])
    func override(language: AppLanguage) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        language.save(in: env.defaults)
        #expect(AppLanguage.saved(in: env.defaults) == language)
        #expect(env.defaults.persistentDomain(forName: env.suiteName)?["AppleLanguages"] as? [String] == [language.rawValue])
    }

    @Test("Back to System removes the override")
    func backToSystem() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        AppLanguage.russian.save(in: env.defaults)
        AppLanguage.system.save(in: env.defaults)
        #expect(AppLanguage.saved(in: env.defaults) == .system)
        #expect(env.defaults.persistentDomain(forName: env.suiteName)?["AppleLanguages"] == nil)
    }

    @Test("The app ships both languages it offers")
    func localizationsExist() {
        for language in AppLanguage.allCases where language != .system {
            #expect(Bundle.main.localizations.contains(language.rawValue), "\(language)")
        }
    }
}
