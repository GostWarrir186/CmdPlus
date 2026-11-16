import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Состояние окна истории: поиск, фильтр, выделенная строка.
@Observable
final class HistoryViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, text, images, files, pinned, secrets

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .text: "Text"
            case .images: "Images"
            case .files: "Files"
            case .pinned: "Pinned"
            case .secrets: "Passwords"
            }
        }

        var systemImage: String {
            switch self {
            case .all: "tray.full"
            case .text: "text.alignleft"
            case .images: "photo"
            case .files: "doc"
            case .pinned: "pin"
            case .secrets: "key"
            }
        }
    }

    var query = ""
    var filter: Filter = .all
    var selectedID: ClipboardItem.ID?
    /// Пароли, раскрытые по Touch ID. Сбрасываются при закрытии окна.
    var revealed: [ClipboardItem.ID: String] = [:]
    /// Меняется при каждом показе окна — сигнал поставить курсор в поиск.
    private(set) var focusRequest = 0

    @ObservationIgnored weak var module: ClipboardHistoryModule?
    @ObservationIgnored var close: () -> Void = {}
    /// Вызывается, когда запись начали перетаскивать из окна.
    @ObservationIgnored var dragStarted: () -> Void = {}

    init(module: ClipboardHistoryModule) {
        self.module = module
    }

    var store: ClipboardStore? { module?.store }

    /// Слова из строки поиска. Запись подходит, если содержит все слова.
    var terms: [String] {
        Self.terms(from: query)
    }

    /// Записи с учётом фильтра и поиска; закреплённые — сверху.
    var visibleItems: [ClipboardItem] {
        guard let store else { return [] }
        return Self.filter(store.items, by: filter, terms: terms)
    }

    static func terms(from query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Чистая функция поиска: запись подходит, если проходит фильтр и содержит все слова.
    static func filter(_ items: [ClipboardItem], by filter: Filter, terms: [String]) -> [ClipboardItem] {
        let matched = items.filter { item in
            matches(item, filter: filter) && terms.allSatisfy { item.searchableText.localizedStandardContains($0) }
        }
        return matched.filter(\.isPinned) + matched.filter { !$0.isPinned }
    }

    private static func matches(_ item: ClipboardItem, filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .text: item.kind == .text && !item.isSecret
        case .images: item.kind == .image
        case .files: item.kind == .files
        case .pinned: item.isPinned
        case .secrets: item.isSecret
        }
    }

    // MARK: - Жизненный цикл окна

    func prepareForShow() {
        query = ""
        filter = .all
        revealed = [:]
        selectFirst()
        focusRequest += 1
    }

    func didClose() {
        revealed = [:]
    }

    // MARK: - Выделение и действия

    func selectFirst() {
        selectedID = visibleItems.first?.id
    }

    func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    private var selectedItem: ClipboardItem? {
        visibleItems.first { $0.id == selectedID }
    }

    /// Выбор записи: кладёт её в буфер, закрывает окно и сразу вставляет
    /// в приложение, где вы работали. `paste: false` (⌥↩) — только копирует.
    /// Без разрешения «Универсальный доступ» тоже только копирует.
    func activate(_ item: ClipboardItem, paste: Bool = true) {
        Task {
            guard let module, await module.copyToPasteboard(item) else { return }
            close()
            if paste, module.canPasteDirectly {
                module.pasteIntoFrontApp()
            }
        }
    }

    /// Вставка сразу работает — от этого зависят подсказки в окне.
    var pastesDirectly: Bool {
        module?.canPasteDirectly ?? false
    }

    /// Вставка включена в настройках, но разрешения ещё нет.
    var needsPasteAccess: Bool {
        guard let module else { return false }
        return module.settings.pasteDirectly && !module.hasPasteAccess
    }

    func requestPasteAccess() {
        module?.requestPasteAccess()
    }

    /// Данные для перетаскивания. `nil` — запись перетащить нельзя (пароль, файл удалён).
    func dragProvider(for item: ClipboardItem) -> NSItemProvider? {
        guard let provider = module?.dragItemProvider(for: item) else { return nil }
        dragStarted()
        return provider
    }

    func canDrag(_ item: ClipboardItem) -> Bool {
        !item.isSecret
    }

    func togglePin(_ item: ClipboardItem) {
        store?.togglePin(item.id)
    }

    func delete(_ item: ClipboardItem) {
        if selectedID == item.id {
            moveSelection(by: 1)
            if selectedID == item.id { moveSelection(by: -1) }
        }
        revealed[item.id] = nil
        store?.delete(item.id)
        if visibleItems.isEmpty { selectedID = nil }
    }

    func toggleReveal(_ item: ClipboardItem) {
        if revealed[item.id] != nil {
            revealed[item.id] = nil
            return
        }
        Task {
            if let secret = await module?.revealSecret(item) {
                revealed[item.id] = secret
            }
        }
    }

    /// Клавиатура окна. Возвращает `true`, если клавиша обработана.
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            moveSelection(by: -1)
        case kVK_DownArrow:
            moveSelection(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let item = selectedItem else { return true }
            // ⌥↩ — только скопировать, не вставляя.
            activate(item, paste: !event.modifierFlags.contains(.option))
        case kVK_Escape:
            close()
        case kVK_Delete where command:
            guard let item = selectedItem else { return true }
            delete(item)
        case kVK_ANSI_P where command:
            guard let item = selectedItem else { return true }
            togglePin(item)
        default:
            // ⌘1…⌘9 — сразу выбрать запись по номеру, без стрелок.
            guard command, let number = Self.quickPickNumber(for: event) else { return false }
            let items = visibleItems
            guard number <= items.count else { return true }
            activate(items[number - 1], paste: !event.modifierFlags.contains(.option))
        }
        return true
    }

    /// Цифра 1…9 нажатой клавиши (по символу, поэтому работает в любой раскладке).
    private static func quickPickNumber(for event: NSEvent) -> Int? {
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let number = Int(characters),
              (1...9).contains(number)
        else { return nil }
        return number
    }
}
