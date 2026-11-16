import SwiftUI

/// Menu bar tile with one-click layouts for the window you were using.
struct WindowsTileView: View {
    let module: WindowsModule
    @Environment(\.dismiss) private var dismiss

    private static let quickActions: [WindowAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .leftThird, .centerThird, .rightThird, .maximize,
    ]

    var body: some View {
        let descriptor = WindowsModule.descriptor

        ModuleTile(
            title: descriptor.title,
            subtitle: module.hasAccess
                ? String(localized: "Layout for the active window")
                : String(localized: "Permission needed"),
            systemImage: descriptor.systemImage,
            tint: descriptor.tint,
            action: { if !module.hasAccess { module.requestAccess() } }
        ) {
            if module.hasAccess {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Self.quickActions) { action in
                        LayoutButton(action: action) { run(action) }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func run(_ action: WindowAction) {
        dismiss()
        // Let the panel close so the window you were using is in front again.
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            module.perform(action)
        }
    }
}

private struct LayoutButton: View {
    let action: WindowAction
    let perform: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: action.systemImage)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color.primary.opacity(isHovered ? 0.12 : 0.05), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(action.title))
        .accessibilityLabel(Text(action.title))
    }
}
