import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Clipboard History module. Only alive while the module is enabled.
@Observable
final class ClipboardHistoryModule: AppModule {
    static let descriptor = ModuleDescriptor(
        id: "clipboardHistory",
        title: "Clipboard History",
        summary: "Keeps text, images and files you copy. Open with ⇧⌘V.",
        systemImage: "list.clipboard.fill",
        tint: .blue,
        make: { ClipboardHistoryModule() }
    )

    let settings: ClipboardSettings
    let store: ClipboardStore
    private(set) var hotKeyFailed = false
    private(set) var hasPasteAccess = PasteSimulator.hasAccess

    var canPasteDirectly: Bool {
        settings.pasteDirectly && hasPasteAccess
    }

    @ObservationIgnored private let monitor = ClipboardMonitor()
    @ObservationIgnored private var hotKey: GlobalHotKey?
    /// Created lazily on the first ⇧⌘V.
    @ObservationIgnored private var panelController: HistoryPanelController?

    /// Tests and README screenshots pass their own settings and folder.
    init(settings: ClipboardSettings = ClipboardSettings(), directory: URL = ClipboardStore.defaultDirectory) {
        self.settings = settings
        store = ClipboardStore(settings: settings, directory: directory)
    }

    // MARK: - AppModule

    func start() {
        monitor.onCapture = { [weak self] content, source in
            self?.handle(content, source: source)
        }
        monitor.start()

        hotKey = GlobalHotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            self?.togglePanel()
        }
        hotKeyFailed = hotKey == nil

        Task { await store.load() }
    }

    func stop() {
        monitor.stop()
        hotKey?.unregister()
        hotKey = nil
        panelController?.close()
        panelController = nil
        store.save(synchronously: true)
    }

    func makeTile() -> AnyView {
        AnyView(ClipboardTileView(module: self))
    }

    func makeSettingsView() -> AnyView {
        AnyView(ClipboardSettingsView(module: self))
    }

    // MARK: - History window

    /// ⇧⌘V: close if focused, bring forward if covered, open if closed.
    func togglePanel() {
        guard let panelController, panelController.isVisible else {
            showPanel()
            return
        }
        if panelController.isActive {
            panelController.close()
        } else {
            panelController.bringToFront()
        }
    }

    func showPanel() {
        refreshPasteAccess()
        // Warm up thumbnails so the list shows images right away.
        let imageURLs = store.items.prefix(40).compactMap { store.imageURL(for: $0) }
        ImageLoader.prefetch(imageURLs, size: .thumbnail)
        if panelController == nil {
            panelController = HistoryPanelController(module: self)
        }
        panelController?.show()
    }

    // MARK: - Pasting

    func refreshPasteAccess() {
        hasPasteAccess = PasteSimulator.hasAccess
    }

    func requestPasteAccess() {
        PasteSimulator.requestAccess()
        refreshPasteAccess()
    }

    /// A short pause lets the history window close and focus return to the
    /// previous app before ⌘V is sent.
    func pasteIntoFrontApp() {
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            PasteSimulator.pressCommandV()
        }
    }

    // MARK: - Clipboard

    private func handle(_ content: ClipboardMonitor.Content, source: SourceApp?) {
        switch content {
        case .text(let text):
            store.addText(text, source: source)
        case .files(let urls):
            store.addFiles(urls, source: source)
        case .image(let data):
            store.addImage(data, source: source)
        }
    }

    /// Puts an item back on the clipboard. Returns `false` if that didn't work
    /// (for example, the file is gone).
    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) async -> Bool {
        let pasteboard = NSPasteboard.general

        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: item),
                  let png = try? Data(contentsOf: url) else { return false }
            pasteboard.clearContents()
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        case .files:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
        }

        monitor.markOwnWrite()
        store.touch(item.id)
        return true
    }
}
