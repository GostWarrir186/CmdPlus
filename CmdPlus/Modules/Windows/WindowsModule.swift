import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Window management: snap the focused window to halves, quarters, thirds and
/// more with keyboard shortcuts or from the menu bar.
@Observable
final class WindowsModule: AppModule {
    static let descriptor = ModuleDescriptor(
        id: "windows",
        title: "Windows",
        summary: "Snap windows to halves, quarters and thirds with shortcuts.",
        systemImage: "uiwindow.split.2x1",
        tint: .teal,
        // Needs Accessibility permission, so the user turns it on deliberately.
        enabledByDefault: false,
        make: { WindowsModule() }
    )

    let settings: WindowSettings
    private(set) var hasAccess = WindowMover.isTrusted
    /// Actions whose shortcut another app already owns.
    private(set) var conflicts: Set<WindowAction> = []

    @ObservationIgnored private let mover = WindowMover()
    @ObservationIgnored private var hotKeys: [GlobalHotKey] = []
    /// While a shortcut is being recorded, hotkeys are off so the keys reach the recorder.
    @ObservationIgnored var isRecordingShortcut = false {
        didSet { registerHotKeys() }
    }

    init(settings: WindowSettings = WindowSettings()) {
        self.settings = settings
    }

    func start() {
        settings.onShortcutsChange = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()
    }

    func stop() {
        settings.onShortcutsChange = {}
        unregisterHotKeys()
    }

    func makeTile() -> AnyView {
        AnyView(WindowsTileView(module: self))
    }

    func makeSettingsView() -> AnyView {
        AnyView(WindowsSettingsView(module: self))
    }

    func perform(_ action: WindowAction) {
        guard hasAccess || refreshAccess() else {
            NSSound.beep()
            return
        }
        if !mover.perform(action, gap: settings.gap.points) {
            NSSound.beep()
        }
    }

    // MARK: - Permission

    @discardableResult
    func refreshAccess() -> Bool {
        hasAccess = WindowMover.isTrusted
        return hasAccess
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            InputAccess.request()
        }
        refreshAccess()
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        unregisterHotKeys()
        guard !isRecordingShortcut else { return }
        var failed: Set<WindowAction> = []
        for (action, combo) in settings.shortcuts {
            if let hotKey = GlobalHotKey(keyCode: Int(combo.keyCode), modifiers: combo.carbonModifiers,
                                         action: { [weak self] in self?.perform(action) }) {
                hotKeys.append(hotKey)
            } else {
                failed.insert(action)
            }
        }
        conflicts = failed
    }

    private func unregisterHotKeys() {
        hotKeys.forEach { $0.unregister() }
        hotKeys = []
    }
}
