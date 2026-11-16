import Carbon.HIToolbox

/// Глобальное сочетание клавиш (работает, даже когда активно другое приложение).
/// Используем Carbon `RegisterEventHotKey`: он разрешён в песочнице
/// и не требует доступа к «Универсальному доступу».
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let identifier: UInt32

    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static var isHandlerInstalled = false

    /// - Parameters:
    ///   - keyCode: виртуальный код клавиши, например `kVK_ANSI_V`.
    ///   - modifiers: Carbon-модификаторы, например `cmdKey | shiftKey`.
    /// Возвращает `nil`, если сочетание уже занято другим приложением.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x434D_4450), id: identifier) // 'CMDP'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        hotKeyRef = ref
        Self.actions[identifier] = action
    }

    /// Обязательно вызывать при выключении модуля.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        Self.actions[identifier] = nil
    }

    fileprivate static func handle(_ id: UInt32) {
        actions[id]?()
    }

    private static func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        isHandlerInstalled = true
    }
}

/// C-функция, которую вызывает система при нажатии сочетания.
/// Она приходит на главном потоке, поэтому безопасно переходим в MainActor.
nonisolated private func hotKeyEventHandler(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        GlobalHotKey.handle(id)
    }
    return noErr
}
