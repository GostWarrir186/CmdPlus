import AppKit
import ImageIO
import SwiftUI

/// Окно истории в стиле Spotlight: поиск и фильтры сверху,
/// слева компактный список, справа — превью выбранной записи.
struct HistoryView: View {
    @Bindable var model: HistoryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let items = model.visibleItems
        let terms = model.terms
        let selected = items.first { $0.id == model.selectedID } ?? items.first

        VStack(spacing: 0) {
            searchBar
            filterBar
            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "No Items" : "No Results",
                    systemImage: model.query.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(model.query.isEmpty
                        ? "Copy something and it will appear here."
                        : "Try different words or another filter.")
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    list(items, terms: terms)
                        .frame(width: Design.History.listWidth)
                    Divider()
                    if let selected {
                        HistoryPreview(
                            item: selected,
                            terms: terms,
                            revealedSecret: model.revealed[selected.id],
                            imageURL: model.store?.imageURL(for: selected),
                            model: model
                        )
                        .id(selected.id)
                    }
                }
            }

            Divider()
            footer(count: items.count)
        }
        .frame(width: Design.History.windowSize.width, height: Design.History.windowSize.height)
        .onChange(of: model.focusRequest, initial: true) {
            isSearchFocused = true
        }
        .onChange(of: model.query) { model.selectFirst() }
        .onChange(of: model.filter) { model.selectFirst() }
    }

    // MARK: - Поиск и фильтры

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Search Clipboard History", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
            if !model.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    model.query = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(HistoryViewModel.Filter.allCases) { filter in
                FilterChip(filter: filter, isSelected: model.filter == filter) {
                    model.filter = filter
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Список

    private func list(_ items: [ClipboardItem], terms: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HistoryRow(
                            item: item,
                            terms: terms,
                            quickPickNumber: index < 9 ? index + 1 : nil,
                            isSelected: item.id == (model.selectedID ?? items.first?.id),
                            imageURL: model.store?.imageURL(for: item),
                            model: model
                        )
                        .id(item.id)
                    }
                }
                .padding(Design.History.listPadding)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    // MARK: - Подвал

    private func footer(count: Int) -> some View {
        HStack(spacing: 14) {
            if model.pastesDirectly {
                ShortcutHint(keys: "↩", title: "Paste")
                ShortcutHint(keys: "⌥↩", title: "Copy Only")
            } else {
                ShortcutHint(keys: "↩", title: "Copy")
            }
            ShortcutHint(keys: "⌘P", title: "Pin")
            ShortcutHint(keys: "⌘⌫", title: "Delete")
            Spacer()
            if model.needsPasteAccess {
                // Разрешение просим только по нажатию — с понятной подписью.
                Button("Allow Pasting…") { model.requestPasteAccess() }
                    .buttonStyle(.link)
                    .help(Text("CmdPlus needs the Accessibility permission to press ⌘V for you."))
            }
            Text("\(count) items")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Мелкие элементы

/// Фильтр-капсула: иконка + название. Выбранный — залит акцентным цветом.
private struct FilterChip: View {
    let filter: HistoryViewModel.Filter
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(filter.title)
            } icon: {
                Image(systemName: filter.systemImage)
            }
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(background, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(Color.primary.opacity(isHovered ? 0.1 : 0.05))
    }
}

/// Подсказка в подвале: клавиша в капсуле + действие.
private struct ShortcutHint: View {
    let keys: String
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: 5) {
            KeyCap(text: keys)
            Text(title)
        }
    }
}

// MARK: - Строка списка

private struct HistoryRow: View {
    let item: ClipboardItem
    let terms: [String]
    /// Номер для ⌘1…⌘9 (у первых девяти строк).
    let quickPickNumber: Int?
    let isSelected: Bool
    let imageURL: URL?
    let model: HistoryViewModel

