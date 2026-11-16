import SwiftUI

/// No windows at launch — just the menu bar icon. Settings opens on demand.
@main
struct CmdPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var modules: ModuleManager

    init() {
        // Must run before anything reads settings — ModuleManager does on creation.
        SandboxMigration.runIfNeeded()
        _modules = State(initialValue: ModuleManager.shared)
    }

    var body: some Scene {
        MenuBarExtra("CmdPlus", systemImage: "command.square.fill") {
            MenuBarPanel()
                .environment(modules)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(modules)
        }
        .windowResizability(.contentMinSize)
    }
}
