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
    }

    /// Types password managers use to mark secrets (see nspasteboard.org).
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
        if let content = Self.readContent(of: pasteboard) {
            let app = NSWorkspace.shared.frontmostApplication
            onCapture?(content, SourceApp(name: app?.localizedName, bundleID: app?.bundleIdentifier))
        }
    }

    /// What's worth saving from a pasteboard, or `nil` to skip it.
    static func readContent(of pasteboard: NSPasteboard) -> Content? {
        let types = pasteboard.types ?? []
        let typeIDs = Set(types.map(\.rawValue))

        // Passwords from password managers are never saved — skip them entirely.
        guard typeIDs.isDisjoint(with: Self.secretTypes) else { return nil }

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
