import Carbon.HIToolbox
import SwiftUI

/// Menu bar tile with a "Move & Resize" menu, laid out like macOS's own
/// Window menu: every layout with its icon and shortcut.
struct WindowsTileView: View {
    let module: WindowsModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let descriptor = WindowsModule.descriptor

        if module.hasAccess {
            // The whole tile opens the Move & Resize menu.
            Menu {
                ForEach(Array(WindowAction.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.actions) { action in
                            menuItem(action)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            } label: {
                TileHeader(
                    title: descriptor.title,
                    subtitle: String(localized: "Move & Resize"),
                    systemImage: descriptor.systemImage,
                    tint: descriptor.tint
                ) {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .modifier(TileBackground())
            .help(Text("Move & Resize the window you were using"))
        } else {
            ModuleTile(
                title: descriptor.title,
                subtitle: String(localized: "Permission needed"),
                systemImage: descriptor.systemImage,
                tint: descriptor.tint,
                action: { module.requestAccess() }
            )
        }
    }

    @ViewBuilder
    private func menuItem(_ action: WindowAction) -> some View {
        let button = Button {
            run(action)
        } label: {
            Label {
                Text(action.title)
            } icon: {
                Image(systemName: action.systemImage)
            }
        }
        if let shortcut = module.settings.shortcuts[action]?.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    private func run(_ action: WindowAction) {
        dismiss()
        // Let the panel close so the window you were using is in front again.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            module.perform(action)
        }
    }
}

extension KeyCombo {
    /// The same shortcut for SwiftUI, so menus can show it next to an item.
    var swiftUIShortcut: KeyboardShortcut? {
        let special: [Int: KeyEquivalent] = [
            kVK_LeftArrow: .leftArrow, kVK_RightArrow: .rightArrow, kVK_UpArrow: .upArrow,
            kVK_DownArrow: .downArrow, kVK_Return: .return, kVK_Delete: .delete, kVK_Tab: .tab,
            kVK_Space: .space, kVK_Escape: .escape, kVK_Home: .home, kVK_End: .end,
            kVK_PageUp: .pageUp, kVK_PageDown: .pageDown, kVK_ForwardDelete: .deleteForward,
        ]
        let key: KeyEquivalent
        if let named = special[Int(keyCode)] {
            key = named
        } else {
            let name = KeyCombo.keyName(Int(keyCode))
            guard name.count == 1, let character = name.lowercased().first else { return nil }
            key = KeyEquivalent(character)
        }
        var modifiers: SwiftUI.EventModifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}
