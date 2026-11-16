import AppKit

/// Handles app lifecycle events SwiftUI doesn't expose (launch, quit).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the theme before any window appears to avoid a flash.
        AppTheme.saved.apply()
        // Start modules on the next run loop pass so launch feels instant.
        Task { @MainActor in
            ModuleManager.shared.startEnabledModules()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ModuleManager.shared.stopAll()
    }
}
