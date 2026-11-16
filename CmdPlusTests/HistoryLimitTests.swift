import Foundation
import Testing
@testable import CmdPlus

@Suite("Лимит записей")
struct HistoryLimitTests {
    @Test("По умолчанию лимит — 10")
    func defaultLimit() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        #expect(env.makeSettings().historyLimit == ClipboardSettings.defaultLimit)
    }

    @Test("Лимит удерживается в пределах 1–500", arguments: [
        (-5, 1), (0, 1), (1, 1), (37, 37), (500, 500), (501, 500), (10_000, 500),
    ])
    func limitIsClamped(input: Int, expected: Int) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = env.makeSettings()
        settings.historyLimit = input
        #expect(settings.historyLimit == expected)
    }

    @Test("Лимит сохраняется в UserDefaults и читается при следующем запуске")
    func limitPersists() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.makeSettings().historyLimit = 42
        #expect(env.makeSettings().historyLimit == 42)
    }

    @Test("Сохранённое недопустимое значение исправляется при чтении")
    func invalidSavedLimitIsClamped() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.defaults.set(9_999, forKey: "clipboard.historyLimit")
        #expect(env.makeSettings().historyLimit == 500)
    }

    @Test("Сверх лимита удаляются самые старые записи")
    func trimsOldest() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 3)
        for text in ["1", "2", "3", "4", "5"] { store.addText(text, source: nil) }
        #expect(store.texts == ["5", "4", "3"])
    }

    @Test("Лимит 1 оставляет только последнюю запись")
    func limitOne() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 1)
        store.addText("старое", source: nil)
        store.addText("новое", source: nil)
        #expect(store.texts == ["новое"])
    }

    @Test("Лимит 500 вмещает ровно 500 записей")
    func limitFiveHundred() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 500)
        for i in 1...501 { store.addText("запись \(i)", source: nil) }
        #expect(store.items.count == 500)
        #expect(store.items.first?.text == "запись 501")
        #expect(!store.texts.contains("запись 1"))
    }

    @Test("Закреплённые записи не считаются в лимит и не удаляются")
    func pinnedNotCounted() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 2)
        store.addText("важное", source: nil)
        store.togglePin(store.items[0].id)
        for text in ["a", "b", "c", "d"] { store.addText(text, source: nil) }

        #expect(store.unpinnedCount == 2)
        #expect(store.items.count == 3)
        #expect(Set(store.texts) == ["важное", "d", "c"])
    }

    @Test("Закреплённые остаются, даже если их больше лимита")
    func manyPinned() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 1)
        for text in ["p1", "p2", "p3"] {
            store.addText(text, source: nil)
            store.togglePin(store.items[0].id)
        }
        store.addText("обычная", source: nil)
        #expect(store.items.filter(\.isPinned).count == 3)
        #expect(store.unpinnedCount == 1)
    }

    @Test("Уменьшение лимита сразу удаляет лишние старые записи")
    func applyLimitAfterChange() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 10)
        for text in ["1", "2", "3", "4", "5"] { store.addText(text, source: nil) }
        store.settings.historyLimit = 2
        store.applyLimit()
        #expect(store.texts == ["5", "4"])
    }

    @Test("Повторное копирование поднимает запись наверх, а не дублирует")
    func duplicateMovesToTop() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 10)
        for text in ["a", "b", "c"] { store.addText(text, source: nil) }
        let originalID = store.items.last?.id
        store.addText("a", source: nil)
        #expect(store.texts == ["a", "c", "b"])
        #expect(store.items.first?.id == originalID)
    }
}
