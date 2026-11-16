import AppKit
import SwiftUI

/// The big "+" area: hover it and press any extra mouse button to add it.
struct ButtonCaptureField: View {
    let settings: MouseSettings
    /// Called with the new (or existing) row so the list can highlight it.
    var onAdd: (UUID) -> Void = { _ in }
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered ? Color.accentColor : Color.primary.opacity(0.15),
                              style: StrokeStyle(lineWidth: 1, dash: isHovered ? [] : [6, 4]))
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isHovered ? Color.accentColor : .secondary)
            ClickCatcher(
                onHover: { hovering in
                    isHovered = hovering
                    // Let the event tap pass every button through while we listen.
                    settings.isCapturingButtons = hovering
                },
                onClick: add
            )
        }
        .frame(height: 120)
        .onDisappear { settings.isCapturingButtons = false }
        .accessibilityLabel(Text("Add a mouse button"))
    }

    @State private var lastSingleClick: UUID?

    private func add(button: Int64, clickCount: Int) {
        guard ButtonBinding.isAssignable(button) else { return }
        if clickCount >= 2 {
            // A double click starts with a single one — drop that fresh row.
            if let id = lastSingleClick,
               let row = settings.bindings.first(where: { $0.id == id }), row.action == .systemDefault {
                settings.removeBinding(id)
            }
            if let id = settings.addBinding(button: button, trigger: .doubleClick) { onAdd(id) }
        } else {
            let existed = settings.bindings.contains { $0.button == button && $0.trigger == .click }
            let id = settings.addBinding(button: button, trigger: .click)
            lastSingleClick = existed ? nil : id
            if let id { onAdd(id) }
        }
    }
}

/// Catches extra mouse buttons (middle, 4, 5…) and hover over its area.
private struct ClickCatcher: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onClick: (_ button: Int64, _ clickCount: Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onHover = onHover
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onHover = onHover
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        var onClick: (Int64, Int) -> Void = { _, _ in }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func otherMouseDown(with event: NSEvent) {
            onClick(Int64(event.buttonNumber), event.clickCount)
        }
    }
}

extension ButtonBinding {
    /// "Middle Button", "Button 4"… — numbered from 1 like most mouse software.
    static func name(of button: Int64) -> LocalizedStringResource {
        button == 2 ? "Middle Button" : "Button \(button + 1)"
    }
}
