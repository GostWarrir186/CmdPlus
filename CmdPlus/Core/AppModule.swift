import SwiftUI

/// A running module instance. It only exists while the module is enabled,
/// so a disabled module costs nothing.
protocol AppModule: AnyObject {
    func start()
    /// Save state and tear everything down.
    func stop()
    func makeTile() -> AnyView
    func makeSettingsView() -> AnyView
}

/// Lightweight info that's always available (name, icon), plus a factory
/// that builds the real module only when it's turned on.
struct ModuleDescriptor: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let systemImage: String
    let tint: Color
    var enabledByDefault = true
    let make: () -> any AppModule
}

/// Every module in the app. Adding one is a single line here.
enum ModuleRegistry {
    static let all: [ModuleDescriptor] = [
        ClipboardHistoryModule.descriptor,
        MouseModule.descriptor,
    ]
}
