import Foundation
import Testing
@testable import CmdPlus

@Suite("Saving, loading and cleanup")
struct HistoryPersistenceTests {
    @Test("History round-trips through disk unchanged")
    func roundTrip() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 10)
        store.addText("first", source: SourceApp(name: "Safari", bundleID: "com.apple.Safari"))
        store.addFiles([URL(filePath: "/tmp/a.txt")], source: nil)
        store.addText("pinned", source: nil)
        store.togglePin(store.items[0].id)
        store.save(synchronously: true)

        let reloaded = await env.makeStore(limit: 10)
        #expect(reloaded.items == store.items)
        #expect(reloaded.items.first?.isPinned == true)
        #expect(reloaded.items.last?.sourceAppName == "Safari")
    }

    @Test("Missing history file means empty history, no errors")
    func missingFile() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore()
        #expect(store.items.isEmpty)
        #expect(store.isLoaded)
    }

    @Test("Saving before load doesn't overwrite the file")
    func noSaveBeforeLoad() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let saved = [ClipboardItem(kind: .text, text: "old item")]
        try env.writeHistory(saved)

        let store = ClipboardStore(settings: env.makeSettings(), directory: env.directory)
        store.save(synchronously: true)

        let data = try Data(contentsOf: env.historyURL)
        #expect(try JSONDecoder().decode([ClipboardItem].self, from: data) == saved)
    }

    @Test("Corrupt file is moved aside, not lost")
    func corruptFileBackedUp() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: env.historyURL)

        let store = await env.makeStore()
        #expect(store.items.isEmpty)
        let backup = env.directory.appending(path: "history.corrupt.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try Data(contentsOf: backup) == Data("not json".utf8))
    }

    @Test("Items copied during load stay on top")
    func captureDuringLoad() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try env.writeHistory([ClipboardItem(kind: .text, text: "from file")])

        let store = ClipboardStore(settings: env.makeSettings(limit: 10), directory: env.directory)
        store.addText("fresh", source: nil)
        await store.load()
        #expect(store.texts == ["fresh", "from file"])
    }

    @Test("Current limit is applied on load")
    func limitAppliedOnLoad() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let saved = (1...5).map { ClipboardItem(kind: .text, text: "\($0)") }
        try env.writeHistory(saved)
        let store = await env.makeStore(limit: 2)
        #expect(store.texts == ["1", "2"])
    }

    @Test("Migration: password entries from older versions are dropped on load")
    func legacyPasswordsDropped() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try env.writeHistory([
            ClipboardItem(kind: .text, isSecret: true, sourceAppName: "1Password"),
            ClipboardItem(kind: .text, isPinned: true, isSecret: true, sourceAppName: "1Password"),
            ClipboardItem(kind: .text, text: "regular text"),
        ])

        let store = await env.makeStore(limit: 10)
        #expect(store.texts == ["regular text"])

        // The cleaned-up history is written back to disk.
        store.save(synchronously: true)
        let saved = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: env.historyURL))
        #expect(!saved.contains { $0.isSecret })
    }

    @Test("Migration: old password settings are removed")
    func legacyPasswordSettingsRemoved() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.defaults.set(true, forKey: "clipboard.captureSecrets")
        env.defaults.set("oneDay", forKey: "clipboard.secretRetention")
        _ = env.makeSettings()
        #expect(env.defaults.object(forKey: "clipboard.captureSecrets") == nil)
        #expect(env.defaults.object(forKey: "clipboard.secretRetention") == nil)
    }

    @Test("Delete and clear unpinned")
    func deleteAndClear() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 10)
        for text in ["a", "b", "c"] { store.addText(text, source: nil) }
        store.togglePin(store.items[1].id) // "b"
        store.delete(store.items[0].id)    // "c"
        #expect(store.texts == ["b", "a"])
        store.clearUnpinned()
        #expect(store.texts == ["b"])
    }

    @Test("\"Paste directly\" is on by default and persists")
    func pasteDirectlySetting() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        #expect(env.makeSettings().pasteDirectly)
        env.makeSettings().pasteDirectly = false
        #expect(!env.makeSettings().pasteDirectly)
    }
}
