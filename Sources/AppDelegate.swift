import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var panel = HistoryPanelController(store: store)
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
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
        panel.onDelete = { [weak self] items in self?.delete(items) }
        panel.onEdit = { [weak self] item in self?.edit(item) }
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

        // Cmd+Shift+V globale
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.panel.toggle()
        }
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

    /// Editor di testo semplice. Non scrive negli appunti: salva solo nello storico.
    private func edit(_ item: ClipItem) {
        // Il pannello non e' attivante: l'app in primo piano e' ancora quella di prima.
        let previousApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0
        }
        panel.hide()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.string = item.text
        let scroll = NSScrollView(frame: textView.frame)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = L("panel.edit")
        alert.accessoryView = scroll
        alert.addButton(withTitle: L("button.save"))
        alert.addButton(withTitle: L("button.cancel"))
        alert.window.initialFirstResponder = textView

        let saveButton = alert.buttons[0]
        let observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { _ in
            saveButton.isEnabled = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        previousApp?.activate()
        guard response == .alertFirstButtonReturn else { return }
        let wasOnClipboard = monitor.currentString() == item.text
        store.update(id: item.id, text: textView.string)
        if wasOnClipboard { monitor.write(textView.string, record: false) }
    }

    private func delete(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        store.remove(ids: Set(items.map(\.id)))
        syncClipboard()
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
        show.keyEquivalent = "v"
        show.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        let count = store.items.count
        let info = NSMenuItem(title: count == 1 ? L("menu.count.one") : String(format: L("menu.count.other"), count),
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        addItem(to: menu, L("menu.clearAll"), #selector(clearAll))
        addItem(to: menu, L("menu.keepLastTen"), #selector(keepLastTen))
        addItem(to: menu, L("menu.removeOlderHour"), #selector(removeOlderThanHour))
        addItem(to: menu, L("menu.removeOlderDay"), #selector(removeOlderThanDay))

        menu.addItem(.separator())

        let pause = addItem(to: menu, L("menu.pause"), #selector(togglePause))
        pause.state = monitor.isPaused ? .on : .off

        let android = addItem(to: menu, L("menu.android"), #selector(toggleReception))
        android.state = reception.isRunning ? .on : .off

        let autoPaste = addItem(to: menu, L("menu.autoPaste"), #selector(toggleAutoPaste))
        autoPaste.state = UserDefaults.standard.bool(forKey: autoPasteKey) ? .on : .off
        autoPaste.toolTip = L("menu.autoPaste.tooltip")

        menu.addItem(.separator())
        addItem(to: menu, L("menu.quit"), #selector(quit))
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func showHistory() { panel.show() }

    @objc private func clearAll() {
        store.clear()
        syncClipboard()
    }

    @objc private func keepLastTen() {
        store.keepLatest(10)
        syncClipboard()
    }

    @objc private func removeOlderThanHour() {
        store.removeOlder(than: 3600)
        syncClipboard()
    }

    @objc private func removeOlderThanDay() {
        store.removeOlder(than: 86400)
        syncClipboard()
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        reception.isPaused = monitor.isPaused
    }

    @objc private func toggleAutoPaste() {
        let defaults = UserDefaults.standard
        let on = !defaults.bool(forKey: autoPasteKey)
        defaults.set(on, forKey: autoPasteKey)
        // Senza permesso resta attivo ma la selezione si limita a copiare.
        if on, !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
    }

    @objc private func toggleReception() {
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
