import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A small sheet that waits for a key combination. Esc cancels.
struct ShortcutRecorder: View {
    let onFinish: (ShortcutBinding?) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Press a keyboard shortcut")
                .font(.headline)
            Text("For example ⌥⌘4. Press Esc to cancel.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel") { finish(nil) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 320)
        .onAppear(perform: startListening)
        .onDisappear(perform: stopListening)
    }

    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                finish(nil)
                return nil
            }
            finish(Self.binding(for: event))
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func finish(_ binding: ShortcutBinding?) {
        stopListening()
        onFinish(binding)
    }

    static func binding(for event: NSEvent) -> ShortcutBinding {
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        // NSEvent and CGEvent use the same bits for these modifiers.
        let flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        let keyCode = Int(event.keyCode)
        return ShortcutBinding(
            combo: KeyCombo(keyCode, flags),
            display: modifierSymbols(modifiers) + keyName(keyCode, characters: event.charactersIgnoringModifiers)
        )
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    static func keyName(_ keyCode: Int, characters: String?) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[keyCode] { return name }
        return (characters ?? "?").uppercased()
    }
}
