import AppKit

/// Pannello che puo' ricevere i tasti senza attivare l'app.
/// Cosi' l'app in primo piano resta la stessa e riceve poi il Cmd+V.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func iconButton(_ symbol: String, _ tooltip: String, _ target: AnyObject, _ action: Selector) -> NSButton {
    let button = NSButton()
    button.title = ""
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
    button.imagePosition = .imageOnly
    button.isBordered = false
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = tooltip
    button.target = target
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 22).isActive = true
    button.heightAnchor.constraint(equalToConstant: 22).isActive = true
    return button
}

final class ClipCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    // PROTOTYPE: elementi per etichetta e fissato
    let titleLabel = NSTextField(labelWithString: "")
    let badge = NSTextField(labelWithString: "")
    let pinIcon = NSImageView()
    var pinButton: NSButton!
    var deleteButton: NSButton!
    var editButton: NSButton!
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onPin: (() -> Void)?
    private var row: NSStackView!

    /// PROTOTYPE: variante D vuole [modifica] [fissa] [cestino].
    func setEditFirst(_ editFirst: Bool) {
        row.removeArrangedSubview(editButton)
        let index = row.arrangedSubviews.firstIndex(of: pinButton)! + (editFirst ? 0 : 1)
        row.insertArrangedSubview(editButton, at: index)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for field in [label, titleLabel] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.masksToBounds = true
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Fissato")
        pinIcon.contentTintColor = .systemOrange
        pinIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        pinButton = iconButton("pin", "Fissa", self, #selector(pinClicked))
        editButton = iconButton("pencil", L("panel.edit.tooltip"), self, #selector(editClicked))
        deleteButton = iconButton("trash", L("panel.delete.tooltip"), self, #selector(deleteClicked))

        let texts = NSStackView(views: [titleLabel, label])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row = NSStackView(views: [pinIcon, badge, texts, pinButton, editButton, deleteButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        textField = label

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    @objc private func deleteClicked() { onDelete?() }
    @objc private func editClicked() { onEdit?() }
    @objc private func pinClicked() { onPin?() }
}

// PROTOTYPE: riga di intestazione ("Fissati" / "Recenti") della variante A
final class HeaderCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6).isActive = true
        label.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }
}

// PROTOTYPE: una riga della tabella e' un'intestazione o un elemento.
enum PanelRow {
    case header(String)
    case item(ClipItem)
}

final class HistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store: HistoryStore
    private let panel: KeyPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: L("panel.empty"))
    private let hint = NSTextField(labelWithString: "")
    private var keyMonitor: Any?

    // PROTOTYPE
    private(set) var variant: PrototypeVariant? = PrototypeVariant.atLaunch
    private var rows: [PanelRow] = []
    private var tab = 0   // variante C: 0 Recenti, 1 Fissati
    private let tabs = NSSegmentedControl(labels: ["Recenti", "Fissati"], trackingMode: .selectOne, target: nil, action: nil)
    private let protoBox = NSView()
    private let protoTitle = NSTextField(labelWithString: "")
    private let protoState = NSTextField(labelWithString: "")
    private var protoNote = ""
    private let contextMenu = NSMenu()
    // PROTOTYPE variante D: icona modifica ciclabile e modifica dentro il pannello
    private var editSymbolIndex = 0
    private var editSymbol: String { PrototypeVariant.editSymbols.isEmpty ? "pencil" : PrototypeVariant.editSymbols[editSymbolIndex] }
    private let editSymbolButton = NSButton()
    private let protoKeys = NSTextField(labelWithString: "")
    private let titleField = NSTextField(labelWithString: L("history.title"))
    private let editorView = NSView()
    private let editorLabel = NSTextField(string: "")
    private let editorText = NSTextView()
    private var editingID: UUID?

    var onCopy: (([ClipItem]) -> Void)?
    var onDelete: (([ClipItem]) -> Void)?
    var onEdit: ((ClipItem) -> Void)?
    var onTogglePin: (([ClipItem]) -> Void)?   // PROTOTYPE

    var isVisible: Bool { panel.isVisible }

    init(store: HistoryStore) {
        self.store = store
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: PrototypeVariant.atLaunch == nil ? 400 : 470),
                         styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        buildUI()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    // MARK: - UI

    private func buildUI() {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        panel.contentView = background

        let title = titleField
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // PROTOTYPE: schede della variante C
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.controlSize = .small

        // PROTOTYPE: barra in fondo
        contextMenu.delegate = self
        protoBox.wantsLayer = true
        protoBox.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.22).cgColor
        protoTitle.font = .systemFont(ofSize: 11, weight: .bold)
        protoState.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        protoState.textColor = .secondaryLabelColor
        protoState.lineBreakMode = .byTruncatingTail
        protoState.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let prev = NSButton(title: "◀", target: self, action: #selector(prevVariant))
        let next = NSButton(title: "▶", target: self, action: #selector(nextVariant))
        for b in [prev, next] { b.isBordered = false; b.font = .systemFont(ofSize: 11) }
        editSymbolButton.isBordered = false
        editSymbolButton.imagePosition = .imageOnly
        editSymbolButton.toolTip = "Cambia icona modifica (\\)"
        editSymbolButton.target = self
        editSymbolButton.action = #selector(nextEditSymbol)
        protoKeys.font = .systemFont(ofSize: 10)
        protoKeys.textColor = .secondaryLabelColor
        protoKeys.stringValue = "↩ copia  ⌘E modifica  ⌘P fissa/sfissa  ⌫ elimina (Recenti)  ⇥ scheda  esc chiudi  |  editor: ⌘↩ salva  esc annulla"
        let titleRow = NSStackView(views: [protoTitle, prev, next, editSymbolButton])
        titleRow.spacing = 4
        let protoStack = NSStackView(views: [titleRow, protoKeys, protoState])
        protoStack.orientation = .vertical
        protoStack.alignment = .leading
        protoStack.spacing = 2
        protoStack.translatesAutoresizingMaskIntoConstraints = false
        protoBox.addSubview(protoStack)
        NSLayoutConstraint.activate([
            protoStack.leadingAnchor.constraint(equalTo: protoBox.leadingAnchor, constant: 18),
            protoStack.trailingAnchor.constraint(lessThanOrEqualTo: protoBox.trailingAnchor, constant: -12),
            protoStack.topAnchor.constraint(equalTo: protoBox.topAnchor, constant: 5),
            protoStack.bottomAnchor.constraint(equalTo: protoBox.bottomAnchor, constant: -6),
        ])
        protoBox.isHidden = variant == nil

        buildEditor()
        for view in [title, tabs, scrollView, hint, emptyLabel, protoBox, editorView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }

        let hintBottom = variant == nil
            ? hint.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10)
            : hint.bottomAnchor.constraint(equalTo: protoBox.topAnchor, constant: -6)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),

            tabs.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            tabs.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),

            hint.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            hintBottom,

            protoBox.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            protoBox.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            protoBox.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            editorView.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            editorView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            editorView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            editorView.bottomAnchor.constraint(equalTo: protoBox.topAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        applyVariant()
    }

    // MARK: - PROTOTYPE: varianti

    private func applyVariant() {
        let tabbed = variant == .c || variant == .d
        tabs.isHidden = !tabbed
        tableView.menu = tabbed ? contextMenu : nil
        editSymbolButton.isHidden = variant != .d
        protoKeys.isHidden = variant != .d
        editSymbolButton.image = NSImage(systemSymbolName: editSymbol, accessibilityDescription: nil)
        if let v = variant {
            protoTitle.stringValue = "PROTOTIPO — variante \(v.rawValue.uppercased()) (\(v.name))   [ ]"
                + (v == .d ? "   matita: \(editSymbol)  \\" : "")
        }
    }

    @objc private func nextEditSymbol() {
        guard !PrototypeVariant.editSymbols.isEmpty else { NSSound.beep(); return }
        editSymbolIndex = (editSymbolIndex + 1) % PrototypeVariant.editSymbols.count
        applyVariant()
        reload(keeping: Set(selectedItems().map(\.id)), fallback: tableView.selectedRow)
    }

    // MARK: - PROTOTYPE: modifica dentro il pannello (variante D)

    private func buildEditor() {
        let heading = NSTextField(labelWithString: L("panel.edit"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        let labelCaption = NSTextField(labelWithString: "Etichetta")
        labelCaption.font = .systemFont(ofSize: 11)
        labelCaption.textColor = .secondaryLabelColor
        editorLabel.placeholderString = "facoltativa"
        let textCaption = NSTextField(labelWithString: "Testo")
        textCaption.font = labelCaption.font
        textCaption.textColor = .secondaryLabelColor

        editorText.isRichText = false
        editorText.allowsUndo = true
        editorText.font = .systemFont(ofSize: 13)
        editorText.drawsBackground = false
        editorText.isVerticallyResizable = true
        editorText.autoresizingMask = .width
        editorText.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = editorText
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder

        let cancel = NSButton(title: L("button.cancel"), target: self, action: #selector(cancelInlineEdit))
        let save = NSButton(title: L("button.save"), target: self, action: #selector(saveInlineEdit))
        save.bezelColor = .controlAccentColor
        let buttons = NSStackView(views: [NSView(), cancel, save])
        buttons.spacing = 8

        let stack = NSStackView(views: [heading, labelCaption, editorLabel, textCaption, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(12, after: editorLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        editorView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: editorView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: editorView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            editorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        editorView.isHidden = true
    }

    private func setEditing(_ on: Bool) {
        editorView.isHidden = !on
        for view in [titleField, scrollView, hint] as [NSView] { view.isHidden = on }
        tabs.isHidden = on || !(variant == .c || variant == .d)
        if on { emptyLabel.isHidden = true }
    }

    private func beginInlineEdit(_ item: ClipItem) {
        editingID = item.id
        editorLabel.stringValue = item.etichetta ?? ""
        editorText.string = item.text
        setEditing(true)
        panel.makeFirstResponder(editorText)
        editorText.setSelectedRange(NSRange(location: 0, length: 0))
    }

    @objc private func saveInlineEdit() {
        guard let id = editingID else { return }
        let text = editorText.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        let label = editorLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endInlineEdit()
        store.update(id: id, text: text)
        store.setEtichetta(id: id, label.isEmpty ? nil : label)
        reload(keeping: [id], fallback: 0)
        note("salvato")
    }

    @objc private func cancelInlineEdit() {
        endInlineEdit()
        reload(keeping: Set(selectedItems().map(\.id)), fallback: 0)
    }

    private func endInlineEdit() {
        editingID = nil
        setEditing(false)
        panel.makeFirstResponder(tableView)
    }

    /// In D "Modifica" apre l'editor nel pannello; altrove il dialogo dell'app.
    private func edit(_ item: ClipItem) {
        if variant == .d { beginInlineEdit(item) } else { onEdit?(item) }
    }

    var onEnterE: (() -> Void)?   // PROTOTYPE: la variante E vive in un altro pannello

    func showVariant(_ v: PrototypeVariant) {
        variant = v
        applyVariant()
        show()
    }

    private func setVariant(_ v: PrototypeVariant) {
        let keep = Set(selectedItems().map(\.id))
        if editingID != nil { endInlineEdit() }
        variant = v
        if v == .e { hide(); onEnterE?(); return }
        applyVariant()
        updateHint()
        reload(keeping: keep, fallback: 0)
    }

    @objc private func prevVariant() { if let v = variant { setVariant(v.shifted(by: -1)) } }
    @objc private func nextVariant() { if let v = variant { setVariant(v.shifted(by: 1)) } }

    @objc private func tabChanged() {
        tab = tabs.selectedSegment
        reload(keeping: [], fallback: 0)
    }

    /// Messaggio temporaneo nella riga di stato (es. copia finta).
    func note(_ text: String) {
        protoNote = text
        updateState()
    }

    private func updateHint() {
        switch variant {
        case nil:
            let autoPaste = UserDefaults.standard.bool(forKey: "autoPasteOnSelection") && CGPreflightPostEventAccess()
            hint.stringValue = L(autoPaste ? "panel.hint.autoPaste" : "panel.hint")
        case .a: hint.stringValue = "↑↓ scegli   ↩ copia   puntina: fissa/sfissa   ⌫ elimina (non i fissati)   esc"
        case .b: hint.stringValue = "↑↓ scegli   ↩ copia   ⌘P / puntina: fissa/sfissa   ⌫ elimina (non i fissati)   esc"
        case .e: break   // PROTOTYPE: E ha il suo pannello (PrototypeE.swift)
        case .d: hint.stringValue = "⇥ scheda   ↑↓ scegli   ↩ copia   ⌘E modifica   ⌘P fissa/sfissa   ⌫ elimina   esc"
        case .c: hint.stringValue = "⇥ scheda   ↑↓ scegli   ↩ copia   ⌘P / clic destro: fissa   ⌫ elimina   esc"
        }
    }

    private func updateState() {
        guard variant != nil else { return }
        let pinned = store.items.filter(\.fissato).count
        let selected = selectedItems()
        var text = "fissati \(pinned) · non fissati \(store.items.count - pinned) · selezione \(selected.count)"
        if selected.count == 1, let s = selected.first {
            text += " [\(s.fissato ? "fissato" : "non fissato")\(s.etichetta.map { ", “\($0)”" } ?? "")]"
        }
        if !protoNote.isEmpty { text += " · \(protoNote)" }
        protoState.stringValue = text
    }

    private func buildRows() {
        let items = store.items
        switch variant {
        case nil, .b?, .e?:
            rows = items.map { .item($0) }
        case .a?:
            let pinned = items.filter(\.fissato)
            let recent = items.filter { !$0.fissato }
            rows = (pinned.isEmpty ? [] : [.header("FISSATI")] + pinned.map { .item($0) })
                + [.header("RECENTI")] + recent.map { .item($0) }
        case .c?, .d?:
            rows = items.filter { $0.fissato == (tab == 1) }.map { .item($0) }
        }
    }

    private func togglePinSelected() {
        let items = selectedItems()
        guard !items.isEmpty else { NSSound.beep(); return }
        onTogglePin?(items)
    }

    // MARK: - Mostra / nascondi

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        if editingID != nil { endInlineEdit() }   // PROTOTYPE
        updateHint()
        reload(keeping: [], fallback: 0)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let size = panel.frame.size
            let origin = NSPoint(x: area.midX - size.width / 2,
                                 y: area.midY - size.height / 2 + area.height * 0.08)
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(tableView)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func reloadIfVisible() {
        guard panel.isVisible else { return }
        reload(keeping: Set(selectedItems().map(\.id)), fallback: tableView.selectedRowIndexes.first ?? 0)
    }

    /// Riseleziona gli elementi `keep` (seguono il loro posto); altrimenti la riga piu' vicina a `fallback`.
    private func reload(keeping keep: Set<UUID>, fallback row: Int) {
        buildRows()
        tableView.reloadData()
        let itemRows = rows.indices.filter { item(at: $0) != nil }
        emptyLabel.isHidden = !itemRows.isEmpty
        defer { updateState() }
        guard let firstItemRow = itemRows.first else { return }
        var selection = IndexSet(itemRows.filter { keep.contains(item(at: $0)!.id) })
        if selection.isEmpty {
            selection = [itemRows.first { $0 >= row } ?? itemRows.last ?? firstItemRow]
        }
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        tableView.scrollRowToVisible(selection.first!)
    }

    func windowDidResignKey(_ notification: Notification) {
        if variant != nil { return }   // PROTOTYPE: resta aperto
        hide()   // clic fuori dal pannello
    }

    // MARK: - Tastiera

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.window === panel else { return event }
        // PROTOTYPE: editor nel pannello. ⌘↩ salva, esc annulla, il resto va ai campi.
        if editingID != nil {
            if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) { saveInlineEdit(); return nil }
            if event.keyCode == 53 { cancelInlineEdit(); return nil }
            return event
        }
        // ⇧+frecce: la tabella estende la selezione.
        if [125, 126].contains(event.keyCode), event.modifierFlags.contains(.shift) { return event }
        // PROTOTYPE: [ ] cambiano variante, ⌘P fissa, ⇥ cambia scheda
        if let v = variant {
            let chars = event.charactersIgnoringModifiers ?? ""
            if chars == "[" || event.keyCode == 33 { setVariant(v.shifted(by: -1)); return nil }
            if chars == "]" || event.keyCode == 30 { setVariant(v.shifted(by: 1)); return nil }
            if event.keyCode == 35, event.modifierFlags.contains(.command), v != .a { togglePinSelected(); return nil }
            if v == .d, chars == "\\" || event.keyCode == 42 { nextEditSymbol(); return nil }
            if v == .d, event.keyCode == 14, event.modifierFlags.contains(.command) {
                if let first = selectedItems().first { beginInlineEdit(first) } else { NSSound.beep() }
                return nil
            }
            if v == .d, [51, 117].contains(event.keyCode), tab == 1 { NSSound.beep(); return nil }
            if event.keyCode == 48, v == .c || v == .d {
                tabs.selectedSegment = 1 - tabs.selectedSegment
                tabChanged()
                return nil
            }
        }
        switch event.keyCode {
        case 125: moveSelection(by: 1); return nil      // freccia giu'
        case 126: moveSelection(by: -1); return nil     // freccia su
        case 36, 76: copySelected(); return nil        // invio
        case 53: hide(); return nil                     // esc
        case 51, 117: deleteSelected(); return nil      // backspace / canc
        default: return event
        }
    }

    private func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        var row = tableView.selectedRow
        repeat {   // PROTOTYPE: salta le intestazioni
            let nextRow = row + delta
            guard nextRow >= 0, nextRow < rows.count else { return }
            row = nextRow
        } while item(at: row) == nil
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func item(at row: Int) -> ClipItem? {
        guard row >= 0, row < rows.count, case .item(let item) = rows[row] else { return nil }
        return item
    }

    /// Elementi selezionati, nell'ordine della lista.
    private func selectedItems() -> [ClipItem] {
        tableView.selectedRowIndexes.compactMap { item(at: $0) }
    }

    private func copySelected() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        onCopy?(items)
    }

    private func deleteSelected() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        onDelete?(items)
    }

    @objc private func rowClicked() {
        // ⌘-clic e ⇧-clic cambiano solo la selezione. Invio copia.
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        guard modifiers.isDisjoint(with: [.command, .shift]) else { return }
        guard let item = item(at: tableView.clickedRow) else { return }
        onCopy?([item])
    }

    // MARK: - PROTOTYPE: menu contestuale (variante C)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let item = item(at: tableView.clickedRow) else { return }
        let entries: [(String, Selector)] = [
            (item.fissato ? "Sfissa" : "Fissa", #selector(menuPin)),
            (L("panel.edit"), #selector(menuEdit)),
            (L("panel.delete"), #selector(menuDelete)),
        ]
        for (title, action) in entries {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id
            menu.addItem(menuItem)
        }
    }

    private func menuTarget(_ sender: NSMenuItem) -> ClipItem? {
        store.items.first { $0.id == sender.representedObject as? UUID }
    }
    @objc private func menuPin(_ sender: NSMenuItem) { if let i = menuTarget(sender) { onTogglePin?([i]) } }
    @objc private func menuEdit(_ sender: NSMenuItem) { if let i = menuTarget(sender) { edit(i) } }
    @objc private func menuDelete(_ sender: NSMenuItem) { if let i = menuTarget(sender) { onDelete?([i]) } }

    // MARK: - Tabella

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateState()   // PROTOTYPE
    }

    // PROTOTYPE: le intestazioni non si selezionano
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.filteredIndexSet { item(at: $0) != nil }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        item(at: row) == nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = item(at: row) else { return 24 }
        return variant == .a && item.etichetta != nil ? 42 : 32
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = item(at: row) else {
            let header = HeaderCellView(frame: .zero)
            if case .header(let text) = rows[row] { header.label.stringValue = text }
            return header
        }
        let identifier = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ClipCellView) ?? {
            let view = ClipCellView(frame: .zero)
            view.identifier = identifier
            return view
        }()

        let preview = Self.preview(of: item.text)
        cell.label.stringValue = preview
        cell.label.font = .systemFont(ofSize: 13)
        cell.label.textColor = .labelColor
        cell.titleLabel.isHidden = true
        cell.badge.isHidden = true
        cell.pinIcon.isHidden = true
        cell.pinButton.isHidden = true
        cell.deleteButton.isHidden = false
        cell.deleteButton.isEnabled = true
        cell.setEditFirst(variant == .d)
        cell.editButton.image = NSImage(systemSymbolName: variant == .d ? editSymbol : "pencil",
                                        accessibilityDescription: L("panel.edit"))
        cell.toolTip = String(item.text.prefix(600))

        // PROTOTYPE: resa per variante
        let label = item.etichetta
        switch variant {
        case nil, .e?: break
        case .a?:
            if let label {
                cell.titleLabel.isHidden = false
                cell.titleLabel.stringValue = label
                cell.label.font = .systemFont(ofSize: 11)
                cell.label.textColor = .secondaryLabelColor
            }
            cell.pinButton.isHidden = false
            cell.deleteButton.isHidden = item.fissato
        case .b?:
            cell.pinIcon.isHidden = !item.fissato
            if let label {
                cell.badge.isHidden = false
                cell.badge.stringValue = " \(label) "
            }
            cell.pinButton.isHidden = false
            cell.deleteButton.isEnabled = !item.fissato
        case .d?: break   // PROTOTYPE: sotto, dopo i pulsanti
        case .c?:
            if let label {
                cell.label.stringValue = label
                cell.label.font = .systemFont(ofSize: 13, weight: .medium)
            }
        }
        cell.pinButton.image = NSImage(systemSymbolName: item.fissato ? "pin.fill" : "pin",
                                       accessibilityDescription: item.fissato ? "Sfissa" : "Fissa")
        cell.pinButton.contentTintColor = item.fissato ? .systemOrange : .secondaryLabelColor
        cell.pinButton.toolTip = item.fissato ? "Sfissa" : "Fissa"
        if variant == .d {   // PROTOTYPE: in Fissati il pulsante rimanda a Recenti
            if let label {
                cell.badge.isHidden = false
                cell.badge.stringValue = " \(label) "
            }
            cell.pinButton.isHidden = false
            cell.deleteButton.isHidden = item.fissato
            cell.pinButton.image = NSImage(systemSymbolName: item.fissato ? "pin.slash" : "pin",
                                           accessibilityDescription: item.fissato ? "Sfissa" : "Fissa")
            cell.pinButton.contentTintColor = .secondaryLabelColor
            cell.pinButton.toolTip = item.fissato ? "Sfissa: torna in Recenti" : "Fissa"
        }

        cell.onEdit = { [weak self] in self?.edit(item) }
        cell.onDelete = { [weak self] in self?.onDelete?([item]) }
        cell.onPin = { [weak self] in self?.onTogglePin?([item]) }
        return cell
    }

    /// Una sola riga: spazi e ritorni a capo diventano uno spazio.
    private static func preview(of text: String) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(parts.joined(separator: " ").prefix(200))
    }
}
