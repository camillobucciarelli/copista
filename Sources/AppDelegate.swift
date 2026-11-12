import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var panel = HistoryPanelController(store: store)
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Icona nella barra dei menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "Storico appunti")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Pannello
        panel.onPaste = { [weak self] item in self?.paste(item) }
        panel.onDelete = { [weak self] item in self?.delete(item) }
        store.onChange = { [weak self] in self?.panel.reloadIfVisible() }

        // Controllo degli appunti
        monitor.start()

        // Cmd+Shift+V globale
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.panel.toggle()
        }

        // Serve per inviare Cmd+V all'app in primo piano.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Azioni sugli elementi

    private func paste(_ item: ClipItem) {
        panel.hide()
        monitor.write(item.text)          // l'elemento diventa "l'ultimo copiato"
        guard AXIsProcessTrusted() else { return }   // senza permesso: usare Cmd+V a mano
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.sendCommandV()
        }
    }

    private func delete(_ item: ClipItem) {
        store.remove(id: item.id)
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

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    // MARK: - Menu della barra

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = addItem(to: menu, "Mostra storico", #selector(showHistory))
        show.keyEquivalent = "v"
        show.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        let count = store.items.count
        let info = NSMenuItem(title: count == 1 ? "1 elemento nello storico" : "\(count) elementi nello storico",
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        addItem(to: menu, "Svuota tutto lo storico", #selector(clearAll))
        addItem(to: menu, "Mantieni solo gli ultimi 10", #selector(keepLastTen))
        addItem(to: menu, "Elimina elementi più vecchi di 1 ora", #selector(removeOlderThanHour))
        addItem(to: menu, "Elimina elementi più vecchi di 24 ore", #selector(removeOlderThanDay))

        menu.addItem(.separator())

        let pause = addItem(to: menu, "Sospendi registrazione", #selector(togglePause))
        pause.state = monitor.isPaused ? .on : .off

        if !AXIsProcessTrusted() {
            addItem(to: menu, "Abilita incolla automatico (Accessibilità)…", #selector(openAccessibility))
        }

        menu.addItem(.separator())
        addItem(to: menu, "Esci", #selector(quit))
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

    @objc private func togglePause() { monitor.isPaused.toggle() }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
