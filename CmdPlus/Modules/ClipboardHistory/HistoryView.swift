import AppKit
import ImageIO
import SwiftUI

/// Содержимое окна истории: поиск, фильтры, список, подсказки.
struct HistoryView: View {
    @Bindable var model: HistoryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let items = model.visibleItems
        let terms = model.terms

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("Search Clipboard History", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Picker("Filter", selection: $model.filter) {
                ForEach(HistoryViewModel.Filter.allCases) { filter in
                    Label {
                        Text(filter.title)
                    } icon: {
                        Image(systemName: filter.systemImage)
                    }
                    .tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

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
                list(items, terms: terms)
            }

            Divider()
            footer(count: items.count)
        }
        .frame(width: 700, height: 480)
        .onChange(of: model.focusRequest, initial: true) {
            isSearchFocused = true
        }
        .onChange(of: model.query) { model.selectFirst() }
        .onChange(of: model.filter) { model.selectFirst() }
    }

    private func list(_ items: [ClipboardItem], terms: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        HistoryRow(
                            item: item,
                            terms: terms,
                            isSelected: item.id == model.selectedID,
                            revealedSecret: model.revealed[item.id],
                            imageURL: model.store?.imageURL(for: item),
                            model: model
                        )
                        .id(item.id)
                    }
                }
                .padding(Design.History.listPadding)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 14) {
            ShortcutHint(keys: "↩", title: "Copy")
            ShortcutHint(keys: "⌘P", title: "Pin")
            ShortcutHint(keys: "⌘⌫", title: "Delete")
            ShortcutHint(keys: "esc", title: "Close")
            Spacer()
            Text("\(count) items")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct ShortcutHint: View {
    let keys: String
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: keys)
                .fontWeight(.semibold)
            Text(title)
        }
    }
}

/// Строка списка.
private struct HistoryRow: View {
    let item: ClipboardItem
    let terms: [String]
    let isSelected: Bool
    let revealedSecret: String?
    let imageURL: URL?
    let model: HistoryViewModel

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon
                .frame(width: Design.History.thumbnailSize, height: Design.History.thumbnailSize)

            VStack(alignment: .leading, spacing: 3) {
                content
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metadata
            }

            if isSelected {
                actions
            }
        }
        .padding(Design.History.rowPadding)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: Design.History.rowRadius)
        )
        .contentShape(.rect)
        .onHover { hovering in
            if hovering { model.selectedID = item.id }
        }
        .onTapGesture { model.activate(item) }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { model.activate(item) }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                model.togglePin(item)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(item) }
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if item.isSecret {
            iconBadge("key.fill", tint: .orange)
        } else {
            switch item.kind {
            case .text:
                iconBadge("text.alignleft", tint: .gray)
            case .image:
                if let imageURL {
                    ThumbnailView(url: imageURL, size: Design.History.thumbnailSize)
                } else {
                    iconBadge("photo", tint: .purple)
                }
            case .files:
                if let path = item.filePaths?.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .scaledToFit()
                } else {
                    iconBadge("doc", tint: .blue)
                }
            }
        }
    }

    private func iconBadge(_ systemImage: String, tint: Color) -> some View {
        TintedIcon(systemImage: systemImage, tint: tint, size: Design.History.thumbnailSize)
    }

    @ViewBuilder
    private var content: some View {
        if item.isSecret {
            if let revealedSecret {
                Text(verbatim: revealedSecret)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } else {
                Text(verbatim: "••••••••••••")
                    .font(.body.monospaced())
            }
        } else {
            switch item.kind {
            case .text:
                let preview = SearchHighlighter.preview(of: item.text ?? "", terms: terms)
                Text(SearchHighlighter.highlight(preview, terms: terms))
            case .image:
                Text("Image")
            case .files:
                let names = item.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
                Text(SearchHighlighter.highlight(names, terms: terms))
            }
        }
    }

    /// Мета-строка: части разделены одинаковой точкой «·», булавка — отдельно слева.
    private var metadata: some View {
        HStack(spacing: 4) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
            }
            ForEach(Array(metadataParts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Text(verbatim: "·") }
                Text(part)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var metadataParts: [AttributedString] {
        var parts: [AttributedString] = []
        if item.isSecret {
            parts.append(AttributedString(localized: "Password"))
        }
        if let width = item.imageWidth, let height = item.imageHeight {
            parts.append(AttributedString("\(width)×\(height)"))
        }
        if let app = item.sourceAppName {
            parts.append(SearchHighlighter.highlight(app, terms: terms))
        }
        parts.append(AttributedString(item.createdAt.formatted(.relative(presentation: .named))))
        return parts
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if item.isSecret {
                Button(revealedSecret == nil ? "Show" : "Hide",
                       systemImage: revealedSecret == nil ? "eye" : "eye.slash") {
                    model.toggleReveal(item)
                }
            }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                model.togglePin(item)
            }
            Button("Delete", systemImage: "trash") {
                model.delete(item)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .imageScale(.large)
    }
}

/// Миниатюра картинки. Читается в фоне и в уменьшенном виде,
/// чтобы 500 картинок в истории не занимали много памяти.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.iconRadius(for: size))
        // Картинка показывается целиком (scaledToFit) на нейтральной подложке:
        // у скриншотов и широких картинок не обрезаются края.
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
            let url = url
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 120,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
        }
    }
}
