import AppKit
import Carbon.HIToolbox

/// Pastes for the user by sending ⌘V to the frontmost app.
///
/// The history window never activates CmdPlus, so focus is still wherever you
/// were working. Needs Accessibility permission, requested only from a button.
enum PasteSimulator {
    /// Checks permission without showing a system prompt.
    static var hasAccess: Bool {
        CGPreflightPostEventAccess()
    }

    /// Shows the system prompt. If the user already declined (so no prompt appears),
    /// opens the right pane in System Settings instead.
    static func requestAccess() {
        guard !CGRequestPostEventAccess() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns `false` without permission.
    @discardableResult
    static func pressCommandV() -> Bool {
        guard hasAccess else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
