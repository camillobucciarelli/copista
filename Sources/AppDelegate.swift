import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private let shortcuts = ShortcutSettings()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var panel = HistoryPanelController(store: store, shortcuts: shortcuts)
    private lazy var settings = SettingsWindowController(
        shortcuts: shortcuts,
        registerGlobal: { [weak self] in self?.registerGlobal($0) ?? false },
        isReceptionOn: { [weak self] in self?.reception.isRunning ?? false },
        toggleReception: { [weak self] in self?.toggleReception() })
    private var statusItem: NSStatusItem!
    private lazy var hotKey = HotKey { [weak self] in self?.panel.toggle() }
    private let reception = AndroidReception()
    private let receptionEnabledKey = "androidReceptionEnabled"
    private let receptionExplainedKey = "androidReceptionExplained"
    private let autoPasteKey = "autoPasteOnSelection"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        // Icona nella barra dei menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: L("history.title"))
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Pannello
        panel.onCopy = { [weak self] items in self?.copy(items) }
        panel.onDelete = { [weak self] items in self?.delete(items) ?? false }
        panel.onSave = { [weak self] item, text, etichetta in self?.save(item, text, etichetta) ?? false }
        store.onChange = { [weak self] in self?.panel.reloadIfVisible() }

        // Controllo degli appunti
        monitor.start()

        // Ricezione da Android: il testo diventa l'ultimo copiato.
        reception.onText = { [weak self] text in
            self?.monitor.write(text)
            self?.store.add(text)
        }
        if UserDefaults.standard.bool(forKey: receptionEnabledKey), !reception.start() {
            UserDefaults.standard.set(false, forKey: receptionEnabledKey)
        }

        // Scorciatoia globale (predefinita ⌘⇧V)
        settings.globalFailed = !registerGlobal(shortcuts.shortcut(for: .openHistory))
    }

    private func registerGlobal(_ shortcut: Shortcut?) -> Bool {
        guard let shortcut else { hotKey.unregister(); return true }
        return hotKey.register(shortcut)
    }

    // MARK: - Azioni sugli elementi

    /// Gli elementi sono nell'ordine della lista.
    private func copy(_ items: [ClipItem]) {
        guard let first = items.first else { return }
        panel.hide()
        if items.count == 1 {
            monitor.write(first.text)     // l'elemento diventa "l'ultimo copiato"
        } else {
            // Incolla multiplo: un solo testo, che non entra nello storico.
            let joined = items.map(\.text).joined(separator: "\n")
            monitor.write(joined, record: false)
        }
        // Il pannello non attiva Copista: l'app di prima resta in primo piano.
        // Opzione attiva e permesso concesso: Cmd+V sintetico. Altrimenti lo
        // preme l'utente.
        guard UserDefaults.standard.bool(forKey: autoPasteKey), CGPreflightPostEventAccess() else { return }
        // ponytail: ritardo fisso, aspetta che l'app di prima torni attiva
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let key = CGKeyCode(kVK_ANSI_V)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Menu principale minimo (invisibile in un'app agente): serve solo a instradare
    /// Cmd+Z/X/C/V/A al campo di testo attivo tramite la responder chain.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Il foglio di modifica non scrive negli appunti, salvo che l'elemento fosse l'ultimo copiato.
    private func save(_ item: ClipItem, _ text: String, _ etichetta: String?) -> Bool {
        let wasOnClipboard = monitor.currentString() == item.text
        guard store.update(id: item.id, text: text, etichetta: etichetta) else { return false }
        if wasOnClipboard { monitor.write(text, record: false) }
        return true
    }

    /// Elimina solo i non fissati. Se non elimina nulla gli appunti restano com'erano
    /// (un Testo unito non viene sostituito senza un'eliminazione reale).
    private func delete(_ items: [ClipItem]) -> Bool {
        guard !store.remove(ids: Set(items.map(\.id))).isEmpty else { return false }
        syncClipboard()
        return true
    }

    /// Dopo una rimozione: gli appunti di sistema non devono contenere
    /// un elemento che non e' piu' nello storico.
    private func syncClipboard() {
        guard let current = monitor.currentString() else { return }
        if store.items.contains(where: { $0.text == current }) { return }
        if let first = store.items.first {
            monitor.write(first.text)
        } else {
            monitor.clear()
        }
    }

    // MARK: - Menu della barra

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = addItem(to: menu, L("menu.show"), #selector(showHistory))
        if let global = shortcuts.shortcut(for: .openHistory) {
            show.keyEquivalent = global.keyEquivalent
            var mask: NSEvent.ModifierFlags = []
            if global.modifiers.contains(.command) { mask.insert(.command) }
            if global.modifiers.contains(.shift) { mask.insert(.shift) }
            if global.modifiers.contains(.option) { mask.insert(.option) }
            if global.modifiers.contains(.control) { mask.insert(.control) }
            show.keyEquivalentModifierMask = mask
        }

        menu.addItem(.separator())

        let count = store.items.count
        let pinned = store.items.filter(\.fissato).count
        let info = NSMenuItem(title: String(format: L(count == 1 ? "menu.items.one" : "menu.items.other"), count) + " · "
                                + String(format: L(pinned == 1 ? "menu.pinned.one" : "menu.pinned.other"), pinned),
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        let pause = addItem(to: menu, L("menu.pause"), #selector(togglePause))
        pause.state = monitor.isPaused ? .on : .off

        let clean = NSMenu()
        addItem(to: clean, L("menu.clearAll"), #selector(clearAll))
        addItem(to: clean, L("menu.keepLastTen"), #selector(keepLastTen))
        addItem(to: clean, L("menu.removeOlderHour"), #selector(removeOlderThanHour))
        addItem(to: clean, L("menu.removeOlderDay"), #selector(removeOlderThanDay))
        let cleanItem = NSMenuItem(title: L("menu.clean"), action: nil, keyEquivalent: "")
        cleanItem.submenu = clean
        menu.addItem(cleanItem)

        menu.addItem(.separator())
        addItem(to: menu, L("menu.settings"), #selector(showSettings)).keyEquivalent = ","
        addItem(to: menu, L("menu.quit"), #selector(quit)).keyEquivalent = "q"
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func showHistory() { panel.show() }

    @objc private func showSettings() { settings.show() }

    @objc private func clearAll() {
        if store.clear() > 0 { syncClipboard() }
    }

    @objc private func keepLastTen() {
        if store.keepLatest(10) > 0 { syncClipboard() }
    }

    @objc private func removeOlderThanHour() {
        if store.removeOlder(than: 3600) > 0 { syncClipboard() }
    }

    @objc private func removeOlderThanDay() {
        if store.removeOlder(than: 86400) > 0 { syncClipboard() }
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        reception.isPaused = monitor.isPaused
    }

    private func toggleReception() {
        let defaults = UserDefaults.standard
        if reception.isRunning {
            reception.stop()
            defaults.set(false, forKey: receptionEnabledKey)
            return
        }

        if !defaults.bool(forKey: receptionExplainedKey) {
            let alert = NSAlert()
            alert.messageText = L("menu.android")
            alert.informativeText = L("android.alert.body")
            alert.addButton(withTitle: L("button.enable"))
            alert.addButton(withTitle: L("button.cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            defaults.set(true, forKey: receptionExplainedKey)
        }

        if reception.start() {
            defaults.set(true, forKey: receptionEnabledKey)
        } else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("downloads.alert.title")
            alert.informativeText = L("downloads.alert.body")
            alert.addButton(withTitle: L("button.openSettings"))
            alert.addButton(withTitle: L("button.cancel"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
