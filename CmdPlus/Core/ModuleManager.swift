import SwiftUI
import Observation

/// Включает и выключает модули, помнит выбор пользователя между запусками.
@Observable
final class ModuleManager {
    static let shared = ModuleManager()

    let descriptors: [ModuleDescriptor] = ModuleRegistry.all
    private(set) var enabledIDs: Set<String>
    /// Только запущенные модули. Выключенных здесь нет — их объекты не существуют.
    private(set) var activeModules: [String: any AppModule] = [:]

    private static let enabledKey = "modules.enabled"

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.enabledKey) {
            enabledIDs = Set(saved)
        } else {
            enabledIDs = Set(ModuleRegistry.all.filter(\.enabledByDefault).map(\.id))
        }
    }

    /// Запущенные модули в порядке реестра — для плиток в строке меню.
    var activeDescriptors: [ModuleDescriptor] {
        descriptors.filter { activeModules[$0.id] != nil }
    }

    func module(for id: String) -> (any AppModule)? {
        activeModules[id]
    }

    func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let descriptor = descriptors.first(where: { $0.id == id }) else { return }
        if enabled {
            enabledIDs.insert(id)
            activate(descriptor)
        } else {
            enabledIDs.remove(id)
            deactivate(id)
        }
        UserDefaults.standard.set(Array(enabledIDs).sorted(), forKey: Self.enabledKey)
    }

    /// Готовая привязка для `Toggle` в настройках.
    func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(id) },
            set: { self.setEnabled($0, for: id) }
        )
    }

    func startEnabledModules() {
        for descriptor in descriptors where enabledIDs.contains(descriptor.id) {
            activate(descriptor)
        }
    }

    func stopAll() {
        for id in activeModules.keys {
            deactivate(id)
        }
    }

    private func activate(_ descriptor: ModuleDescriptor) {
        guard activeModules[descriptor.id] == nil else { return }
        let module = descriptor.make()
        activeModules[descriptor.id] = module
        module.start()
    }

    private func deactivate(_ id: String) {
        guard let module = activeModules.removeValue(forKey: id) else { return }
        // После stop() на модуль больше никто не ссылается, и он освобождается.
        module.stop()
    }
}
