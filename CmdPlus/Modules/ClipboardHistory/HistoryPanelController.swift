import AppKit
import SwiftUI

/// The Spotlight-style history window.
///
/// It's a non-activating panel: it takes keyboard input without making CmdPlus
/// the active app, so focus stays in your app and pasting lands there.
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let panel: HistoryPanel
    let viewModel: HistoryViewModel
    /// True during Touch ID or a drag — leave the window alone.
    var suppressAutoClose = false
    private var keyMonitor: Any?
    /// True while we position the window ourselves, so those moves aren't saved.
    private var isPositioning = false

    private static let size: NSSize = Design.History.windowSize

    init(module: ClipboardHistoryModule) {
        viewModel = HistoryViewModel(module: module)
        panel = HistoryPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        super.init()

        let hosting = NSHostingView(rootView: HistoryView(model: viewModel))
        hosting.sizingOptions = []

        let glass = NSGlassEffectView()
        glass.cornerRadius = Design.History.windowRadius
        glass.contentView = hosting

        // Borderless windows are rectangular. Clip to the glass corner radius,
        // otherwise dark corners from the square shadow show through.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Design.History.windowRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        panel.contentView = container
        panel.delegate = self

        viewModel.close = { [weak self] in self?.close() }
        viewModel.dragStarted = { [weak self] in self?.beginDragOut() }
    }

    var isVisible: Bool { panel.isVisible }
    /// Visible and focused — i.e. in use, not covered by another window.
    var isActive: Bool { panel.isVisible && panel.isKeyWindow }

    /// Already open but covered — bring it forward without resetting the search.
    func bringToFront() {
        orderFrontAndFocus()
    }

    /// CmdPlus doesn't become active here, so `makeKeyAndOrderFront` would put the
    /// window *behind* the current app. `orderFrontRegardless` puts it on top.
    private func orderFrontAndFocus() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func show() {
        viewModel.prepareForShow()
        positionOnActiveScreen()
        orderFrontAndFocus()
        // The shadow follows the content's shape — recompute once it's drawn.
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
        installKeyMonitor()
    }

    func close() {
        removeKeyMonitor()
        panel.orderOut(nil)
        viewModel.didClose()
    }

    /// While an item is dragged out, make the window transparent and click-through
    /// so it doesn't cover the drop target, then show it again on mouse-up.
    /// (Hiding it outright would cancel the drag.)
    private func beginDragOut() {
        guard !suppressAutoClose else { return }
        suppressAutoClose = true
        panel.ignoresMouseEvents = true
        panel.animator().alphaValue = 0
        Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self else { return }
            self.panel.alphaValue = 1
            self.panel.ignoresMouseEvents = false
            self.suppressAutoClose = false
        }
    }

    func makeKeyIfVisible() {
        if panel.isVisible { panel.makeKey() }
    }

    // The window doesn't close when you switch away — only via Esc, ⇧⌘V,
    // the close button, or after picking an item.

    private static let originKey = "clipboard.panelOrigin"

    /// Where the user left the window, remembered across launches.
    private var savedOrigin: NSPoint? {
        get {
            guard let string = UserDefaults.standard.string(forKey: Self.originKey) else { return nil }
            return NSPointFromString(string)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(NSStringFromPoint(newValue), forKey: Self.originKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.originKey)
            }
        }
    }

    /// Restore the saved spot if it's on the screen with the cursor;
    /// otherwise center it a bit above the middle, like Spotlight.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        if let savedOrigin, visible.contains(NSRect(origin: savedOrigin, size: Self.size)) {
            isPositioning = true
            panel.setFrame(NSRect(origin: savedOrigin, size: Self.size), display: true)
            isPositioning = false
            return
        }
        let origin = NSPoint(
            x: visible.midX - Self.size.width / 2,
            y: visible.maxY - Self.size.height - visible.height * 0.15
        )
        isPositioning = true
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
        isPositioning = false
    }

    /// The user moved the window (not us) — remember where.
    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, panel.isVisible else { return }
        savedOrigin = panel.frame.origin
    }

    /// Handle arrows, Return, Esc and shortcuts at the window level so they work
    /// even while typing in the search field.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.viewModel.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// A borderless, normal-level panel that can take keyboard input.
final class HistoryPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        // A regular window that other windows can cover. ⇧⌘V moves it to the current Space.
        isFloatingPanel = false
        level = .normal
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
