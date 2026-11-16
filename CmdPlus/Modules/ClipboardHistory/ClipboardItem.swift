import Foundation

nonisolated enum ClipboardKind: String, Codable, Sendable {
    case text
    case image
    case files
}

/// One history entry, stored in history.json.
nonisolated struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ClipboardKind
    var createdAt: Date
    var text: String?
    /// PNG file name inside the images folder.
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var filePaths: [String]?
    var isPinned: Bool
    /// Legacy: a password entry from an older version. Such items are dropped on load.
    var isSecret: Bool
    /// Used to spot duplicates. Not stored for passwords.
    var contentHash: String?
    var sourceAppName: String?
    var sourceBundleID: String?

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        createdAt: Date = .now,
        text: String? = nil,
        imageFile: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        filePaths: [String]? = nil,
        isPinned: Bool = false,
        isSecret: Bool = false,
        contentHash: String? = nil,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.text = text
        self.imageFile = imageFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.isPinned = isPinned
        self.isSecret = isSecret
        self.contentHash = contentHash
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
    }

    var fileURLs: [URL] {
        (filePaths ?? []).map { URL(filePath: $0) }
    }

    /// What search looks at.
    var searchableText: String {
        var parts: [String] = []
        if let text { parts.append(text) }
        if let filePaths { parts.append(contentsOf: filePaths) }
        if let sourceAppName { parts.append(sourceAppName) }
        return parts.joined(separator: "\n")
    }
}
