import AppKit
import Observation
import SwiftUI

/// Mouse module: reverse scrolling for wheel mice and actions for side buttons.
@Observable
final class MouseModule: AppModule {
    static let descriptor = ModuleDescriptor(
        id: "mouse",
        title: "Mouse",
        summary: "Reverse scrolling for mice and actions for side buttons.",
        systemImage: "computermouse.fill",
        tint: .indigo,
        // Needs Accessibility permission, so the user turns it on deliberately.
        enabledByDefault: false,
        make: { MouseModule() }
    )

    let settings: MouseSettings
    private(set) var hasAccess = InputAccess.isGranted
    @ObservationIgnored private let eventTap: MouseEventTap

    init(settings: MouseSettings = MouseSettings()) {
        self.settings = settings
        eventTap = MouseEventTap(settings: settings)
    }

    func start() {
        settings.onChange = { [weak self] in self?.updateEventTap() }
        updateEventTap()
    }

    func stop() {
        settings.onChange = {}
        eventTap.stop()
    }

    func makeTile() -> AnyView {
        AnyView(MouseTileView(module: self))
    }

    func makeSettingsView() -> AnyView {
        AnyView(MouseSettingsView(module: self))
    }

    // MARK: - Permission

    func refreshAccess() {
        hasAccess = InputAccess.isGranted
        updateEventTap()
    }

    func requestAccess() {
        InputAccess.request()
        refreshAccess()
    }

    /// Runs the tap only when it's allowed and there's something to do.
    private func updateEventTap() {
        if hasAccess && settings.needsEventTap {
            eventTap.start()
        } else {
            eventTap.stop()
        }
    }
}
