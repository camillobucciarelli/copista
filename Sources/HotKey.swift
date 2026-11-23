import Carbon.HIToolbox

/// Scorciatoia globale con l'API Carbon. Non richiede permessi speciali.
/// Un solo gestore di eventi, installato una volta; `register` sostituisce il tasto precedente.
final class HotKey {
    private static var action: (() -> Void)?
    private static var handlerInstalled = false
    private var hotKeyRef: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        HotKey.action = action
        guard !HotKey.handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        HotKey.handlerInstalled = true
    }

    /// Registra la combinazione al posto di quella attuale. Restituisce false se macOS la
    /// rifiuta (in uso nel sistema o in un'altra app): in quel caso nessun tasto e' attivo.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        var mods: UInt32 = 0
        if shortcut.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        if shortcut.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5053), id: 1) // "CLPS"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), mods, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
