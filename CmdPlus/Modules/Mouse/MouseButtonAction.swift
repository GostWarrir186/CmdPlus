import Carbon.HIToolbox
import SwiftUI

/// What a mouse side button does.
nonisolated enum MouseButtonAction: String, CaseIterable, Identifiable, Sendable {
    /// Leave the button alone — apps handle it as usual.
    case systemDefault
    /// Swallow the click.
    case nothing
    case back
    case forward
    case missionControl
    case appWindows
    case previousSpace
    case nextSpace
    case showDesktop
    case clipboardHistory
    case copy
    case paste
    case undo
    case newTab
    case closeTab

    var id: String { rawValue }

    /// Picker sections, in order.
    static let groups: [[MouseButtonAction]] = [
        [.systemDefault, .nothing],
        [.back, .forward],
        [.missionControl, .appWindows, .previousSpace, .nextSpace, .showDesktop],
        [.clipboardHistory],
        [.copy, .paste, .undo],
        [.newTab, .closeTab],
    ]

    var title: LocalizedStringResource {
        switch self {
        case .systemDefault: "System Default"
        case .nothing: "Do Nothing"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appWindows: "App Windows"
        case .previousSpace: "Previous Desktop"
        case .nextSpace: "Next Desktop"
        case .showDesktop: "Show Desktop"
        case .clipboardHistory: "Clipboard History"
        case .copy: "Copy"
        case .paste: "Paste"
        case .undo: "Undo"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        }
    }

    /// The shortcut sent for this action. `nil` for the two pass-through choices.
    var keyCombo: KeyCombo? {
        switch self {
        case .systemDefault, .nothing: nil
        case .back: KeyCombo(kVK_ANSI_LeftBracket, .maskCommand)
        case .forward: KeyCombo(kVK_ANSI_RightBracket, .maskCommand)
        case .missionControl: KeyCombo(kVK_UpArrow, .maskControl)
        case .appWindows: KeyCombo(kVK_DownArrow, .maskControl)
        case .previousSpace: KeyCombo(kVK_LeftArrow, .maskControl)
        case .nextSpace: KeyCombo(kVK_RightArrow, .maskControl)
        case .showDesktop: KeyCombo(kVK_F11)
        case .clipboardHistory: KeyCombo(kVK_ANSI_V, [.maskShift, .maskCommand])
        case .copy: KeyCombo(kVK_ANSI_C, .maskCommand)
        case .paste: KeyCombo(kVK_ANSI_V, .maskCommand)
        case .undo: KeyCombo(kVK_ANSI_Z, .maskCommand)
        case .newTab: KeyCombo(kVK_ANSI_T, .maskCommand)
        case .closeTab: KeyCombo(kVK_ANSI_W, .maskCommand)
        }
    }

    /// Whether CmdPlus has to intercept the button at all.
    var interceptsButton: Bool { self != .systemDefault }
}
