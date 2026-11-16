import AppKit
import Carbon.HIToolbox
import SwiftUI

/// What a mouse side button does.
nonisolated enum MouseButtonAction: String, CaseIterable, Identifiable, Sendable {
    /// Leave the button alone — apps handle it as usual.
    case systemDefault
    /// Swallow the click.
    case nothing
    case lookUp
    case middleClick
    case back
    case forward
    case missionControl
    case appWindows
    case showDesktop
    case launchpad
    case previousSpace
    case nextSpace
    case clipboardHistory
    case copy
    case paste
    case undo
    case newTab
    case closeTab
    /// A shortcut the user recorded (stored in `MouseSettings`).
    case keyboardShortcut

    var id: String { rawValue }

    /// Picker sections, in order.
    static let groups: [[MouseButtonAction]] = [
        [.systemDefault, .nothing],
        [.lookUp, .middleClick],
        [.back, .forward],
        [.missionControl, .appWindows, .showDesktop],
        [.launchpad],
        [.previousSpace, .nextSpace],
        [.clipboardHistory],
        [.copy, .paste, .undo],
        [.newTab, .closeTab],
        [.keyboardShortcut],
    ]

    var title: LocalizedStringResource {
        switch self {
        case .systemDefault: "System Default"
        case .nothing: "Do Nothing"
        case .lookUp: "Look Up"
        case .middleClick: "Middle Click"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appWindows: "Application Windows"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Launchpad"
        case .previousSpace: "Move Left a Space"
        case .nextSpace: "Move Right a Space"
        case .clipboardHistory: "Clipboard History"
        case .copy: "Copy"
        case .paste: "Paste"
        case .undo: "Undo"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        case .keyboardShortcut: "Keyboard Shortcut…"
        }
    }

    /// What pressing the button actually does.
    enum Behavior: Equatable {
        case passThrough
        case swallow
        case keys(KeyCombo)
        case middleClick
        case openApp(URL)
        case customShortcut
    }

    var behavior: Behavior {
        switch self {
        case .systemDefault: .passThrough
        case .nothing: .swallow
        case .lookUp: .keys(KeyCombo(kVK_ANSI_D, [.maskControl, .maskCommand]))
        case .middleClick: .middleClick
        case .back: .keys(KeyCombo(kVK_ANSI_LeftBracket, .maskCommand))
        case .forward: .keys(KeyCombo(kVK_ANSI_RightBracket, .maskCommand))
        case .missionControl: .keys(KeyCombo(kVK_UpArrow, .maskControl))
        case .appWindows: .keys(KeyCombo(kVK_DownArrow, .maskControl))
        case .showDesktop: .keys(KeyCombo(kVK_F11))
        // macOS 26 replaced Launchpad with the Apps launcher.
        case .launchpad: .openApp(URL(filePath: "/System/Applications/Apps.app"))
        case .previousSpace: .keys(KeyCombo(kVK_LeftArrow, .maskControl))
        case .nextSpace: .keys(KeyCombo(kVK_RightArrow, .maskControl))
        case .clipboardHistory: .keys(KeyCombo(kVK_ANSI_V, [.maskShift, .maskCommand]))
        case .copy: .keys(KeyCombo(kVK_ANSI_C, .maskCommand))
        case .paste: .keys(KeyCombo(kVK_ANSI_V, .maskCommand))
        case .undo: .keys(KeyCombo(kVK_ANSI_Z, .maskCommand))
        case .newTab: .keys(KeyCombo(kVK_ANSI_T, .maskCommand))
        case .closeTab: .keys(KeyCombo(kVK_ANSI_W, .maskCommand))
        case .keyboardShortcut: .customShortcut
        }
    }

    /// Whether CmdPlus has to intercept the button at all.
    var interceptsButton: Bool { self != .systemDefault }
}

/// A recorded shortcut plus how to show it (e.g. "⌥⌘4").
nonisolated struct ShortcutBinding: Equatable, Sendable, Codable {
    let combo: KeyCombo
    let display: String
}

/// How a button is pressed.
nonisolated enum ButtonTrigger: String, CaseIterable, Sendable, Codable {
    case click
    case doubleClick

    var title: LocalizedStringResource {
        switch self {
        case .click: "Click"
        case .doubleClick: "Double Click"
        }
    }
}

/// One row in the button list: "Button 4 · Click → Mission Control".
nonisolated struct ButtonBinding: Identifiable, Equatable, Sendable, Codable {
    var id = UUID()
    /// Raw button number: 2 is the middle button, 3 and 4 the usual side buttons.
    var button: Int64
    var trigger: ButtonTrigger
    var action: MouseButtonAction
    /// Used when `action` is `.keyboardShortcut`.
    var shortcut: ShortcutBinding?

    /// Left and right buttons are never remapped.
    static func isAssignable(_ button: Int64) -> Bool { button >= 2 }
}

extension MouseButtonAction: Codable {}
