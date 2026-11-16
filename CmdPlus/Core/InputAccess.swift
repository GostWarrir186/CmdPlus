import AppKit
import Carbon.HIToolbox

/// The Accessibility permission CmdPlus needs to send keystrokes and to change
/// mouse events. Asked for only from a button the user clicks.
enum InputAccess {
    /// Checks permission without showing a system prompt.
    static var isGranted: Bool {
        CGPreflightPostEventAccess()
    }

    /// Shows the system prompt. If the user already declined (so no prompt appears),
    /// opens the right pane in System Settings instead.
    static func request() {
        guard !CGRequestPostEventAccess() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A keyboard shortcut CmdPlus can press for the user.
nonisolated struct KeyCombo: Equatable, Sendable, Codable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    init(_ keyCode: Int, _ flags: CGEventFlags = []) {
        self.keyCode = CGKeyCode(keyCode)
        // The Dock only reacts to arrow-key shortcuts (Mission Control, Spaces)
        // when they carry the same flags a real arrow key has.
        let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        self.flags = arrows.contains(keyCode) ? flags.union([.maskSecondaryFn, .maskNumericPad]) : flags
    }

    private enum CodingKeys: String, CodingKey { case keyCode, flags }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(CGKeyCode.self, forKey: .keyCode)
        flags = CGEventFlags(rawValue: try container.decode(UInt64.self, forKey: .flags))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(flags.rawValue, forKey: .flags)
    }

    /// Returns `false` without permission.
    @discardableResult
    func post() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
