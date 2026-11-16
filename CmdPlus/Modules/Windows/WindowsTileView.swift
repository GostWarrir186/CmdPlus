import Carbon.HIToolbox
import SwiftUI

/// Menu bar tile. Click it to show a compact grid of layouts — each a tiny
/// picture of where the window goes, with its name.
struct WindowsTileView: View {
    let module: WindowsModule
    @Environment(\.dismiss) private var dismiss
    @AppStorage("windows.tileExpanded") private var isExpanded = true

    var body: some View {
        let descriptor = WindowsModule.descriptor

        if module.hasAccess {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
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
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .padding(.trailing, 4)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(WindowAction.groups.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top),
                                                         count: 5),
                                          alignment: .leading, spacing: 4) {
                                    ForEach(group.actions) { action in
                                        LayoutButton(action: action, shortcut: module.settings.shortcuts[action]) {
                                            run(action)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .modifier(TileBackground())
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

    private func run(_ action: WindowAction) {
        dismiss()
        // Let the panel close so the window you were using is in front again.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            module.perform(action)
        }
    }
}

/// Picture + short name. The shortcut shows on hover.
private struct LayoutButton: View {
    let action: WindowAction
    let shortcut: KeyCombo?
    let perform: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 3) {
                LayoutPictogram(action: action, size: CGSize(width: 44, height: 28))
                Text(action.shortTitle)
                    .font(.system(size: 9.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(verbatim: helpText))
        .accessibilityLabel(Text(action.title))
    }

    private var helpText: String {
        let title = String(localized: action.title)
        guard let shortcut else { return title }
        return "\(title)  \(shortcut.displayString)"
    }
}
