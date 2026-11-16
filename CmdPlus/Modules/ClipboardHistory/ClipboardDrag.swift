import AppKit
import UniformTypeIdentifiers

/// Перетаскивание записи из окна истории в другие приложения.
extension ClipboardHistoryModule {
    /// Что «несёт» перетаскиваемая запись:
    /// - текст — как обычный текст;
    /// - картинка — как PNG (в Finder появится файл, в редакторах — сама картинка);
    /// - файлы — как ссылка на файл (берём первый: SwiftUI перетаскивает один объект).
    /// Пароли не перетаскиваются: для них нужен Touch ID.
    func dragItemProvider(for item: ClipboardItem) -> NSItemProvider? {
        guard !item.isSecret else { return nil }
        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            return NSItemProvider(object: text as NSString)

        case .image:
            guard let url = store.imageURL(for: item),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            let provider = NSItemProvider()
            provider.suggestedName = String(localized: "Image")
            provider.registerFileRepresentation(for: .png, visibility: .all, openInPlace: false) { completion in
                completion(url, false, nil)
                return nil
            }
            provider.registerDataRepresentation(for: .png, visibility: .all) { completion in
                completion(try? Data(contentsOf: url), nil)
                return nil
            }
            return provider

        case .files:
            guard let url = item.fileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else { return nil }
            return NSItemProvider(contentsOf: url)
        }
    }
}
