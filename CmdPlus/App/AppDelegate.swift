import AppKit

/// Делегат приложения: здесь ловим события жизненного цикла,
/// которых нет в чистом SwiftUI (запуск и завершение).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Тему ставим до появления любых окон, чтобы не было мигания.
        AppTheme.saved.apply()
        // Запускаем только включённые модули. Делаем это на следующем
        // проходе главного цикла, чтобы старт приложения был мгновенным.
        Task { @MainActor in
            ModuleManager.shared.startEnabledModules()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Даём модулям сохранить данные на диск перед выходом.
        ModuleManager.shared.stopAll()
    }
}
