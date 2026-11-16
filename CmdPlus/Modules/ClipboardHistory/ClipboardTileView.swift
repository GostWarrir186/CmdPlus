import SwiftUI

/// Плитка модуля в панели строки меню: число записей и три последние.
struct ClipboardTileView: View {
    let module: ClipboardHistoryModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let store = module.store
        let descriptor = ClipboardHistoryModule.descriptor

        ModuleTile(
            title: descriptor.title,
            subtitle: String(localized: "\(store.items.count) items"),
            systemImage: descriptor.systemImage,
            tint: descriptor.tint,
            shortcut: "⇧⌘V",
            action: openHistory
        ) {
            if store.items.isEmpty {
                Text("Copy something and it will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, ModuleTile<EmptyView>.iconSize + ModuleTile<EmptyView>.iconSpacing)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.items.prefix(3)) { item in
                        RecentItemRow(item: item, imageURL: store.imageURL(for: item)) {
                            Task {
                                await module.copyToPasteboard(item)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    private func openHistory() {
        dismiss()
        module.showPanel()
    }
}

/// Строка недавней записи. Иконка стоит в той же колонке, что и иконка плитки,
/// а текст начинается там же, где заголовок плитки.
private struct RecentItemRow: View {
    let item: ClipboardItem
    let imageURL: URL?
    let action: () -> Void
    @State private var isHovered = false

    private static let thumbnailSize: CGFloat = 22

    var body: some View {
        Button(action: action) {
            HStack(spacing: ModuleTile<EmptyView>.iconSpacing) {
                leadingIcon
                    .frame(width: ModuleTile<EmptyView>.iconSize)
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            // Подсветка выходит за края строки на rowInset — ровно до отступа плитки,
            // а её радиус согласован с радиусом плитки.
            RoundedRectangle(cornerRadius: Design.Panel.rowRadius)
                .fill(.primary.opacity(isHovered ? 0.08 : 0))
                .padding(.horizontal, -(Design.Panel.tilePadding - Design.Panel.rowInset))
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if !item.isSecret, item.kind == .image, let imageURL {
            ThumbnailView(url: imageURL, size: Self.thumbnailSize)
        } else if !item.isSecret, item.kind == .files, let path = item.filePaths?.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        } else {
            Image(systemName: item.isSecret ? "key.fill" : "text.alignleft")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        }
    }

    private var title: String {
        if item.isSecret { return "••••••••" }
        switch item.kind {
        case .text:
            return SearchHighlighter.preview(of: item.text ?? "", terms: [], limit: 60)
        case .image:
            if let width = item.imageWidth, let height = item.imageHeight {
                return String(localized: "Image") + " \(width)×\(height)"
            }
            return String(localized: "Image")
        case .files:
            return item.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        }
    }
}
