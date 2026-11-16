import SwiftUI
import Observation

/// Turns modules on and off and remembers the choice between launches.
@Observable
final class ModuleManager {
    static let shared = ModuleManager()

    let descriptors: [ModuleDescriptor] = ModuleRegistry.all
    private(set) var enabledIDs: Set<String>
    /// Disabled modules aren't here at all — their objects don't exist.
    private(set) var activeModules: [String: any AppModule] = [:]

    private static let enabledKey = "modules.enabled"

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.enabledKey) {
            enabledIDs = Set(saved)
        } else {
            enabledIDs = Set(ModuleRegistry.all.filter(\.enabledByDefault).map(\.id))
        }
    }

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
        // Nothing holds the module after stop(), so it's freed here.
        module.stop()
    }
}
