import AppKit

/// Pannello che puo' ricevere i tasti senza attivare l'app.
/// Cosi' l'app in primo piano resta la stessa e riceve poi il Cmd+V.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClipCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let deleteButton = NSButton()
    var onDelete: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        deleteButton.title = ""
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Elimina")
        deleteButton.imagePosition = .imageOnly
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.toolTip = "Elimina dalla lista"
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(deleteButton)
        textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    @objc private func deleteClicked() { onDelete?() }
}

final class HistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: HistoryStore
    private let panel: KeyPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Nessun elemento copiato")
    private var keyMonitor: Any?

    var onPaste: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?

    var isVisible: Bool { panel.isVisible }

    init(store: HistoryStore) {
        self.store = store
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
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

        let title = NSTextField(labelWithString: "Storico appunti")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let hint = NSTextField(labelWithString: "↑↓ scegli   ↩ incolla   ⌫ elimina   esc chiudi")
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
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        for view in [title, scrollView, hint, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),

            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),

            hint.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            hint.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    // MARK: - Mostra / nascondi

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        reload(selecting: 0)

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
        reload(selecting: max(tableView.selectedRow, 0))
    }

    private func reload(selecting row: Int) {
        tableView.reloadData()
        let count = store.items.count
        emptyLabel.isHidden = count > 0
        guard count > 0 else { return }
        let target = min(max(row, 0), count - 1)
        tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        tableView.scrollRowToVisible(target)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()   // clic fuori dal pannello
    }

    // MARK: - Tastiera

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.window === panel else { return event }
        switch event.keyCode {
        case 125: moveSelection(by: 1); return nil      // freccia giu'
        case 126: moveSelection(by: -1); return nil     // freccia su
        case 36, 76: pasteSelected(); return nil        // invio
        case 53: hide(); return nil                     // esc
        case 51, 117: deleteSelected(); return nil      // backspace / canc
        default: return event
        }
    }

    private func moveSelection(by delta: Int) {
        let count = store.items.count
        guard count > 0 else { return }
        let row = min(max(tableView.selectedRow + delta, 0), count - 1)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func item(at row: Int) -> ClipItem? {
        guard row >= 0, row < store.items.count else { return nil }
        return store.items[row]
    }

    private func pasteSelected() {
        guard let item = item(at: tableView.selectedRow) else { return }
        onPaste?(item)
    }

    private func deleteSelected() {
        guard let item = item(at: tableView.selectedRow) else { return }
        onDelete?(item)
    }

    @objc private func rowClicked() {
        guard let item = item(at: tableView.clickedRow) else { return }
        onPaste?(item)
    }

    // MARK: - Tabella

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ClipCellView) ?? {
            let view = ClipCellView(frame: .zero)
            view.identifier = identifier
            return view
        }()

        let item = store.items[row]
        cell.label.stringValue = Self.preview(of: item.text)
        cell.toolTip = String(item.text.prefix(600))
        cell.onDelete = { [weak self] in self?.onDelete?(item) }
        return cell
    }

    /// Una sola riga: spazi e ritorni a capo diventano uno spazio.
    private static func preview(of text: String) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(parts.joined(separator: " ").prefix(200))
    }
}
