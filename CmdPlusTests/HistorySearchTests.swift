import Foundation
import Testing
@testable import CmdPlus

@Suite("Поиск по словам")
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

    @Test("Строка поиска делится на слова по пробелам и переводам строк")
    func splitsTerms() {
        #expect(HistoryViewModel.terms(from: "  молоко   хлеб\nкупить ") == ["молоко", "хлеб", "купить"])
        #expect(HistoryViewModel.terms(from: "   ").isEmpty)
    }

    @Test("Пустой запрос показывает все записи")
    func emptyQuery() {
        #expect(search("").count == items.count)
    }

    @Test("Слова ищутся в любом порядке, без учёта регистра")
    func anyOrderCaseInsensitive() {
        #expect(search("ХЛЕБ купить").map(\.text) == ["Купить молоко и хлеб"])
        #expect(search("review PULL").count == 1)
    }

    @Test("Запись должна содержать все слова запроса")
    func allTermsRequired() {
        #expect(search("молоко пятницу").isEmpty)
    }

    @Test("Ищется часть слова")
    func partialWord() {
        #expect(search("команд").map(\.text) == ["Встреча с командой в пятницу"])
    }

    @Test("Поиск по пути файла и по имени приложения")
    func searchesPathsAndApps() {
        #expect(search("отчёт").map(\.kind) == [.files])
        #expect(search("notes").map(\.text) == ["Купить молоко и хлеб"])
        #expect(search("preview").map(\.kind) == [.image])
    }

    @Test("Текст пароля никогда не участвует в поиске")
    func secretTextNotSearchable() {
        var secret = ClipboardItem(kind: .text, isSecret: true)
        secret.text = "hunter2" // даже если бы текст оказался в записи
        let found = HistoryViewModel.filter([secret], by: .all, terms: ["hunter2"])
        #expect(found.isEmpty)
        #expect(search("1password").count == 1)
    }

    @Test("Фильтры по типу", arguments: [
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

    @Test("Фильтр и поиск работают вместе")
    func filterAndQuery() {
        #expect(search("молоко", filter: .files).isEmpty)
        #expect(search("молоко", filter: .text).count == 1)
    }

    @Test("Закреплённые записи показываются первыми, порядок остальных сохраняется")
    func pinnedFirst() {
        var list = items
        list[2].isPinned = true
        let result = HistoryViewModel.filter(list, by: .all, terms: [])
        #expect(result.first?.id == list[2].id)
        #expect(result.dropFirst().map(\.id) == list.filter { !$0.isPinned }.map(\.id))
    }

    @Test("Подсветка выделяет все найденные слова")
    func highlight() {
        let text = "Кот и котёнок, КОТ"
        let attributed = SearchHighlighter.highlight(text, terms: ["кот"])
        let highlighted = attributed.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(attributed[$0.range].characters) }
        #expect(highlighted == ["Кот", "кот", "КОТ"])
        #expect(String(attributed.characters) == text)
    }

    @Test("Пересекающиеся совпадения не ломают текст")
    func overlappingHighlight() {
        let text = "abcdef"
        let attributed = SearchHighlighter.highlight(text, terms: ["abc", "bcd"])
        #expect(String(attributed.characters) == text)
    }

    @Test("Превью показывает фрагмент вокруг далёкого совпадения")
    func previewAroundMatch() {
        let text = String(repeating: "слово ", count: 40) + "ЦЕЛЬ в конце"
        let preview = SearchHighlighter.preview(of: text, terms: ["цель"], limit: 100)
        #expect(preview.hasPrefix("…"))
        #expect(preview.contains("ЦЕЛЬ"))
    }
}
