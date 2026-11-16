import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Модуль «История буфера». Объект существует только пока модуль включён.
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

    let settings = ClipboardSettings()
    let store: ClipboardStore
    /// `true`, если ⇧⌘V уже занято другим приложением.
    private(set) var hotKeyFailed = false

    @ObservationIgnored private let monitor = ClipboardMonitor()
    @ObservationIgnored private var hotKey: GlobalHotKey?
    /// Окно истории создаётся лениво — при первом нажатии ⇧⌘V.
    @ObservationIgnored private var panelController: HistoryPanelController?
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?

    init() {
        store = ClipboardStore(settings: settings)
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

        // Раз в 5 минут удаляем пароли с истёкшим сроком хранения.
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.store.purgeExpiredSecrets()
            }
        }
    }

    func stop() {
        monitor.stop()
        hotKey?.unregister()
        hotKey = nil
        maintenanceTask?.cancel()
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

    // MARK: - Окно истории

    func togglePanel() {
        if panelController?.isVisible == true {
            panelController?.close()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        store.purgeExpiredSecrets()
        if panelController == nil {
            panelController = HistoryPanelController(module: self)
        }
        panelController?.show()
    }

    // MARK: - Буфер

    private func handle(_ content: ClipboardMonitor.Content, source: SourceApp?) {
        switch content {
        case .text(let text):
            store.addText(text, source: source)
        case .files(let urls):
            store.addFiles(urls, source: source)
        case .image(let data):
            store.addImage(data, source: source)
        case .secret(let secret):
            guard settings.captureSecrets else { return }
            store.addSecret(secret, source: source)
        }
    }

    /// Кладёт запись обратно в буфер. Для паролей сначала спрашивает Touch ID.
    /// Возвращает `false`, если не получилось (отмена Touch ID, файл удалён и т. п.).
    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) async -> Bool {
        let pasteboard = NSPasteboard.general

        if item.isSecret {
            guard let secret = await revealSecret(item) else { return false }
            pasteboard.clearContents()
            // Помечаем как секрет, чтобы другие менеджеры буфера его не записывали.
            pasteboard.declareTypes([.string, ClipboardMonitor.concealedType], owner: nil)
            pasteboard.setString(secret, forType: .string)
            pasteboard.setData(Data(), forType: ClipboardMonitor.concealedType)
        } else {
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
        }

        monitor.markOwnWrite()
        store.touch(item.id)
        return true
    }

    /// Показывает пароль после Touch ID. Окно истории на это время не закрывается.
    func revealSecret(_ item: ClipboardItem) async -> String? {
        panelController?.suppressAutoClose = true
        defer {
            panelController?.suppressAutoClose = false
            panelController?.makeKeyIfVisible()
        }
        return try? await SecretVault.reveal(
            account: item.id.uuidString,
            reason: String(localized: "show a password from clipboard history")
        )
    }
}
