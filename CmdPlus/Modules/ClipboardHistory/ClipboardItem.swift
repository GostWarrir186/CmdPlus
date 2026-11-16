import Foundation

/// Тип содержимого записи в истории.
nonisolated enum ClipboardKind: String, Codable, Sendable {
    case text
    case image
    case files
}

/// Одна запись истории. Хранится в history.json.
/// Для паролей (`isSecret`) сам текст здесь НЕ хранится — только в Keychain.
nonisolated struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ClipboardKind
    var createdAt: Date
    /// Текст записи (для обычного текста). У секретов всегда `nil`.
    var text: String?
    /// Имя PNG-файла в папке images.
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    /// Пути скопированных файлов.
    var filePaths: [String]?
    var isPinned: Bool
    var isSecret: Bool
    /// Отпечаток содержимого для поиска дублей. У секретов не хранится.
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

    /// Текст, по которому идёт поиск. У секретов — только имя приложения.
    var searchableText: String {
        var parts: [String] = []
        if !isSecret, let text { parts.append(text) }
        if let filePaths { parts.append(contentsOf: filePaths) }
        if let sourceAppName { parts.append(sourceAppName) }
        return parts.joined(separator: "\n")
    }
}
