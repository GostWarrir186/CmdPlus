import AppKit
import UniformTypeIdentifiers

extension ClipboardHistoryModule {
    /// What a dragged item carries: text as text, images as PNG (a file in Finder,
    /// an image in editors), files as file URLs — only the first one, since SwiftUI
    /// drags a single item.
    func dragItemProvider(for item: ClipboardItem) -> NSItemProvider? {
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
