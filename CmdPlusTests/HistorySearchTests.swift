import Foundation
import Testing
@testable import CmdPlus

@Suite("Word search")
struct HistorySearchTests {
    private let items: [ClipboardItem] = [
        ClipboardItem(kind: .text, text: "Встреча с командой в пятницу"),
        ClipboardItem(kind: .text, text: "Купить молоко и хлеб", sourceAppName: "Notes"),
        ClipboardItem(kind: .text, text: "Pull request ready for review"),
        ClipboardItem(kind: .files, filePaths: ["/Users/me/Documents/Отчёт.pdf"]),
        ClipboardItem(kind: .image, imageFile: "abc.png", sourceAppName: "Preview"),
        ClipboardItem(kind: .text, isSecret: true, sourceAppName: "1Password"),
    ]

    private func search(_ query: String, filter: HistoryViewModel.Filter = .all) -> [ClipboardItem] {
        HistoryViewModel.filter(items, by: filter, terms: HistoryViewModel.terms(from: query))
    }

    @Test("Query splits into words on spaces and newlines")
    func splitsTerms() {
        #expect(HistoryViewModel.terms(from: "  молоко   хлеб\nкупить ") == ["молоко", "хлеб", "купить"])
        #expect(HistoryViewModel.terms(from: "   ").isEmpty)
    }

    @Test("Empty query shows everything")
    func emptyQuery() {
        #expect(search("").count == items.count)
    }

    @Test("Words match in any order, case-insensitive")
    func anyOrderCaseInsensitive() {
        #expect(search("ХЛЕБ купить").map(\.text) == ["Купить молоко и хлеб"])
        #expect(search("review PULL").count == 1)
    }

    @Test("An item must contain every word")
    func allTermsRequired() {
        #expect(search("молоко пятницу").isEmpty)
    }

    @Test("Partial words match")
    func partialWord() {
        #expect(search("команд").map(\.text) == ["Встреча с командой в пятницу"])
    }

    @Test("Searches file paths and app names")
    func searchesPathsAndApps() {
        #expect(search("отчёт").map(\.kind) == [.files])
        #expect(search("notes").map(\.text) == ["Купить молоко и хлеб"])
        #expect(search("preview").map(\.kind) == [.image])
    }

    @Test("Password text is never searchable")
    func secretTextNotSearchable() {
        var secret = ClipboardItem(kind: .text, isSecret: true)
        secret.text = "hunter2" // even if text somehow ended up in the item
        let found = HistoryViewModel.filter([secret], by: .all, terms: ["hunter2"])
        #expect(found.isEmpty)
        #expect(search("1password").count == 1)
    }

    @Test("Type filters", arguments: [
        (HistoryViewModel.Filter.text, 3),
        (.images, 1),
        (.files, 1),
        (.secrets, 1),
        (.pinned, 0),
        (.all, 6),
    ])
    func filters(filter: HistoryViewModel.Filter, expectedCount: Int) {
        #expect(search("", filter: filter).count == expectedCount)
    }

    @Test("Filter and search combine")
    func filterAndQuery() {
        #expect(search("молоко", filter: .files).isEmpty)
        #expect(search("молоко", filter: .text).count == 1)
    }

    @Test("Pinned items come first; the rest keep their order")
    func pinnedFirst() {
        var list = items
        list[2].isPinned = true
        let result = HistoryViewModel.filter(list, by: .all, terms: [])
        #expect(result.first?.id == list[2].id)
        #expect(result.dropFirst().map(\.id) == list.filter { !$0.isPinned }.map(\.id))
    }

    @Test("Highlighting marks every match")
    func highlight() {
        let text = "Кот и котёнок, КОТ"
        let attributed = SearchHighlighter.highlight(text, terms: ["кот"])
        let highlighted = attributed.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(attributed[$0.range].characters) }
        #expect(highlighted == ["Кот", "кот", "КОТ"])
        #expect(String(attributed.characters) == text)
    }

    @Test("Overlapping matches don't break the text")
    func overlappingHighlight() {
        let text = "abcdef"
        let attributed = SearchHighlighter.highlight(text, terms: ["abc", "bcd"])
        #expect(String(attributed.characters) == text)
    }

    @Test("Preview shows a snippet around a distant match")
    func previewAroundMatch() {
        let text = String(repeating: "слово ", count: 40) + "ЦЕЛЬ в конце"
        let preview = SearchHighlighter.preview(of: text, terms: ["цель"], limit: 100)
        #expect(preview.hasPrefix("…"))
        #expect(preview.contains("ЦЕЛЬ"))
    }
}
