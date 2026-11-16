import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// State of the history window: search, filter, selection.
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
    /// Passwords revealed with Touch ID. Cleared when the window closes.
    var revealed: [ClipboardItem.ID: String] = [:]
    /// Bumped on every show — tells the view to focus the search field.
    private(set) var focusRequest = 0

    @ObservationIgnored weak var module: ClipboardHistoryModule?
    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored var dragStarted: () -> Void = {}

    init(module: ClipboardHistoryModule) {
        self.module = module
    }

    var store: ClipboardStore? { module?.store }

    /// Search words. An item matches only if it contains all of them.
    var terms: [String] {
        Self.terms(from: query)
    }

    /// Filtered and searched items, pinned first.
    var visibleItems: [ClipboardItem] {
        guard let store else { return [] }
        return Self.filter(store.items, by: filter, terms: terms)
    }

    static func terms(from query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

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

    // MARK: - Window lifecycle

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

    // MARK: - Selection and actions

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

    /// Copies the item, closes the window and pastes into the previous app.
    /// `paste: false` (⌥↩) only copies — as does missing Accessibility permission.
    func activate(_ item: ClipboardItem, paste: Bool = true) {
        Task {
            guard let module, await module.copyToPasteboard(item) else { return }
            close()
            if paste, module.canPasteDirectly {
                module.pasteIntoFrontApp()
            }
        }
    }

    var pastesDirectly: Bool {
        module?.canPasteDirectly ?? false
    }

    /// Pasting is on in Settings, but permission hasn't been granted yet.
    var needsPasteAccess: Bool {
        guard let module else { return false }
        return module.settings.pasteDirectly && !module.hasPasteAccess
    }

    func requestPasteAccess() {
        module?.requestPasteAccess()
    }

    /// `nil` if the item can't be dragged (a password, or the file is gone).
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

    /// Window keyboard handling. Returns `true` if the key was used.
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            moveSelection(by: -1)
        case kVK_DownArrow:
            moveSelection(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let item = selectedItem else { return true }
            // ⌥↩ copies without pasting.
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
            // ⌘1…⌘9 picks an item directly.
            guard command, let number = Self.quickPickNumber(for: event) else { return false }
            let items = visibleItems
            guard number <= items.count else { return true }
            activate(items[number - 1], paste: !event.modifierFlags.contains(.option))
        }
        return true
    }

    /// Uses the typed character, so it works with any keyboard layout.
    private static func quickPickNumber(for event: NSEvent) -> Int? {
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let number = Int(characters),
              (1...9).contains(number)
        else { return nil }
        return number
    }
}
