import AppKit
import Carbon.HIToolbox

/// Вставка «за пользователя»: нажимает ⌘V в приложении, которое сейчас активно.
///
/// Окно истории не делает CmdPlus активным, поэтому после его закрытия
/// фокус остаётся там, где вы работали, — туда и уходит ⌘V.
///
/// Нужно разрешение «Универсальный доступ». Запрашиваем его только
/// по кнопке пользователя, с объяснением (см. настройки модуля).
enum PasteSimulator {
    /// Есть ли разрешение отправлять нажатия клавиш. Системное окно не показывает.
    static var hasAccess: Bool {
        CGPreflightPostEventAccess()
    }

    /// Показывает системный запрос. Если пользователь уже отказывал и запрос
    /// больше не появляется — открывает нужный раздел Системных настроек.
    static func requestAccess() {
        guard !CGRequestPostEventAccess() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Нажимает ⌘V. Возвращает `false`, если разрешения нет.
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
