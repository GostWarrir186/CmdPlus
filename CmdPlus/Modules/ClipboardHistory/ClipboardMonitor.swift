import AppKit

/// Watches the system clipboard.
///
/// macOS has no "clipboard changed" notification, so we poll `changeCount`
/// twice a second. That's cheap and doesn't read the contents — we only read
/// them when the count actually changes.
final class ClipboardMonitor {
    enum Content {
        case text(String)
        case image(Data)
        case files([URL])
        case secret(String)
    }

    /// Types password managers use to mark secrets (see nspasteboard.org).
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let secretTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ]

    private static let maxTextLength = 1_000_000
    private static let maxImageBytes = 30 * 1024 * 1024

    var onCapture: ((Content, SourceApp?) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var ownChangeCount: Int?
    private var pollTask: Task<Void, Never>?

    func start() {
        lastChangeCount = pasteboard.changeCount
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Call after we write to the clipboard ourselves, so we don't capture it again.
    func markOwnWrite() {
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ownChangeCount else { return }
        if let content = readContent() {
            let app = NSWorkspace.shared.frontmostApplication
            onCapture?(content, SourceApp(name: app?.localizedName, bundleID: app?.bundleIdentifier))
        }
    }

    private func readContent() -> Content? {
        let types = pasteboard.types ?? []
        let typeIDs = Set(types.map(\.rawValue))

        if !typeIDs.isDisjoint(with: Self.secretTypes) {
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
            return .secret(text)
        }

        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]
           ) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }

        // Prefer text when both are present (e.g. a spreadsheet cell).
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.count <= Self.maxTextLength else { return nil }
            return .text(text)
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] where types.contains(type) {
            if let data = pasteboard.data(forType: type), data.count <= Self.maxImageBytes {
                return .image(data)
            }
        }
        return nil
    }
}