    var body: some View {
        HStack(spacing: 10) {
            HistoryItemIcon(item: item, imageURL: imageURL, size: Design.History.thumbnailSize)

            VStack(alignment: .leading, spacing: 1) {
                title
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitle
                    .font(.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
            }
            if let quickPickNumber {
                Text(verbatim: "⌘\(quickPickNumber)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(Design.History.rowPadding)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: Design.History.rowRadius)
        )
        .contentShape(.rect)
        // Двойной клик — вставить, одинарный — показать в превью.
        .onTapGesture(count: 2) { model.activate(item) }
        .onTapGesture { model.selectedID = item.id }
        // Запись можно перетащить в любое приложение.
        .draggableItem(item, model: model, imageURL: imageURL)
        .contextMenu {
            if model.pastesDirectly {
                Button("Paste", systemImage: "doc.on.clipboard") { model.activate(item) }
            }
            Button("Copy", systemImage: "doc.on.doc") { model.activate(item, paste: false) }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                model.togglePin(item)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(item) }
        }
    }

    @ViewBuilder
    private var title: some View {
        if item.isSecret {
            Text(verbatim: "••••••••••••")
                .font(.body.monospaced())
        } else {
            switch item.kind {
            case .text:
                let preview = SearchHighlighter.preview(of: item.text ?? "", terms: terms, limit: 120)
                Text(SearchHighlighter.highlight(preview, terms: terms))
            case .image:
                if let width = item.imageWidth, let height = item.imageHeight {
                    Text("Image") + Text(verbatim: " \(width)×\(height)")
                } else {
                    Text("Image")
                }
            case .files:
                let names = item.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
                Text(SearchHighlighter.highlight(names, terms: terms))
            }
        }
    }

    /// «Приложение · когда».
    private var subtitle: some View {
        HStack(spacing: 4) {
            if let app = item.sourceAppName {
                Text(SearchHighlighter.highlight(app, terms: terms))
                Text(verbatim: "·")
            }
            Text(item.createdAt.formatted(.relative(presentation: .named)))
        }
    }
}

extension View {
    /// Делает запись перетаскиваемой (кроме паролей). Под курсором — иконка и название.
    @ViewBuilder
    fileprivate func draggableItem(_ item: ClipboardItem, model: HistoryViewModel, imageURL: URL?) -> some View {
        if model.canDrag(item) {
            onDrag {
                model.dragProvider(for: item) ?? NSItemProvider()
            } preview: {
                HistoryItemIcon(item: item, imageURL: imageURL, size: 48)
            }
        } else {
            self
        }
    }
}

/// Иконка записи: миниатюра картинки, иконка файла или символ в цветной подложке.
private struct HistoryItemIcon: View {
    let item: ClipboardItem
    let imageURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if item.isSecret {
                TintedIcon(systemImage: "key.fill", tint: .orange, size: size)
            } else {
                switch item.kind {
                case .text:
                    TintedIcon(systemImage: "text.alignleft", tint: .gray, size: size)
                case .image:
                    if let imageURL {
                        ThumbnailView(url: imageURL, size: size)
                    } else {
                        TintedIcon(systemImage: "photo", tint: .purple, size: size)
                    }
                case .files:
                    if let path = item.filePaths?.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .scaledToFit()
                    } else {
                        TintedIcon(systemImage: "doc", tint: .blue, size: size)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Превью

/// Правая часть окна: содержимое записи целиком, сведения и действия.
private struct HistoryPreview: View {
    let item: ClipboardItem
    let terms: [String]
    let revealedSecret: String?
    let imageURL: URL?
    let model: HistoryViewModel

    /// Больше не показываем — превью должно открываться мгновенно.
    private static let maxTextLength = 20_000

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(spacing: 10) {
                details
                actions
            }
            .padding(14)
        }
    }

    // MARK: Содержимое

    @ViewBuilder
    private var content: some View {
        if item.isSecret {
            secretContent
        } else {
            switch item.kind {
            case .text:
                ScrollView {
                    Text(SearchHighlighter.highlight(String((item.text ?? "").prefix(Self.maxTextLength)), terms: terms))
                        .font(.body)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            case .image:
                if let imageURL {
                    PreviewImage(url: imageURL)
                        .draggableItem(item, model: model, imageURL: imageURL)
                        .padding(16)
                } else {
                    ContentUnavailableView("Image", systemImage: "photo")
                }
            case .files:
                filesContent
            }
        }
    }

    private var secretContent: some View {
        VStack(spacing: 14) {
            TintedIcon(systemImage: "key.fill", tint: .orange, size: 48)
            Text(verbatim: revealedSecret ?? "••••••••••••")
                .font(.title3.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button(revealedSecret == nil ? "Show" : "Hide",
                   systemImage: revealedSecret == nil ? "eye" : "eye.slash") {
                model.toggleReveal(item)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private var filesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(item.fileURLs, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(SearchHighlighter.highlight(url.lastPathComponent, terms: terms))
                                .lineLimit(1)
                            Text(verbatim: url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    // MARK: Сведения и действия

    private var details: some View {
        VStack(spacing: 4) {
            if let app = item.sourceAppName {
                DetailRow(title: "Application", value: app)
            }
            DetailRow(
                title: "Copied",
                value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
            if !item.isSecret {
                switch item.kind {
                case .text:
                    DetailRow(title: "Characters", value: (item.text?.count ?? 0).formatted())
                case .image:
                    if let width = item.imageWidth, let height = item.imageHeight {
                        DetailRow(title: "Dimensions", value: "\(width)×\(height)")
                    }
                case .files:
                    DetailRow(title: "Files", value: item.fileURLs.count.formatted())
                }
            }
        }
        .font(.caption)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Group {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    model.togglePin(item)
                }
                .help(Text(item.isPinned ? "Unpin" : "Pin"))
                Button("Delete", systemImage: "trash") {
                    model.delete(item)
                }
                .help(Text("Delete"))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            Spacer()

            Group {
                if model.pastesDirectly {
                    Button("Copy") { model.activate(item, paste: false) }
                        .buttonStyle(.bordered)
                    Button("Paste") { model.activate(item) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Copy") { model.activate(item, paste: false) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .buttonBorderShape(.capsule)
        }
        .controlSize(.large)
    }
}

private struct DetailRow: View {
    let title: LocalizedStringResource
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Картинка в превью: целиком, со скруглением и тонкой рамкой.
/// Читается в фоне, уменьшенной — большие скриншоты не тормозят окно.
private struct PreviewImage: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.History.previewRadius)
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: url) {
            image = await ThumbnailView.load(url, maxPixelSize: 1400)
        }
    }
}

/// Миниатюра картинки: целиком (scaledToFit) на нейтральной подложке,
/// чтобы у скриншотов и широких картинок не обрезались края.
/// Читается в фоне и в уменьшенном виде — 500 картинок не занимают много памяти.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.iconRadius(for: size))
        ZStack {
            Color.secondary.opacity(0.12)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .task(id: url) {
            image = await Self.load(url, maxPixelSize: 120)
        }
    }

    /// Уменьшенная копия картинки с диска, в фоне.
    static func load(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}
