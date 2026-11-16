import Foundation
import Testing
@testable import CmdPlus

@Suite("Сохранение, загрузка и удаление старых записей")
struct HistoryPersistenceTests {
    @Test("История сохраняется на диск и загружается обратно без потерь")
    func roundTrip() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 10)
        store.addText("первая", source: SourceApp(name: "Safari", bundleID: "com.apple.Safari"))
        store.addFiles([URL(filePath: "/tmp/a.txt")], source: nil)
        store.addText("закреплённая", source: nil)
        store.togglePin(store.items[0].id)
        store.save(synchronously: true)

        let reloaded = await env.makeStore(limit: 10)
        #expect(reloaded.items == store.items)
        #expect(reloaded.items.first?.isPinned == true)
        #expect(reloaded.items.last?.sourceAppName == "Safari")
    }

    @Test("Нет файла истории — пустая история без ошибок")
    func missingFile() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore()
        #expect(store.items.isEmpty)
        #expect(store.isLoaded)
    }

    @Test("До загрузки история не перезаписывает файл")
    func noSaveBeforeLoad() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let saved = [ClipboardItem(kind: .text, text: "старая запись")]
        try env.writeHistory(saved)

        let store = ClipboardStore(settings: env.makeSettings(), directory: env.directory)
        store.save(synchronously: true)

        let data = try Data(contentsOf: env.historyURL)
        #expect(try JSONDecoder().decode([ClipboardItem].self, from: data) == saved)
    }

    @Test("Повреждённый файл откладывается в сторону, а не теряется")
    func corruptFileBackedUp() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
        try Data("не json".utf8).write(to: env.historyURL)

        let store = await env.makeStore()
        #expect(store.items.isEmpty)
        let backup = env.directory.appending(path: "history.corrupt.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try Data(contentsOf: backup) == Data("не json".utf8))
    }

    @Test("Скопированное во время загрузки остаётся сверху")
    func captureDuringLoad() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try env.writeHistory([ClipboardItem(kind: .text, text: "из файла")])

        let store = ClipboardStore(settings: env.makeSettings(limit: 10), directory: env.directory)
        store.addText("свежее", source: nil)
        await store.load()
        #expect(store.texts == ["свежее", "из файла"])
    }

    @Test("При загрузке применяется текущий лимит")
    func limitAppliedOnLoad() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let saved = (1...5).map { ClipboardItem(kind: .text, text: "\($0)") }
        try env.writeHistory(saved)
        let store = await env.makeStore(limit: 2)
        #expect(store.texts == ["1", "2"])
    }

    @Test("Пароли старше срока хранения удаляются, закреплённые и свежие остаются")
    func expiredSecretsPurged() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let old = Date.now.addingTimeInterval(-2 * 60 * 60)
        let saved = [
            ClipboardItem(kind: .text, createdAt: .now, isSecret: true, sourceAppName: "свежий"),
            ClipboardItem(kind: .text, createdAt: old, isSecret: true, sourceAppName: "старый"),
            ClipboardItem(kind: .text, createdAt: old, isPinned: true, isSecret: true, sourceAppName: "закреплён"),
            ClipboardItem(kind: .text, createdAt: old, text: "обычный старый текст"),
        ]
        try env.writeHistory(saved)

        let settings = env.makeSettings(limit: 10)
        settings.secretRetention = .oneHour
        let store = await env.makeStore(settings: settings)

        #expect(store.items.map(\.sourceAppName) == ["свежий", "закреплён", nil])
        #expect(store.items.last?.text == "обычный старый текст")
    }

    @Test("Срок «Навсегда» не удаляет пароли")
    func foreverKeepsSecrets() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let ancient = Date.now.addingTimeInterval(-365 * 24 * 60 * 60)
        try env.writeHistory([ClipboardItem(kind: .text, createdAt: ancient, isSecret: true)])
        let settings = env.makeSettings(limit: 10)
        settings.secretRetention = .forever
        let store = await env.makeStore(settings: settings)
        #expect(store.items.count == 1)
    }

    @Test("Пароль не попадает в history.json открытым текстом")
    func secretTextNotWritten() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try env.writeHistory([ClipboardItem(kind: .text, isSecret: true, sourceAppName: "1Password")])
        let store = await env.makeStore(limit: 10)
        store.addText("обычный", source: nil)
        store.save(synchronously: true)
        let json = try String(contentsOf: env.historyURL, encoding: .utf8)
        #expect(json.contains("обычный"))
        #expect(store.items.first { $0.isSecret }?.text == nil)
    }

    @Test("Удаление и очистка незакреплённых")
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
}
