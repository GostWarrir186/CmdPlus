import AppKit

/// A brief highlight where a window just landed, so it's clear what happened.
/// The panels are created once and reused; nothing runs between snaps.
final class WindowFootprint {
    private var panels: [NSPanel] = []

    func flash(_ frames: [CGRect]) {
        while panels.count < frames.count { panels.append(Self.makePanel()) }
        for (panel, frame) in zip(panels, frames) {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        let shown = Array(panels.prefix(frames.count))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                shown.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: {
                MainActor.assumeIsolated { shown.forEach { $0.orderOut(nil) } }
            }
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        view.layer?.borderWidth = 2
        panel.contentView = view
        return panel
    }
}
