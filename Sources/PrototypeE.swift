import AppKit

// PROTOTYPE (#19) variante E "Proposta design": pannello a se', dalla revisione di design.
// Ricerca in testa, sezioni Fissati / Recenti, azioni nel menu ⌘K, editor a scheda nel pannello.

/// PROTOTYPE: la riga selezionata resta in evidenza (accento, testo bianco) anche
/// quando il fuoco e' nel campo di ricerca.
private final class ERowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
}

private func shortName(_ item: ClipItem) -> String {
    if let label = item.etichetta { return label }
    let parts = item.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    let line = parts.joined(separator: " ")
    return line.count > 40 ? String(line.prefix(40)) + "…" : line
}

private func preview(_ text: String) -> String {
    String(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ").prefix(200))
}

// PROTOTYPE
final class ECellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let previewLabel = NSTextField(labelWithString: "")
    let pinState = NSImageView()
    var pinButton: NSButton!
    var moreButton: NSButton!
    var onPin: (() -> Void)?
    var onMore: (() -> Void)?
    private var fissato = false
    private var hasTitle = false
    private var hovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [titleLabel, previewLabel] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        pinState.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Fissato")
        pinState.setAccessibilityLabel("Fissato")
        pinState.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        pinButton = iconButton("pin", "Fissa", self, #selector(pinClicked))
        moreButton = iconButton("ellipsis", "Azioni", self, #selector(moreClicked))

        let texts = NSStackView(views: [titleLabel, previewLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [texts, pinState, pinButton, moreButton])
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        textField = previewLabel
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    func configure(_ item: ClipItem) {
        fissato = item.fissato
        hasTitle = item.etichetta != nil
        hovering = false
        titleLabel.isHidden = !hasTitle
        titleLabel.stringValue = item.etichetta ?? ""
        previewLabel.stringValue = preview(item.text)
        previewLabel.font = .systemFont(ofSize: hasTitle ? 11 : 13)
        toolTip = String(item.text.prefix(600))
        let name = shortName(item)
        pinButton.image = NSImage(systemSymbolName: fissato ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.toolTip = fissato ? "Sfissa" : "Fissa"
        pinButton.setAccessibilityLabel("\(fissato ? "Sfissa" : "Fissa") \(name)")
        moreButton.setAccessibilityLabel("Azioni per \(name)")
        refresh()
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { refresh() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }

    private func refresh() {
        let selected = (superview as? NSTableRowView)?.isSelected ?? false
        let showButtons = selected || hovering
        pinButton.isHidden = !showButtons
        moreButton.isHidden = !showButtons
        pinState.isHidden = showButtons || !fissato
        let emphasized = backgroundStyle == .emphasized
        titleLabel.textColor = emphasized ? .white : .labelColor
        previewLabel.textColor = emphasized
            ? NSColor.white.withAlphaComponent(hasTitle ? 0.85 : 1)
            : (hasTitle ? .secondaryLabelColor : .labelColor)
        pinButton.contentTintColor = emphasized ? .white : .secondaryLabelColor
        moreButton.contentTintColor = pinButton.contentTintColor
        pinState.contentTintColor = emphasized ? .white : .controlAccentColor
    }

    @objc private func pinClicked() { onPin?() }
    @objc private func moreClicked() { onMore?() }
}

// PROTOTYPE
final class PrototypeEController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate,
                                  NSTextViewDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store: HistoryStore
    private let panel: KeyPanel
    private let search = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let footerLeft = NSTextField(labelWithString: "↩ copia")
    private let footerRight = NSTextField(labelWithString: "⌘K azioni")
    private let protoState = NSTextField(labelWithString: "")
    private let contextMenu = NSMenu()
    private var rows: [PanelRow] = []
    private var footerReset: DispatchWorkItem?
    private var keyMonitor: Any?

    // Editor a scheda
    private let card = NSView()
    private var cardTop: NSLayoutConstraint!
    private let cardLabel = NSTextField(string: "")
    private let cardText = NSTextView()
    private let cardCount = NSTextField(labelWithString: "")
    private var cardButtons: NSStackView!
    private var cardConfirm: NSStackView!
    private var editing: ClipItem?

    var onLeave: ((PrototypeVariant) -> Void)?

    init(store: HistoryStore) {
        self.store = store
        // 400 di contenuto + barra PROTOTIPO
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 446),
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
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.delegate = self
        panel.appearance = NSAppearance(named: .vibrantDark)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        panel.contentView = background

        search.placeholderString = "Cerca testo o etichetta"
        search.font = .systemFont(ofSize: 14)
        search.delegate = self
        search.sendsSearchStringImmediately = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)   // clic singolo seleziona soltanto
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        for footer in [footerLeft, footerRight] {
            footer.font = .systemFont(ofSize: 11)
            footer.textColor = .secondaryLabelColor
        }

        // Barra PROTOTIPO
        let protoBox = NSView()
        protoBox.wantsLayer = true
        protoBox.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.22).cgColor
        let protoTitle = NSTextField(labelWithString: "PROTOTIPO — variante E (Proposta design)")
        protoTitle.font = .systemFont(ofSize: 11, weight: .bold)
        protoState.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        protoState.textColor = .secondaryLabelColor
        protoState.lineBreakMode = .byTruncatingTail
        protoState.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let prev = NSButton(title: "◀", target: self, action: #selector(prevVariant))
        let next = NSButton(title: "▶", target: self, action: #selector(nextVariant))
        for b in [prev, next] { b.isBordered = false; b.font = .systemFont(ofSize: 11) }
        let titleRow = NSStackView(views: [protoTitle, prev, next])
        titleRow.spacing = 4
        let protoStack = NSStackView(views: [titleRow, protoState])
        protoStack.orientation = .vertical
        protoStack.alignment = .leading
        protoStack.spacing = 2
        protoStack.translatesAutoresizingMaskIntoConstraints = false
        protoBox.addSubview(protoStack)

        buildCard()

        for view in [search, scrollView, emptyLabel, footerLeft, footerRight, protoBox, card] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        cardTop = card.topAnchor.constraint(equalTo: background.topAnchor, constant: -400)

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            search.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerLeft.topAnchor, constant: -6),

            footerLeft.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            footerLeft.bottomAnchor.constraint(equalTo: protoBox.topAnchor, constant: -8),
            footerRight.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            footerRight.centerYAnchor.constraint(equalTo: footerLeft.centerYAnchor),

            protoBox.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            protoBox.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            protoBox.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            protoStack.leadingAnchor.constraint(equalTo: protoBox.leadingAnchor, constant: 18),
            protoStack.trailingAnchor.constraint(lessThanOrEqualTo: protoBox.trailingAnchor, constant: -12),
            protoStack.topAnchor.constraint(equalTo: protoBox.topAnchor, constant: 5),
            protoStack.bottomAnchor.constraint(equalTo: protoBox.bottomAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -36),

            cardTop,
            card.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
        ])
    }

    private func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func buildCard() {
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.96).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        card.isHidden = true

        let heading = NSTextField(labelWithString: "Modifica elemento")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        cardLabel.placeholderString = "facoltativa"

        cardText.isRichText = false
        cardText.allowsUndo = true
        cardText.font = .systemFont(ofSize: 13)
        cardText.drawsBackground = false
        cardText.isVerticallyResizable = true
        cardText.autoresizingMask = .width
        cardText.textContainer?.widthTracksTextView = true
        cardText.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = cardText
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder

        cardCount.font = .systemFont(ofSize: 11)
        cardCount.textColor = .tertiaryLabelColor

        let cancel = NSButton(title: "Annulla", target: self, action: #selector(escInEditor))
        let save = NSButton(title: "Salva", target: self, action: #selector(saveEdit))
        save.bezelColor = .controlAccentColor
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = .command   // ↩ da solo va a capo nel testo
        cancel.toolTip = "esc"
        save.toolTip = "⌘↩"
        cardButtons = NSStackView(views: [cardCount, NSView(), cancel, save])
        cardButtons.spacing = 8

        let question = NSTextField(labelWithString: "Scartare le modifiche?")
        question.font = .systemFont(ofSize: 12, weight: .medium)
        let keep = NSButton(title: "Continua a modificare", target: self, action: #selector(keepEditing))
        let discard = NSButton(title: "Scarta", target: self, action: #selector(discardEdit))
        discard.bezelColor = .systemRed
        cardConfirm = NSStackView(views: [question, NSView(), keep, discard])
        cardConfirm.spacing = 8
        cardConfirm.isHidden = true

        let stack = NSStackView(views: [heading, caption("Etichetta"), cardLabel, caption("Testo"), scroll, cardButtons, cardConfirm])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(12, after: cardLabel)
        stack.setCustomSpacing(10, after: scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            cardLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 104),   // ~6 righe a 13pt
            cardButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cardConfirm.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    // MARK: - Mostra / nascondi / varianti

    var isVisible: Bool { panel.isVisible }

    func show() {
        if editing != nil { closeEditor(animated: false) }
        search.stringValue = ""
        reload(keeping: nil, fallback: 0)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                         y: area.midY - size.height / 2 + area.height * 0.08))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(search)
    }

    func hide() { panel.orderOut(nil) }

    @objc private func prevVariant() { hide(); onLeave?(PrototypeVariant.e.shifted(by: -1)) }
    @objc private func nextVariant() { hide(); onLeave?(PrototypeVariant.e.shifted(by: 1)) }

    // MARK: - Lista

    private func buildRows() {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matches = store.items.filter {
            query.isEmpty || $0.text.range(of: query, options: options) != nil
                || $0.etichetta?.range(of: query, options: options) != nil
        }
        let pinned = matches.filter(\.fissato).map { PanelRow.item($0) }
        let recent = matches.filter { !$0.fissato }.map { PanelRow.item($0) }
        if !query.isEmpty {
            rows = pinned + recent   // cercando: niente intestazioni
        } else {
            rows = (pinned.isEmpty ? [] : [.header("FISSATI")] + pinned)
                + (recent.isEmpty ? [] : [.header("RECENTI")] + recent)
        }
    }

    private func item(at row: Int) -> ClipItem? {
        guard row >= 0, row < rows.count, case .item(let item) = rows[row] else { return nil }
        return item
    }

    private var selected: ClipItem? { item(at: tableView.selectedRow) }

    private func row(of id: UUID) -> Int? {
        rows.indices.first { item(at: $0)?.id == id }
    }

    /// Riseleziona `id` se c'e' ancora, altrimenti l'elemento piu' vicino a `fallback`.
    private func reload(keeping id: UUID?, fallback: Int) {
        buildRows()
        tableView.reloadData()
        let itemRows = rows.indices.filter { item(at: $0) != nil }
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        emptyLabel.stringValue = store.items.isEmpty ? L("panel.empty") : "Nessun risultato per “\(query)”"
        emptyLabel.isHidden = !itemRows.isEmpty
        if let target = id.flatMap(row(of:)) ?? itemRows.first(where: { $0 >= fallback }) ?? itemRows.last {
            tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
            tableView.scrollRowToVisible(target)
        }
        updateState()
    }

    private func updateState() {
        let pinned = store.items.filter(\.fissato).count
        protoState.stringValue = "fissati \(pinned) · non fissati \(store.items.count - pinned) · selezione: "
            + (selected.map { "\(shortName($0))\($0.fissato ? " (fissato)" : "")" } ?? "nessuna")
    }

    private func move(by delta: Int) {
        var row = tableView.selectedRow
        repeat {   // salta le intestazioni
            let next = row + delta
            guard next >= 0, next < rows.count else { return }
            row = next
        } while item(at: row) == nil
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func controlTextDidChange(_ obj: Notification) {
        reload(keeping: nil, fallback: 0)
    }

    // MARK: - Azioni

    /// Messaggio di 2 secondi a sinistra nel pie' di pagina.
    private func flash(_ text: String, warning: Bool = false) {
        footerReset?.cancel()
        footerLeft.stringValue = text
        footerLeft.textColor = warning ? .systemOrange : .labelColor
        let reset = DispatchWorkItem { [weak self] in
            self?.footerLeft.stringValue = "↩ copia"
            self?.footerLeft.textColor = .secondaryLabelColor
        }
        footerReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
    }

    private func copy(_ item: ClipItem) {
        flash("Copiato (finto): “\(shortName(item))” — appunti invariati")
    }

    private func togglePin(_ item: ClipItem) {
        store.togglePin(ids: [item.id])
        reload(keeping: item.id, fallback: 0)
    }

    private func delete(_ item: ClipItem) {
        guard !item.fissato else {
            NSSound.beep()
            flash("Elemento fissato: sfissalo (⌘P) per eliminarlo", warning: true)
            return
        }
        let fallback = tableView.selectedRow
        store.remove(ids: [item.id])
        reload(keeping: nil, fallback: fallback)
    }

    @objc private func doubleClicked() {
        if let item = item(at: tableView.clickedRow) { copy(item) }
    }

    // MARK: - Menu azioni (⌘K, puntini, clic destro)

    private func fillActionMenu(_ menu: NSMenu, for item: ClipItem) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: shortName(item), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        func add(_ title: String, _ action: Selector, _ key: String, _ mask: NSEvent.ModifierFlags) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = mask
            menuItem.target = self
            menuItem.representedObject = item.id
            menu.addItem(menuItem)
            return menuItem
        }
        _ = add("Copia", #selector(menuCopy), "\r", [])
        _ = add("Modifica…", #selector(menuEdit), "e", .command)
        _ = add(item.fissato ? "Sfissa" : "Fissa", #selector(menuPin), "p", .command)
        menu.addItem(.separator())
        let delete = add("Elimina", #selector(menuDelete), String(UnicodeScalar(8)), [])
        delete.isEnabled = !item.fissato
        if item.fissato {
            let why = NSMenuItem(title: "Sfissa per poterlo eliminare", action: nil, keyEquivalent: "")
            why.isEnabled = false
            menu.addItem(why)
        }
    }

    private func showActionMenu() {
        guard let item = selected else { NSSound.beep(); return }
        let menu = NSMenu()
        fillActionMenu(menu, for: item)
        let rect = tableView.rect(ofRow: tableView.selectedRow)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.maxX - 180, y: rect.maxY), in: tableView)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {   // clic destro
        menu.removeAllItems()
        guard let item = item(at: tableView.clickedRow) else { return }
        tableView.selectRowIndexes(IndexSet(integer: tableView.clickedRow), byExtendingSelection: false)
        fillActionMenu(menu, for: item)
    }

    private func menuTarget(_ sender: NSMenuItem) -> ClipItem? {
        store.items.first { $0.id == sender.representedObject as? UUID }
    }
    @objc private func menuCopy(_ sender: NSMenuItem) { if let i = menuTarget(sender) { copy(i) } }
    @objc private func menuEdit(_ sender: NSMenuItem) { if let i = menuTarget(sender) { openEditor(i) } }
    @objc private func menuPin(_ sender: NSMenuItem) { if let i = menuTarget(sender) { togglePin(i) } }
    @objc private func menuDelete(_ sender: NSMenuItem) { if let i = menuTarget(sender) { delete(i) } }

    // MARK: - Tastiera

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.window === panel else { return event }
        let command = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if editing != nil {
            if [36, 76].contains(event.keyCode), command { saveEdit(); return nil }
            if event.keyCode == 53 { escInEditor(); return nil }
            return event
        }
        if command {
            switch key {
            case "e": if let i = selected { openEditor(i) } else { NSSound.beep() }; return nil
            case "p": if let i = selected { togglePin(i) } else { NSSound.beep() }; return nil
            case "k": showActionMenu(); return nil
            default: return event
            }
        }
        switch event.keyCode {
        case 125 where !event.modifierFlags.contains(.shift): move(by: 1); return nil
        case 126 where !event.modifierFlags.contains(.shift): move(by: -1); return nil
        case 36, 76: if let i = selected { copy(i) }; return nil
        case 53:
            if search.stringValue.isEmpty { hide() } else {
                search.stringValue = ""
                reload(keeping: selected?.id, fallback: 0)
            }
            return nil
        case 51, 117:
            guard panel.firstResponder === tableView else { return event }   // nel campo ⌫ corregge la ricerca
            if let i = selected { delete(i) }
            return nil
        default: return event
        }
    }

    // MARK: - Editor a scheda

    private func openEditor(_ item: ClipItem) {
        editing = item
        cardLabel.stringValue = item.etichetta ?? ""
        cardText.string = item.text
        cardText.setSelectedRange(NSRange(location: 0, length: 0))
        cardText.scrollToBeginningOfDocument(nil)
        updateCount()
        cardConfirm.isHidden = true
        cardButtons.isHidden = false
        card.isHidden = false
        card.superview?.layoutSubtreeIfNeeded()
        cardTop.constant = -card.frame.height - 10
        card.superview?.layoutSubtreeIfNeeded()
        setDimmed(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            cardTop.animator().constant = 10
        }
        panel.makeFirstResponder(cardText)
    }

    private func setDimmed(_ dimmed: Bool) {
        for view in [search, scrollView, footerLeft, footerRight, emptyLabel] as [NSView] {
            view.alphaValue = dimmed ? 0.35 : 1
        }
        search.isEnabled = !dimmed
        tableView.isEnabled = !dimmed
    }

    private func closeEditor(animated: Bool = true) {
        editing = nil
        setDimmed(false)
        let hidden = -card.frame.height - 10
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                cardTop.animator().constant = hidden
            }, completionHandler: { [weak self] in
                if self?.editing == nil { self?.card.isHidden = true }
            })
        } else {
            cardTop.constant = hidden
            card.isHidden = true
        }
        panel.makeFirstResponder(search)
    }

    private var hasChanges: Bool {
        guard let item = editing else { return false }
        let label = cardLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return cardText.string != item.text || label != (item.etichetta ?? "")
    }

    @objc private func escInEditor() {
        if !cardConfirm.isHidden { keepEditing(); return }
        guard hasChanges else { closeEditor(); return }
        cardButtons.isHidden = true
        cardConfirm.isHidden = false
    }

    @objc private func keepEditing() {
        cardConfirm.isHidden = true
        cardButtons.isHidden = false
        panel.makeFirstResponder(cardText)
    }

    @objc private func discardEdit() { closeEditor() }

    @objc private func saveEdit() {
        guard let item = editing else { return }
        let text = cardText.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        let label = cardLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(id: item.id, text: text)
        store.setEtichetta(id: item.id, label.isEmpty ? nil : label)
        closeEditor()
        reload(keeping: item.id, fallback: 0)
        flash("Salvato")
    }

    func textDidChange(_ notification: Notification) { updateCount() }

    private func updateCount() {
        let text = cardText.string
        let lines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        cardCount.stringValue = "\(lines) \(lines == 1 ? "riga" : "righe") · \(text.count) caratteri"
    }

    // MARK: - Tabella

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateState() }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.filteredIndexSet { item(at: $0) != nil }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { item(at: row) == nil }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = item(at: row) else { return 22 }
        return item.etichetta != nil ? 44 : 30
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        item(at: row) == nil ? nil : ERowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = item(at: row) else {
            let header = HeaderCellView(frame: .zero)
            header.label.font = .systemFont(ofSize: 10, weight: .semibold)
            if case .header(let text) = rows[row] { header.label.stringValue = text }
            return header
        }
        let identifier = NSUserInterfaceItemIdentifier("ECell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ECellView) ?? {
            let view = ECellView(frame: .zero)
            view.identifier = identifier
            return view
        }()
        cell.configure(item)
        cell.onPin = { [weak self] in self?.togglePin(item) }
        cell.onMore = { [weak self] in
            guard let self, let row = self.row(of: item.id) else { return }
            self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            self.showActionMenu()
        }
        return cell
    }
}
