import AppKit
import SwiftUI

/// A transparent area you can drag the window by.
///
/// In borderless windows SwiftUI content swallows clicks, so
/// `isMovableByWindowBackground` doesn't help. Put this behind headers and
/// footers; controls on top keep working, empty space moves the window.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
