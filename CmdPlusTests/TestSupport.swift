import Foundation
@testable import CmdPlus

/// Isolated test environment: its own temp folder and UserDefaults,
/// so real history and settings are never touched.
struct TestEnvironment {
    let directory: URL
    let defaults: UserDefaults
    let suiteName: String

    init() {
        suiteName = "CmdPlusTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        directory = FileManager.default.temporaryDirectory
            .appending(path: "CmdPlusTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var historyURL: URL { directory.appending(path: "history.json") }

    func makeSettings(limit: Int? = nil) -> ClipboardSettings {
        let settings = ClipboardSettings(defaults: defaults)
        if let limit { settings.historyLimit = limit }
        return settings
    }

    /// Creates a store and waits for it to load, like at app launch.
    func makeStore(limit: Int? = nil, settings: ClipboardSettings? = nil) async -> ClipboardStore {
        let store = ClipboardStore(settings: settings ?? makeSettings(limit: limit), directory: directory)
        await store.load()
        return store
    }

    func writeHistory(_ items: [ClipboardItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: historyURL)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

extension ClipboardStore {
    var texts: [String?] { items.map(\.text) }
}
