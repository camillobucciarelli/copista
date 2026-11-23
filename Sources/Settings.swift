import AppKit

/// Campo che registra una scorciatoia: clic per registrare, clic fuori per annullare.
/// Esc e' registrabile come qualsiasi altro tasto.
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut? { didSet { refresh() } }
    var onRecord: ((Shortcut) -> Void)?
    private var isRecording = false { didSet { refresh() } }
    private var clickMonitor: Any?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override var acceptsFirstResponder: Bool { true }

    private func refresh() {
        title = isRecording ? L("settings.recording") : (shortcut?.display ?? L("settings.none"))
        highlight(isRecording)
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.stopRecording()
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags
        var mods: Shortcut.Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        guard let shortcut = Shortcut.make(keyCode: event.keyCode, modifiers: mods,
                                           characters: event.charactersIgnoringModifiers) else {
            NSSound.beep()
            return
        }
        stopRecording()
        onRecord?(shortcut)
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }
}

/// Finestra Impostazioni: Generali e Scorciatoie.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let shortcuts: ShortcutSettings
    /// Registra la globale (nil = nessuna). Restituisce false se macOS la rifiuta.
    private let registerGlobal: (Shortcut?) -> Bool
    private let isReceptionOn: () -> Bool
    private let toggleReception: () -> Void
    private var window: NSWindow?

    private let autoPaste = NSButton(checkboxWithTitle: L("settings.autoPaste"), target: nil, action: nil)
    private let permission = NSTextField(labelWithString: "")
    private let reception = NSButton(checkboxWithTitle: L("settings.android"), target: nil, action: nil)
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private var reasons: [ShortcutAction: NSTextField] = [:]
    /// Motivo mostrato all'avvio se la globale non si e' registrata.
    var globalFailed = false

    init(shortcuts: ShortcutSettings, registerGlobal: @escaping (Shortcut?) -> Bool,
         isReceptionOn: @escaping () -> Bool, toggleReception: @escaping () -> Void) {
        self.shortcuts = shortcuts
        self.registerGlobal = registerGlobal
        self.isReceptionOn = isReceptionOn
        self.toggleReception = toggleReception
        super.init()
    }

    func show() {
        if window == nil { build() }
        refreshGeneral()
        refreshShortcuts()
        if globalFailed { reasons[.openHistory]?.stringValue = L("settings.globalUnavailable") }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshGeneral() }

    private func build() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let general = NSTabViewItem(viewController: viewController(generalView()))
        general.label = L("settings.general")
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        let keys = NSTabViewItem(viewController: viewController(shortcutsView()))
        keys.label = L("settings.shortcuts")
        keys.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        tabs.addTabViewItem(general)
        tabs.addTabViewItem(keys)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
    }

    private func viewController(_ view: NSView) -> NSViewController {
        let controller = NSViewController()
        controller.view = view
        controller.preferredContentSize = view.fittingSize   // ogni scheda alta quanto serve
        return controller
    }

    private func padded(_ content: NSView) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 520
        return field
    }

    // MARK: - Generali

    private func generalView() -> NSView {
        autoPaste.target = self
        autoPaste.action = #selector(autoPasteChanged)
        reception.target = self
        reception.action = #selector(receptionChanged)
        permission.font = .systemFont(ofSize: 11)
        let openSettings = NSButton(title: L("settings.openSystemSettings"), target: self, action: #selector(openAccessibility))
        openSettings.controlSize = .small
        let permissionRow = NSStackView(views: [permission, openSettings])
        permissionRow.spacing = 8

        let stack = NSStackView(views: [
            autoPaste, note(L("menu.autoPaste.tooltip")), permissionRow,
            reception, note(L("settings.android.note")),
            NSTextField(labelWithString: L("settings.retained")),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(18, after: permissionRow)
        stack.setCustomSpacing(18, after: stack.views[4])
        stack.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return padded(stack)
    }

    private func refreshGeneral() {
        autoPaste.state = UserDefaults.standard.bool(forKey: "autoPasteOnSelection") ? .on : .off
        let granted = CGPreflightPostEventAccess()
        permission.stringValue = L(granted ? "settings.permission.granted" : "settings.permission.missing")
        permission.textColor = granted ? .secondaryLabelColor : .systemOrange
        reception.state = isReceptionOn() ? .on : .off
    }

    @objc private func autoPasteChanged() {
        let on = autoPaste.state == .on
        UserDefaults.standard.set(on, forKey: "autoPasteOnSelection")
        // Senza permesso resta attivo ma la selezione si limita a copiare.
        if on, !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        refreshGeneral()
    }

    @objc private func receptionChanged() {
        toggleReception()
        refreshGeneral()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Scorciatoie

    private func shortcutsView() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        var headers: [Int] = []
        let sections: [(String, [ShortcutAction])] = [
            (L("settings.scope.global"), [.openHistory]),
            (L("settings.scope.panel"), [.copy, .edit, .togglePin, .delete, .actionMenu, .closePanel]),
            (L("settings.scope.sheet"), [.save, .cancelEdit]),
        ]
        for (title, actions) in sections {
            let header = NSTextField(labelWithString: title)
            header.font = .systemFont(ofSize: 13, weight: .semibold)
            let row = grid.addRow(with: [header])
            row.topPadding = grid.numberOfRows > 1 ? 10 : 0
            headers.append(grid.numberOfRows - 1)
            for action in actions {
                let recorder = ShortcutRecorder()
                recorder.onRecord = { [weak self] in self?.apply($0, to: action) }
                recorder.setAccessibilityLabel(action.title)
                recorders[action] = recorder
                let clear = smallButton("xmark.circle.fill", L("settings.clear"), action, #selector(clearShortcut))
                let reset = smallButton("arrow.counterclockwise", L("settings.reset"), action, #selector(resetShortcut))
                let reason = NSTextField(wrappingLabelWithString: "")
                reason.font = .systemFont(ofSize: 11)
                reason.textColor = .systemRed
                reason.preferredMaxLayoutWidth = 220
                reasons[action] = reason
                grid.addRow(with: [NSTextField(labelWithString: action.title), recorder, clear, reset, reason])
            }
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 4).width = 220   // motivo del rifiuto, accanto al campo
        for index in headers {   // le intestazioni occupano tutta la riga, allineate a sinistra
            let row = grid.row(at: index)
            row.mergeCells(in: NSRange(location: 0, length: grid.numberOfColumns))
            row.cell(at: 0).xPlacement = .leading
        }
        grid.rowAlignment = .firstBaseline
        let resetAll = NSButton(title: L("settings.resetAll"), target: self, action: #selector(resetAll))
        let stack = NSStackView(views: [grid, resetAll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        return padded(stack)
    }

    private func smallButton(_ symbol: String, _ label: String, _ action: ShortcutAction, _ selector: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                              target: self, action: selector)
        button.isBordered = false
        button.toolTip = label
        button.setAccessibilityLabel("\(label): \(action.title)")
        button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        return button
    }

    private func action(of sender: NSButton) -> ShortcutAction? {
        sender.identifier.flatMap { ShortcutAction(rawValue: $0.rawValue) }
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        if let action = action(of: sender) { apply(nil, to: action) }
    }

    @objc private func resetShortcut(_ sender: NSButton) {
        if let action = action(of: sender) { apply(ShortcutAction.defaults[action] ?? nil, to: action) }
    }

    @objc private func resetAll() {
        // Prima la globale: passa alla predefinita solo se macOS la accetta, altrimenti resta
        // quella che funziona. Poi le azioni locali, senza scontrarsi con la globale rimasta.
        let current = shortcuts.current
        let previous = shortcuts.shortcut(for: .openHistory)
        let failed = !registerGlobal(ShortcutAction.defaults[.openHistory] ?? nil)
        if failed {
            _ = registerGlobal(previous)
        } else {
            shortcuts.reset(.openHistory)
            globalFailed = false
        }
        let plan = restoredDefaults(keepingGlobal: shortcuts.shortcut(for: .openHistory), current: current)
        for action in ShortcutAction.allCases where action != .openHistory && !plan.unchanged.contains(action) {
            shortcuts.reset(action)
        }
        refreshShortcuts()
        if failed {
            NSSound.beep()
            reasons[.openHistory]?.stringValue = L("settings.globalUnavailable")
        }
        for action in plan.unchanged {   // perche' non e' tornata predefinita
            reasons[action]?.stringValue = validate(ShortcutAction.defaults[action] ?? nil, for: action,
                                                    in: plan.shortcuts)?.message ?? ""
        }
    }

    /// Valida e salva; una combinazione rifiutata non viene salvata e il motivo compare accanto.
    private func apply(_ shortcut: Shortcut?, to action: ShortcutAction) {
        let reason = reasons[action]
        if let rejection = validate(shortcut, for: action, in: shortcuts.current) {
            NSSound.beep()
            reason?.stringValue = rejection.message
            return
        }
        if action == .openHistory {
            let previous = shortcuts.shortcut(for: .openHistory)
            guard registerGlobal(shortcut) else {
                _ = registerGlobal(previous)   // torna la combinazione precedente
                NSSound.beep()
                reason?.stringValue = L("settings.globalUnavailable")
                return
            }
            globalFailed = false
        }
        shortcuts.set(shortcut, for: action)
        reason?.stringValue = ""
        recorders[action]?.shortcut = shortcut
    }

    private func refreshShortcuts() {
        for (action, recorder) in recorders {
            recorder.shortcut = shortcuts.shortcut(for: action)
            reasons[action]?.stringValue = ""
        }
    }
}
