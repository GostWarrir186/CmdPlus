import Foundation
import Testing
@testable import CmdPlus

@Suite("History limit")
struct HistoryLimitTests {
    @Test("Default limit is 10")
    func defaultLimit() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        #expect(env.makeSettings().historyLimit == ClipboardSettings.defaultLimit)
    }

    @Test("Limit is clamped to 1–500", arguments: [
        (-5, 1), (0, 1), (1, 1), (37, 37), (500, 500), (501, 500), (10_000, 500),
    ])
    func limitIsClamped(input: Int, expected: Int) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = env.makeSettings()
        settings.historyLimit = input
        #expect(settings.historyLimit == expected)
    }

    @Test("Limit persists across launches")
    func limitPersists() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.makeSettings().historyLimit = 42
        #expect(env.makeSettings().historyLimit == 42)
    }

    @Test("Invalid saved limit is clamped on load")
    func invalidSavedLimitIsClamped() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.defaults.set(9_999, forKey: "clipboard.historyLimit")
        #expect(env.makeSettings().historyLimit == 500)
    }

    @Test("Oldest items are dropped over the limit")
    func trimsOldest() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 3)
        for text in ["1", "2", "3", "4", "5"] { store.addText(text, source: nil) }
        #expect(store.texts == ["5", "4", "3"])
    }

    @Test("Limit of 1 keeps only the newest item")
    func limitOne() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 1)
        store.addText("старое", source: nil)
        store.addText("новое", source: nil)
        #expect(store.texts == ["новое"])
    }

    @Test("Limit of 500 holds exactly 500 items")
    func limitFiveHundred() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 500)
        for i in 1...501 { store.addText("запись \(i)", source: nil) }
        #expect(store.items.count == 500)
        #expect(store.items.first?.text == "запись 501")
        #expect(!store.texts.contains("запись 1"))
    }

    @Test("Pinned items don't count toward the limit and aren't removed")
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

    @Test("Pinned items stay even when they exceed the limit")
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

    @Test("Lowering the limit trims old items right away")
    func applyLimitAfterChange() async {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let store = await env.makeStore(limit: 10)
        for text in ["1", "2", "3", "4", "5"] { store.addText(text, source: nil) }
        store.settings.historyLimit = 2
        store.applyLimit()
        #expect(store.texts == ["5", "4"])
    }

    @Test("Copying again moves the item to the top instead of duplicating it")
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
