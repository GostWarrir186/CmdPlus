import SwiftUI

/// Работающий экземпляр модуля. Создаётся только когда модуль включён
/// и уничтожается при выключении — поэтому выключенный модуль не занимает память.
protocol AppModule: AnyObject {
    /// Вызывается сразу после создания: подписки, таймеры, горячие клавиши.
    func start()
    /// Вызывается перед уничтожением: сохранить данные и всё отключить.
    func stop()
    /// Плитка для панели в строке меню.
    func makeTile() -> AnyView
    /// Параметры модуля для правой части окна настроек.
    func makeSettingsView() -> AnyView
}

/// «Паспорт» модуля: лёгкое описание, которое есть всегда (имя, иконка),
/// плюс фабрика `make`, создающая тяжёлый экземпляр только по требованию.
struct ModuleDescriptor: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let systemImage: String
    let tint: Color
    var enabledByDefault = true
    let make: () -> any AppModule
}

/// Список всех модулей приложения. Новый модуль = одна строка здесь.
enum ModuleRegistry {
    static let all: [ModuleDescriptor] = [
        ClipboardHistoryModule.descriptor,
    ]
}
