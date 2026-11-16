import AppKit
import SwiftUI

/// The history window: search and filters on top, a compact list on the left,
/// a preview of the selected item on the right.
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
        // A backdrop under the glass so wallpaper doesn't bleed through the text.
        // Window background color adapts to light and dark mode.
        .background(Color(nsColor: .windowBackgroundColor).opacity(Design.History.backgroundOpacity))
        .onChange(of: model.focusRequest, initial: true) {
            isSearchFocused = true
        }
        .onChange(of: model.query) { model.selectFirst() }
        .onChange(of: model.filter) { model.selectFirst() }
        // Preload neighbors' images so arrowing through the list is instant.
        .onChange(of: selected?.id, initial: true) {
            prefetchNeighbors(of: selected, in: items)
        }
    }

    private func prefetchNeighbors(of item: ClipboardItem?, in items: [ClipboardItem]) {
        guard let item, let store = model.store,
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let range = max(index - 2, 0)...min(index + 2, items.count - 1)
        let urls = items[range].compactMap { $0.kind == .image ? store.imageURL(for: $0) : nil }
        ImageLoader.prefetch(urls, size: .preview)
    }

    // MARK: - Search and filters

    private var searchBar: some View {
        HStack(spacing: 10) {
            // Close sits on the left, like every macOS window (Esc and ⇧⌘V work too).
            WindowCloseButton { model.close() }
                .padding(.trailing, 4)
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
        .background(WindowDragArea())
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
        .background(WindowDragArea())
    }

    // MARK: - List

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

    // MARK: - Footer

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
                // Only ask for permission when the user clicks.
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
        .background(WindowDragArea())
    }
}

// MARK: - Small pieces

/// Close button styled like the system one: a red dot that shows × on hover.
private struct WindowCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.55))
                        .opacity(isHovered ? 1 : 0)
                }
                .frame(width: 13, height: 13)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Close (esc)"))
        .accessibilityLabel(Text("Close"))
    }
}

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

// MARK: - List row

private struct HistoryRow: View {
    let item: ClipboardItem
    let terms: [String]
    /// Shortcut number for ⌘1…⌘9 (first nine rows only).
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
        // One tap handler, not two: pairing onTapGesture(count: 2) with onTapGesture
        // makes SwiftUI wait out the double-click interval (~0.5s) before selecting.
        // Select immediately and detect double-clicks from the event's click count.
        .onTapGesture {
            if NSApp.currentEvent?.clickCount ?? 1 >= 2 {
                model.activate(item)
            } else {
                model.selectedID = item.id
            }
        }
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
    /// Makes an item draggable, with its icon as the drag preview.
    fileprivate func draggableItem(_ item: ClipboardItem, model: HistoryViewModel, imageURL: URL?) -> some View {
        onDrag {
            model.dragProvider(for: item) ?? NSItemProvider()
        } preview: {
            HistoryItemIcon(item: item, imageURL: imageURL, size: 48)
        }
    }
}

/// Image thumbnail, file icon, or a symbol on a tinted background.
private struct HistoryItemIcon: View {
    let item: ClipboardItem
    let imageURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
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
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

private struct HistoryPreview: View {
    let item: ClipboardItem
    let terms: [String]
    let imageURL: URL?
    let model: HistoryViewModel

    /// Cap the preview so it always opens instantly.
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

    // MARK: Content

    @ViewBuilder
    private var content: some View {
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

    // MARK: Details and actions

    private var details: some View {
        VStack(spacing: 4) {
            if let app = item.sourceAppName {
                DetailRow(title: "Application", value: app)
            }
            DetailRow(
                title: "Copied",
                value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
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

/// Full image with rounded corners. Comes from the cache when possible,
/// otherwise decoded in the background.
private struct PreviewImage: View {
    let url: URL
    @State private var image: CGImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ImageLoader.cached(url, size: .preview))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.History.previewRadius)
        Group {
            if let image {
                // No shadow: on a large image it forced an extra render pass on every update.
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            // Holding an arrow key flies past items — don't decode every one.
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            image = await ImageLoader.load(url, size: .preview)
        }
    }
}

/// Thumbnail shown whole (scaledToFit) so screenshots aren't cropped.
/// Served from the shared cache, so reopening the window doesn't decode again.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat
    @State private var image: CGImage?

    init(url: URL, size: CGFloat) {
        self.url = url
        self.size = size
        _image = State(initialValue: ImageLoader.cached(url, size: .thumbnail))
    }

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
            guard image == nil else { return }
            image = await ImageLoader.load(url, size: .thumbnail)
        }
    }
}
