import SwiftUI

/// Menu bar tile: title, item count and ⇧⌘V. It just opens the history window —
/// no item list here, so the panel opens instantly and doesn't load thumbnails.
struct ClipboardTileView: View {
    let module: ClipboardHistoryModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let descriptor = ClipboardHistoryModule.descriptor

        ModuleTile(
            title: descriptor.title,
            subtitle: String(localized: "\(module.store.items.count) items"),
            systemImage: descriptor.systemImage,
            tint: descriptor.tint,
            shortcut: "⇧⌘V",
            action: openHistory
        )
        .help(Text("Open Clipboard History"))
    }

    private func openHistory() {
        dismiss()
        module.showPanel()
    }
}
