import AppKit
import CryptoKit
import Observation

/// History storage: items in memory plus files on disk.
///
/// Lives in `Application Support/CmdPlus/ClipboardHistory/` (inside the sandbox
/// container): `history.json` for items (no passwords) and `images/` for PNGs.
@Observable
final class ClipboardStore {
    /// Newest first.
    private(set) var items: [ClipboardItem] = []
    private(set) var isLoaded = false
    /// Last Keychain error, shown in Settings.
    var vaultError: String?

    let settings: ClipboardSettings
    let directory: URL
    let imagesDirectory: URL
    private let historyURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "CmdPlus/ClipboardHistory", directoryHint: .isDirectory)
    }

    /// Tests pass a temporary directory here.
    init(settings: ClipboardSettings, directory: URL = ClipboardStore.defaultDirectory) {
        self.settings = settings
        self.directory = directory
        imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
        historyURL = directory.appending(path: "history.json")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Loading and saving

    /// Reads history.json in the background so launch isn't blocked.
    func load() async {
        let url = historyURL
        let loaded: [ClipboardItem] = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return [] }
            do {
                return try JSONDecoder().decode([ClipboardItem].self, from: data)
            } catch {
                // Corrupt file — move it aside instead of silently overwriting it.
                let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: url, to: backup)
                return []
            }
        }.value

        // Anything copied while loading stays on top.
        let capturedIDs = Set(items.map(\.id))
        items += loaded.filter { !capturedIDs.contains($0.id) }
        isLoaded = true
        purgeExpiredSecrets()
        applyLimit()
    }

    /// Debounced to once a second so we don't hit the disk on every copy.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save(synchronously: false)
        }
    }

    func save(synchronously: Bool) {
        // Don't overwrite the file before the old history has been read.
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

    // MARK: - Adding

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

    /// PNG conversion can take a moment, so it runs in the background.
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

    /// The password goes to the Keychain; history only gets a placeholder entry.
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
            // Couldn't encrypt it — so don't keep it at all. No plain-text passwords.
            vaultError = error.localizedDescription
        }
    }

    private func insert(_ newItem: ClipboardItem) {
        var item = newItem
        // Same content already exists — move the old entry to the top.
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

    // MARK: - Item actions

    func togglePin(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    /// Moves an item to the top (after it's reused from history).
    func touch(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        if !item.isSecret {
            // Don't bump the date for passwords, or they'd never expire.
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

    func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        removed.forEach(removeFiles(of:))
        scheduleSave()
    }

    /// Removes passwords past their retention period. Pinned ones are kept.
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

    // MARK: - Internals

    /// Only unpinned items count toward the limit.
    var unpinnedCount: Int {
        items.count { !$0.isPinned }
    }

    /// Call after the limit changes to trim right away.
    func applyLimit() {
        if trimToLimit() { scheduleSave() }
    }

    /// Drops the oldest unpinned items over the limit. Returns `true` if anything was removed.
    @discardableResult
    private func trimToLimit() -> Bool {
        let excess = unpinnedCount - settings.historyLimit
        guard excess > 0 else { return false }
        // Items are newest-first, so the extras are the last unpinned ones.
        let removedIDs = Set(items.filter { !$0.isPinned }.suffix(excess).map(\.id))
        let removed = items.filter { removedIDs.contains($0.id) }
        items.removeAll { removedIDs.contains($0.id) }
        removed.forEach(removeFiles(of:))
        return true
    }

    /// Cleans up what an item leaves behind: its image file or Keychain entry.
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
        // Named by content hash, so identical images are stored once.
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

struct SourceApp {
    let name: String?
    let bundleID: String?
}
