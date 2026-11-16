import Carbon.HIToolbox

/// Pastes for the user by sending ⌘V to the frontmost app.
///
/// The history window never activates CmdPlus, so focus is still wherever you
/// were working.
enum PasteSimulator {
    static var hasAccess: Bool { InputAccess.isGranted }

    static func requestAccess() { InputAccess.request() }

    /// Returns `false` without permission.
    @discardableResult
    static func pressCommandV() -> Bool {
        KeyCombo(kVK_ANSI_V, .maskCommand).post()
    }
}
