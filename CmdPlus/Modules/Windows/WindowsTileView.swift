import Carbon.HIToolbox
import SwiftUI

/// Menu bar tile with a "Move & Resize" menu, laid out like macOS's own
/// Window menu: every layout with its icon and shortcut.
struct WindowsTileView: View {
    let module: WindowsModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let descriptor = WindowsModule.descriptor

        ModuleTile(
            title: descriptor.title,
            subtitle: module.hasAccess
                ? String(localized: "For the window you were using")
                : String(localized: "Permission needed"),
            systemImage: descriptor.systemImage,
            tint: descriptor.tint,
            action: { if !module.hasAccess { module.requestAccess() } }
        ) {
            if module.hasAccess {
                Menu {
                    ForEach(Array(WindowAction.groups.enumerated()), id: \.offset) { index, group in
                        Section {
                            ForEach(group.actions) { action in
                                menuItem(action)
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                } label: {
                    Label("Move & Resize", systemImage: "macwindow.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .padding(.leading, ModuleTile<EmptyView>.iconSize + ModuleTile<EmptyView>.iconSpacing)
            }
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
