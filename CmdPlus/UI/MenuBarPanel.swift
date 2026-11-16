import SwiftUI

/// Окно, которое выпадает по клику на иконку в строке меню.
/// Показывает плитки только включённых модулей.
struct MenuBarPanel: View {
    @Environment(ModuleManager.self) private var modules
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if modules.activeDescriptors.isEmpty {
                ContentUnavailableView(
                    "No Modules Enabled",
                    systemImage: "square.grid.2x2",
                    description: Text("Turn on modules in Settings.")
                )
                .frame(maxWidth: .infinity)
            } else {
                GlassEffectContainer(spacing: Design.Panel.tileSpacing) {
                    VStack(spacing: Design.Panel.tileSpacing) {
                        ForEach(modules.activeDescriptors) { descriptor in
                            if let module = modules.module(for: descriptor.id) {
                                module.makeTile()
                            }
                        }
                    }
                }
            }
        }
        .padding(Design.Panel.padding)
        .frame(width: 340)
    }

    /// Шапка как в Пункте управления: название слева, круглые кнопки справа.
    private var header: some View {
        HStack(spacing: 8) {
            Text(verbatim: "CmdPlus")
                .font(.headline)
                .padding(.leading, 6)

            Spacer()

            Button("Settings…", systemImage: "gearshape") {
                // У приложения без Dock окно настроек нужно явно вывести на передний план.
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            .help(Text("Settings…"))

            Button("Quit", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
            .help(Text("Quit"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}
