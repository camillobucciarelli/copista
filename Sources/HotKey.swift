import Carbon.HIToolbox

/// Scorciatoia globale con l'API Carbon. Non richiede permessi speciali.
final class HotKey {
    private static var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5053), id: 1) // "CLPS"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    var isRegistered: Bool { hotKeyRef != nil }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
