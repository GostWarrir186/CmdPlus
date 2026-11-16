import SwiftUI

/// The panel that drops down from the menu bar icon. Shows tiles for enabled modules.
struct MenuBarPanel: View {
    @Environment(ModuleManager.self) private var modules
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

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

    /// Control Center-style header: title on the left, round buttons on the right.
    private var header: some View {
        HStack(spacing: 8) {
            Text(verbatim: "CmdPlus")
                .font(.headline)
                .padding(.leading, 6)

            Spacer()

            Button("Settings…", systemImage: "gearshape") {
                // Close the panel so it doesn't sit on top of Settings.
                dismiss()
                // Without a Dock icon, Settings has to be brought forward explicitly.
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
