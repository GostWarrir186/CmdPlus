import AppKit
import SwiftUI

/// Плавающее окно истории в стиле Spotlight.
///
/// Это «неактивирующая» панель: она получает ввод с клавиатуры,
/// но не делает CmdPlus активным приложением. Поэтому после выбора записи
/// фокус остаётся в вашем приложении, и CmdPlus вставляет запись туда сам (⌘V).
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let panel: HistoryPanel
    let viewModel: HistoryViewModel
    /// Пока идёт Touch ID, окно теряет фокус — в это время не закрываем его.
    var suppressAutoClose = false
    private var keyMonitor: Any?

    private static let size: NSSize = Design.History.windowSize

    init(module: ClipboardHistoryModule) {
        viewModel = HistoryViewModel(module: module)
        panel = HistoryPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        super.init()

        let hosting = NSHostingView(rootView: HistoryView(model: viewModel))
        hosting.sizingOptions = []

        // Фон окна — системное стекло Liquid Glass.
        let glass = NSGlassEffectView()
        glass.cornerRadius = Design.History.windowRadius
        glass.contentView = hosting
        panel.contentView = glass
        panel.delegate = self

        viewModel.close = { [weak self] in self?.close() }
        viewModel.dragStarted = { [weak self] in self?.beginDragOut() }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        viewModel.prepareForShow()
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        removeKeyMonitor()
        panel.orderOut(nil)
        viewModel.didClose()
    }

    /// Запись тянут в другое приложение: окно становится прозрачным и пропускает
    /// мышь, чтобы не закрывать место, куда бросают. Закрываем, когда кнопку отпустили.
    /// (Сразу убрать окно нельзя — это оборвало бы перетаскивание.)
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
            self.close()
            self.panel.alphaValue = 1
            self.panel.ignoresMouseEvents = false
            self.suppressAutoClose = false
        }
    }

    func makeKeyIfVisible() {
        if panel.isVisible { panel.makeKey() }
    }

    func windowDidResignKey(_ notification: Notification) {
        if !suppressAutoClose { close() }
    }

    /// По центру экрана, где сейчас курсор, чуть выше середины — как Spotlight.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - Self.size.width / 2,
            y: visible.maxY - Self.size.height - visible.height * 0.15
        )
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }

    /// Стрелки, Enter, Esc и сочетания обрабатываем на уровне окна,
    /// чтобы они работали, даже когда курсор в поле поиска.
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

/// Окно без рамки, которое может принимать ввод с клавиатуры.
final class HistoryPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
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
