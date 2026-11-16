import AppKit
import CryptoKit
import Observation

/// Хранилище истории: список записей в памяти + файлы на диске.
///
/// Папка: `~/Library/Application Support/CmdPlus/ClipboardHistory/`
/// (в песочнице macOS это `~/Library/Containers/com.azam.CmdPlus/Data/Library/Application Support/...`).
/// - `history.json` — список записей (без паролей);
/// - `images/` — картинки в PNG.
@Observable
final class ClipboardStore {
    /// Записи, новые — первыми.
    private(set) var items: [ClipboardItem] = []
    private(set) var isLoaded = false
    /// Последняя ошибка Keychain — показываем её в настройках.
    var vaultError: String?

    let settings: ClipboardSettings
    let directory: URL
    let imagesDirectory: URL
    private let historyURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "CmdPlus/ClipboardHistory", directoryHint: .isDirectory)
    }

    /// `directory` можно подменить — например, на временную папку в тестах.
    init(settings: ClipboardSettings, directory: URL = ClipboardStore.defaultDirectory) {
        self.settings = settings
        self.directory = directory
        imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
        historyURL = directory.appending(path: "history.json")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Загрузка и сохранение

    /// Читает history.json в фоне, чтобы не тормозить запуск.
    func load() async {
        let url = historyURL
        let loaded: [ClipboardItem] = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return [] }
            do {
                return try JSONDecoder().decode([ClipboardItem].self, from: data)
            } catch {
                // Файл повреждён — откладываем его в сторону, а не затираем молча.
                let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: url, to: backup)
                return []
            }
        }.value

        // Если что-то успели скопировать, пока шла загрузка, — оставляем это сверху.
        let capturedIDs = Set(items.map(\.id))
        items += loaded.filter { !capturedIDs.contains($0.id) }
        isLoaded = true
        purgeExpiredSecrets()
        applyLimit()
    }

    /// Сохраняет не чаще раза в секунду, чтобы не писать на диск на каждое копирование.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save(synchronously: false)
        }
    }

    func save(synchronously: Bool) {
        // Пока старая история не прочитана, не перезаписываем файл.
        guard isLoaded, let data = try? JSONEncoder().encode(items) else { return }
        let url = historyURL
        if synchronously {
            try? data.write(to: url, options: .atomic)
        } else {
            Task.detached(priority: .utility) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Добавление

    func addText(_ text: String, source: SourceApp?) {
        insert(ClipboardItem(
            kind: .text,
            text: text,
            contentHash: Self.hash(Data(text.utf8)),
            sourceAppName: source?.name,
            sourceBundleID: source?.bundleID
        ))
    }

    func addFiles(_ urls: [URL], source: SourceApp?) {
        let paths = urls.map(\.path)
        insert(ClipboardItem(
            kind: .files,
            filePaths: paths,
            contentHash: Self.hash(Data(paths.joined(separator: "\n").utf8)),
            sourceAppName: source?.name,
            sourceBundleID: source?.bundleID
        ))
    }

    /// Картинку перекодируем в PNG в фоне — это может занять время.
    func addImage(_ data: Data, source: SourceApp?) {
        let folder = imagesDirectory
        Task {
            let processed = await Task.detached(priority: .utility) {
                Self.processImage(data, folder: folder)
            }.value
            guard let processed else { return }
            insert(ClipboardItem(
                kind: .image,
                imageFile: processed.fileName,
                imageWidth: processed.width,
                imageHeight: processed.height,
                contentHash: processed.hash,
                sourceAppName: source?.name,
                sourceBundleID: source?.bundleID
            ))
        }
    }

    /// Пароль кладём в Keychain, а в историю — только запись-заглушку без текста.
    func addSecret(_ secret: String, source: SourceApp?) {
        let item = ClipboardItem(
            kind: .text,
            isSecret: true,
            sourceAppName: source?.name,
            sourceBundleID: source?.bundleID
        )
        do {
            try SecretVault.store(secret, account: item.id.uuidString)
            vaultError = nil
            insert(item)
        } catch {
            // Не смогли зашифровать — не сохраняем вовсе. Открытым текстом пароли не храним.
            vaultError = error.localizedDescription
        }
    }

    private func insert(_ newItem: ClipboardItem) {
        var item = newItem
        // Тот же текст/файл/картинка уже есть — поднимаем старую запись наверх.
        if let hash = item.contentHash, let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items.remove(at: index)
            existing.createdAt = item.createdAt
            existing.sourceAppName = item.sourceAppName ?? existing.sourceAppName
            existing.sourceBundleID = item.sourceBundleID ?? existing.sourceBundleID
            item = existing
        }
        items.insert(item, at: 0)
        trimToLimit()
        scheduleSave()
    }

    // MARK: - Действия с записями

    func togglePin(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    /// Поднимает запись наверх (после повторного копирования из истории).
    func touch(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        if !item.isSecret {
            // Для секретов дату не меняем, чтобы не продлевать срок хранения.
            item.createdAt = .now
        }
        items.insert(item, at: 0)
        scheduleSave()
    }

    func delete(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        removeFiles(of: items.remove(at: index))
        scheduleSave()
    }

    /// Удаляет всё, кроме закреплённых записей.
    func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        removed.forEach(removeFiles(of:))
        scheduleSave()
    }

    /// Удаляет пароли старше выбранного срока. Закреплённые не трогаем.
    func purgeExpiredSecrets() {
        guard let interval = settings.secretRetention.interval else { return }
        let cutoff = Date.now.addingTimeInterval(-interval)
        let expired = items.filter { $0.isSecret && !$0.isPinned && $0.createdAt < cutoff }
        guard !expired.isEmpty else { return }
        let expiredIDs = Set(expired.map(\.id))
        items.removeAll { expiredIDs.contains($0.id) }
        expired.forEach(removeFiles(of:))
        scheduleSave()
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appending(path: $0) }
    }

    // MARK: - Внутреннее

    /// Число незакреплённых записей — только они считаются в лимит.
    var unpinnedCount: Int {
        items.count { !$0.isPinned }
    }

    /// Вызывается после смены лимита: сразу удаляет лишние старые незакреплённые записи.
    func applyLimit() {
        if trimToLimit() { scheduleSave() }
    }

    /// Удаляет самые старые незакреплённые записи сверх лимита.
    /// Возвращает `true`, если что-то удалили.
    @discardableResult
    private func trimToLimit() -> Bool {
        let excess = unpinnedCount - settings.historyLimit
        guard excess > 0 else { return false }
        // Записи идут от новых к старым, поэтому лишние — последние незакреплённые.
        let removedIDs = Set(items.filter { !$0.isPinned }.suffix(excess).map(\.id))
        let removed = items.filter { removedIDs.contains($0.id) }
        items.removeAll { removedIDs.contains($0.id) }
        removed.forEach(removeFiles(of:))
        return true
    }

    /// Удаляет «хвосты» записи: файл картинки или секрет в Keychain.
    private func removeFiles(of item: ClipboardItem) {
        if let url = imageURL(for: item),
           !items.contains(where: { $0.imageFile == item.imageFile }) {
            try? FileManager.default.removeItem(at: url)
        }
        if item.isSecret {
            SecretVault.delete(account: item.id.uuidString)
        }
    }

    nonisolated private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct ProcessedImage: Sendable {
        let fileName: String
        let hash: String
        let width: Int
        let height: Int
    }

    nonisolated private static func processImage(_ data: Data, folder: URL) -> ProcessedImage? {
        guard let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        let hash = hash(png)
        // Имя файла = отпечаток, поэтому одинаковые картинки не дублируются на диске.
        let fileName = "\(hash.prefix(32)).png"
        let url = folder.appending(path: fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }
        return ProcessedImage(fileName: fileName, hash: hash, width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}

/// Приложение, из которого скопировали.
struct SourceApp {
    let name: String?
    let bundleID: String?
}
