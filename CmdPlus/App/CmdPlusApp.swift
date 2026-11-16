import SwiftUI

/// Точка входа. У приложения нет обычных окон при запуске:
/// только иконка в строке меню (MenuBarExtra) и окно настроек (Settings),
/// которое открывается лишь по запросу пользователя.
@main
struct CmdPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var modules = ModuleManager.shared

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
