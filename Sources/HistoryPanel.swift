import AppKit

/// Pannello che puo' ricevere i tasti senza attivare l'app.
/// Cosi' l'app in primo piano resta la stessa e riceve poi il Cmd+V.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Colori e viste di base

enum PanelColor {
    /// Un solo riempimento per ricerca, tasti e campi: nero 5,5% in chiaro, bianco 8% in scuro.
    static let fill = adaptive(dark: 0.08, light: 0.055)
    /// Pulsanti secondari e bordo del foglio.
    static let strongFill = adaptive(dark: 0.14, light: 0.09)
    /// Testo e icone sopra l'evidenziazione d'accento.
    static var onAccent: NSColor { .alternateSelectedControlTextColor }

    private static func adaptive(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        }
    }

    /// Velatura del colore di sfondo di sistema sopra il materiale. Risolta dentro il
    /// provider: `withAlphaComponent` su un colore dinamico resta fisso all'aspetto di creazione.
    static func ground(alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            // Dentro il materiale l'aspetto e' "vibrant": si risolve sull'aspetto base.
            let base = NSAppearance(named: appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua) ?? appearance
            var resolved = NSColor.controlBackgroundColor
            base.performAsCurrentDrawingAppearance {
                resolved = NSColor.controlBackgroundColor.usingColorSpace(.sRGB) ?? .controlBackgroundColor
            }
            return resolved.withAlphaComponent(alpha)
        }
    }
}

/// Vista con riempimento, bordo e raggio; i colori dinamici si risolvono a ogni disegno,
/// quindi segue il cambio chiaro/scuro anche a pannello aperto.
class FillView: NSView {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var border: NSColor? { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }

    init(fill: NSColor? = nil, border: NSColor? = nil, radius: CGFloat = 0) {
        super.init(frame: .zero)
        self.fill = fill
        self.border = border
        self.radius = radius
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let rect = border == nil ? bounds : bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let fill { fill.setFill(); path.fill() }
        if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Pulsante senza bordo. I simboli SF hanno un proprio alignmentRect che NSButton
/// trasforma in alignmentRectInsets: Auto Layout allarga il frame e deforma l'immagine.
/// Azzerati, il frame coincide col quadrato del vincolo.
final class PlainButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

/// Pulsante icona 22×22 della riga selezionata (bianco sull'accento).
private func rowIconButton(symbol: String, target: AnyObject, action: Selector) -> PlainButton {
    let button = PlainButton()
    button.isBordered = false
    button.title = ""
    button.image = symbolImage(symbol)
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.contentTintColor = PanelColor.onAccent
    button.wantsLayer = true
    button.layer?.cornerRadius = 5
    button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    button.target = target
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 22),
        button.heightAnchor.constraint(equalToConstant: 22),
    ])
    return button
}

private func symbolImage(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
}

/// Pulsante a pillola (Annulla / Salva del foglio).
private final class PillButton: FillView {
    let button: NSButton = PlainButton()
    private let title: String
    private let titleColor: NSColor
    private let weight: NSFont.Weight

    init(title: String, fill: NSColor, titleColor: NSColor, weight: NSFont.Weight = .regular,
         padding: CGFloat, target: AnyObject, action: Selector) {
        self.title = title
        self.titleColor = titleColor
        self.weight = weight
        super.init(fill: fill, radius: 6)
        button.isBordered = false
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(equalTo: button.widthAnchor, constant: padding * 2),
        ])
        isEnabled = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    var isEnabled: Bool {
        get { button.isEnabled }
        set {
            button.isEnabled = newValue
            alphaValue = newValue ? 1 : 0.5
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: weight), .foregroundColor: titleColor,
            ])
        }
    }
}

/// Tasto stile <kbd>: 11 pt, raggio 4, bordo sottile.
private final class Keycap: FillView {
    let label = NSTextField(labelWithString: "")
    init(filled: Bool) {
        super.init(fill: filled ? PanelColor.fill : nil, border: .separatorColor, radius: 4)
        label.font = .systemFont(ofSize: 11)
        label.textColor = filled ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }
}

private func textLabel(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
}

/// Una sola riga: spazi e ritorni a capo diventano uno spazio.
private func preview(_ text: String) -> String {
    String(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ").prefix(200))
}

/// Nome breve per menu ed etichette accessibili: l'Etichetta o l'inizio del testo.
func shortName(_ item: ClipItem) -> String {
    if let etichetta = item.etichetta { return etichetta }
    let line = preview(item.text)
    return line.count > 40 ? String(line.prefix(40)) + "…" : line
}

// MARK: - Righe della lista

private enum PanelRow {
    case header(String)
    case spacer
    case item(ClipItem)
}

/// Selezione d'accento rientrata (10 ai lati, 2 sopra e sotto, raggio 6), sempre in evidenza
/// anche con il focus nel campo di ricerca.
private final class PanelRowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }

    /// Le intestazioni flottanti hanno sotto lo stesso fondo del pannello,
    /// cosi' le righe che scorrono non traspaiono.
    func addPanelGround() {
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        let veil = FillView(fill: PanelColor.ground(alpha: 0.92))
        for view in [material, veil] as [NSView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
        }
        addSubview(material, positioned: .below, relativeTo: nil)
        addSubview(veil, positioned: .above, relativeTo: material)
    }
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSeparator(in dirtyRect: NSRect) {}
    override func draw(_ dirtyRect: NSRect) {
        if isGroupRowStyle { return }
        super.draw(dirtyRect)
    }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 2), xRadius: 6, yRadius: 6).fill()
    }
}

/// Intestazione di sezione: 10 pt semibold maiuscolo, secondario, rientro 18.
private final class CaptionCellView: NSTableCellView {
    init(_ title: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.6,
        ])
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18).isActive = true
        label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }
}

private final class ItemCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let previewLabel = NSTextField(labelWithString: "")
    let pinState = NSImageView()
    var pinButton: PlainButton!
    var moreButton: PlainButton!
    var onPin: (() -> Void)?
    var onMore: (() -> Void)?
    private var fissato = false
    private var hasTitle = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [titleLabel, previewLabel] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        pinState.image = symbolImage("pin.fill")
        pinState.imageScaling = .scaleProportionallyDown
        pinState.contentTintColor = .controlAccentColor
        pinState.setAccessibilityLabel(L("panel.pinned"))
        pinButton = rowIconButton(symbol: "pin", target: self, action: #selector(pinClicked))
        moreButton = rowIconButton(symbol: "ellipsis", target: self, action: #selector(moreClicked))

        let texts = NSStackView(views: [titleLabel, previewLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 0
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Colonna finale a larghezza fissa (22 + 6 + 22), uguale per ogni riga.
        let trailing = NSView()
        let buttons = NSStackView(views: [pinButton, moreButton])
        buttons.spacing = 6
        for view in [texts, trailing, pinState, buttons] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        trailing.addSubview(pinState)
        trailing.addSubview(buttons)
        addSubview(texts)
        addSubview(trailing)
        textField = previewLabel
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            texts.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -6),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.widthAnchor.constraint(equalToConstant: 50),
            trailing.heightAnchor.constraint(equalToConstant: 22),
            buttons.trailingAnchor.constraint(equalTo: trailing.trailingAnchor),
            buttons.centerYAnchor.constraint(equalTo: trailing.centerYAnchor),
            // La puntina sta nello stesso quadrato 22×22 dell'ultimo pulsante.
            pinState.centerXAnchor.constraint(equalTo: trailing.trailingAnchor, constant: -11),
            pinState.centerYAnchor.constraint(equalTo: trailing.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    func configure(_ item: ClipItem, pinKey: String?, menuKey: String?) {
        fissato = item.fissato
        hasTitle = item.etichetta != nil
        titleLabel.isHidden = !hasTitle
        titleLabel.stringValue = item.etichetta ?? ""
        previewLabel.stringValue = preview(item.text)
        previewLabel.font = .systemFont(ofSize: hasTitle ? 11 : 13)
        toolTip = String(item.text.prefix(600))
        let name = shortName(item)
        pinButton.image = symbolImage(fissato ? "pin.fill" : "pin")
        pinButton.toolTip = withKey(L(fissato ? "action.unpin" : "action.pin"), pinKey)
        pinButton.setAccessibilityLabel(String(format: L(fissato ? "a11y.unpin" : "a11y.pin"), name))
        moreButton.toolTip = withKey(L("panel.actions"), menuKey)
        moreButton.setAccessibilityLabel(String(format: L("a11y.actions"), name))
        refresh()
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { refresh() } }

    private func refresh() {
        let selected = (superview as? NSTableRowView)?.isSelected ?? false
        pinButton.isHidden = !selected       // pulsanti solo sulla riga selezionata
        moreButton.isHidden = !selected
        pinState.isHidden = selected || !fissato
        let onAccent = backgroundStyle == .emphasized
        titleLabel.textColor = onAccent ? PanelColor.onAccent : .labelColor
        previewLabel.textColor = onAccent
            ? PanelColor.onAccent.withAlphaComponent(hasTitle ? 0.85 : 1)
            : (hasTitle ? .secondaryLabelColor : .labelColor)
    }

    @objc private func pinClicked() { onPin?() }
    @objc private func moreClicked() { onMore?() }
}

private func withKey(_ title: String, _ key: String?) -> String {
    key.map { "\(title) (\($0))" } ?? title
}

// MARK: - Pannello

final class HistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate,
                                    NSTextViewDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store: HistoryStore
    private let shortcuts: ShortcutSettings
    private let panel: KeyPanel
    private let background = NSVisualEffectView()
    private let searchBox = FillView(fill: PanelColor.fill, radius: 7)
    private let search = NSTextField(string: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = textLabel("", size: 13, color: .secondaryLabelColor)
    private let footer = NSView()
    private let footerLeft = NSStackView()
    private let footerRight = NSStackView()
    private let copyKey = Keycap(filled: true)
    private let copyHint = textLabel("", size: 11, color: .secondaryLabelColor)
    private let menuKey = Keycap(filled: true)
    private let footerFlash = textLabel("", size: 11)
    private let bubble = NSVisualEffectView()
    private let bubbleLabel = textLabel("", size: 11)
    private let contextMenu = NSMenu()
    private var rows: [PanelRow] = []
    private var flashReset: DispatchWorkItem?
    private var bubbleReset: DispatchWorkItem?
    private var keyMonitor: Any?

    // Foglio di modifica
    private let sheet = NSVisualEffectView()
    private let sheetLabelBox = FillView(fill: PanelColor.fill, border: .separatorColor, radius: 6)
    private let sheetLabel = NSTextField(string: "")
    private let sheetTextBox = FillView(fill: PanelColor.fill, border: .separatorColor, radius: 6)
    private let sheetText = NSTextView()
    private let sheetCount = textLabel("", size: 11, color: .secondaryLabelColor)
    private var sheetButtons: NSStackView!
    private var sheetConfirm: NSStackView!
    private var saveButton: PillButton!
    private let cancelKey = Keycap(filled: false)
    private let saveKey = Keycap(filled: false)
    private var editing: ClipItem?

    /// Elementi nell'ordine dello storico.
    var onCopy: (([ClipItem]) -> Void)?
    /// Restituisce false se non e' stato eliminato nulla (solo fissati).
    var onDelete: (([ClipItem]) -> Bool)?
    /// Restituisce false se lo storico rifiuta la modifica (testo vuoto).
    var onSave: ((ClipItem, String, String?) -> Bool)?

    var isVisible: Bool { panel.isVisible }

    init(store: HistoryStore, shortcuts: ShortcutSettings) {
        self.store = store
        self.shortcuts = shortcuts
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                         styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        // Chiede a macOS di escludere pannello e foglio dalla condivisione schermo.
        // Su macOS 15.4+ ScreenCaptureKit puo' ignorarlo (docs/research/screen-sharing-exclusion.md).
        // `--allow-screencapture` lo disattiva, per gli screenshot dello store.
        panel.sharingType = CommandLine.arguments.contains("--allow-screencapture") ? .readOnly : .none
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

        background.material = .popover   // adattivo: segue chiaro/scuro
        background.blendingMode = .behindWindow
        background.state = .active
        panel.contentView = background
        let veil = FillView(fill: PanelColor.ground(alpha: 0.92))

        // Ricerca: 28 alto, raggio 7, lente e campo senza bordo.
        let glass = NSImageView(image: symbolImage("magnifyingglass") ?? NSImage())
        glass.imageScaling = .scaleProportionallyDown
        glass.contentTintColor = .secondaryLabelColor
        search.placeholderString = L("panel.search.placeholder")
        search.setAccessibilityLabel(L("panel.search.a11y"))
        search.font = .systemFont(ofSize: 13)
        search.isBezeled = false
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.delegate = self
        search.cell?.isScrollable = true
        search.cell?.wraps = false
        let searchRow = NSStackView(views: [glass, search])
        searchRow.spacing = 6
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(searchRow)
        NSLayoutConstraint.activate([
            searchRow.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 8),
            searchRow.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            searchRow.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
        ])

        // Lista unica con intestazioni flottanti (righe di gruppo).
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.floatsGroupRows = true
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)   // il clic singolo seleziona soltanto
        contextMenu.delegate = self
        tableView.menu = contextMenu
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // 8 pt in fondo alla lista; quelli in cima stanno fuori (vedi topAnchor), cosi'
        // l'intestazione flottante resta a filo del bordo della lista.
        // ponytail: su macOS 26 sotto l'intestazione flottante il sistema disegna una riga
        // sottile ("scroll edge"); nessuna API pubblica la toglie su NSScrollView, la si accetta.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byTruncatingTail

        // Pie' di pagina: 30 alto, filo superiore, tasti configurati.
        let rule = FillView(fill: .separatorColor)
        footerLeft.setViews([copyKey, copyHint], in: .leading)
        footerRight.setViews([menuKey, textLabel(L("panel.footer.actions"), size: 11, color: .secondaryLabelColor)],
                             in: .leading)
        footerLeft.spacing = 4
        footerRight.spacing = 4
        footerFlash.isHidden = true
        for view in [rule, footerLeft, footerRight, footerFlash] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            rule.topAnchor.constraint(equalTo: footer.topAnchor),
            rule.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            footerLeft.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            footerLeft.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footerFlash.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            footerFlash.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footerRight.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            footerRight.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        // Fumetto sui fissati: raggio 6, 11 pt.
        bubble.material = .toolTip
        bubble.state = .active
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 6
        bubble.layer?.masksToBounds = true
        bubble.isHidden = true
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(bubbleLabel)
        NSLayoutConstraint.activate([
            bubbleLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            bubbleLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 5),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -5),
        ])

        buildSheet()

        for view in [veil, searchBox, scrollView, emptyLabel, footer, sheet, bubble] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        bubble.translatesAutoresizingMaskIntoConstraints = true   // posizionato a mano sotto la riga

        NSLayoutConstraint.activate([
            veil.topAnchor.constraint(equalTo: background.topAnchor),
            veil.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            veil.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: background.trailingAnchor),

            searchBox.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            searchBox.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            searchBox.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            searchBox.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 16),   // 8 + 8
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: 30),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -36),

            sheet.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            sheet.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            sheet.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
        ])
    }

    private func caption(_ string: String) -> NSTextField {
        textLabel(string, size: 11, color: .secondaryLabelColor)
    }

    /// Foglio di modifica dentro il pannello: rientro 10, raggio 10.
    private func buildSheet() {
        sheet.material = .menu
        sheet.blendingMode = .withinWindow
        sheet.state = .active
        sheet.wantsLayer = true
        sheet.layer?.cornerRadius = 10
        sheet.layer?.masksToBounds = true
        sheet.isHidden = true
        let sheetBorder = FillView(fill: PanelColor.strongFill, border: .separatorColor, radius: 10)

        let heading = textLabel(L("edit.title"), size: 13, weight: .semibold)

        sheetLabel.font = .systemFont(ofSize: 13)
        sheetLabel.placeholderString = L("edit.label.placeholder")
        sheetLabel.setAccessibilityLabel(L("edit.label"))
        sheetLabel.isBezeled = false
        sheetLabel.isBordered = false
        sheetLabel.drawsBackground = false
        sheetLabel.focusRingType = .none
        sheetLabel.cell?.isScrollable = true
        sheetLabel.cell?.wraps = false
        sheetLabel.translatesAutoresizingMaskIntoConstraints = false
        sheetLabelBox.addSubview(sheetLabel)
        NSLayoutConstraint.activate([
            sheetLabelBox.heightAnchor.constraint(equalToConstant: 26),
            sheetLabel.leadingAnchor.constraint(equalTo: sheetLabelBox.leadingAnchor, constant: 8),
            sheetLabel.trailingAnchor.constraint(equalTo: sheetLabelBox.trailingAnchor, constant: -8),
            sheetLabel.centerYAnchor.constraint(equalTo: sheetLabelBox.centerYAnchor),
        ])

        // Testo: 84 alto (4 righe da 18), scorre.
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        sheetText.isRichText = false
        sheetText.allowsUndo = true
        sheetText.font = .systemFont(ofSize: 13)
        sheetText.textColor = .labelColor
        sheetText.defaultParagraphStyle = paragraph
        sheetText.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph,
                                      .foregroundColor: NSColor.labelColor]
        sheetText.drawsBackground = false
        sheetText.focusRingType = .none
        sheetText.textContainerInset = NSSize(width: 8, height: 6)
        sheetText.textContainer?.lineFragmentPadding = 0
        sheetText.isVerticallyResizable = true
        sheetText.autoresizingMask = .width
        sheetText.textContainer?.widthTracksTextView = true
        sheetText.setAccessibilityLabel(L("edit.text"))
        sheetText.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = sheetText
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sheetTextBox.addSubview(scroll)
        NSLayoutConstraint.activate([
            sheetTextBox.heightAnchor.constraint(equalToConstant: 84),
            scroll.topAnchor.constraint(equalTo: sheetTextBox.topAnchor, constant: 1),
            scroll.bottomAnchor.constraint(equalTo: sheetTextBox.bottomAnchor, constant: -1),
            scroll.leadingAnchor.constraint(equalTo: sheetTextBox.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: sheetTextBox.trailingAnchor, constant: -1),
        ])

        // Pulsanti a destra, ciascuno con il suo tasto sotto.
        let cancel = PillButton(title: L("button.cancel"), fill: PanelColor.strongFill, titleColor: .labelColor,
                                padding: 14, target: self, action: #selector(cancelEdit))
        saveButton = PillButton(title: L("button.save"), fill: .controlAccentColor, titleColor: PanelColor.onAccent,
                                weight: .semibold, padding: 18, target: self, action: #selector(saveEdit))
        func withKey(_ button: NSView, _ key: Keycap) -> NSStackView {
            let stack = NSStackView(views: [button, key])
            stack.orientation = .vertical
            stack.spacing = 3
            return stack
        }
        sheetButtons = NSStackView(views: [NSView(), withKey(cancel, cancelKey), withKey(saveButton, saveKey)])
        sheetButtons.spacing = 10
        sheetButtons.alignment = .top

        let question = textLabel(L("edit.discard.question"), size: 13, weight: .medium)
        let keep = PillButton(title: L("edit.discard.keep"), fill: PanelColor.strongFill, titleColor: .labelColor,
                              padding: 14, target: self, action: #selector(keepEditing))
        let discard = PillButton(title: L("edit.discard.confirm"), fill: .systemRed, titleColor: PanelColor.onAccent,
                                 weight: .semibold, padding: 18, target: self, action: #selector(discardEdit))
        sheetConfirm = NSStackView(views: [question, NSView(), keep, discard])
        sheetConfirm.spacing = 10
        sheetConfirm.isHidden = true

        let stack = NSStackView(views: [heading, caption(L("edit.label")), sheetLabelBox, caption(L("edit.text")),
                                        sheetTextBox, sheetCount, sheetButtons, sheetConfirm])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(10, after: sheetLabelBox)
        stack.setCustomSpacing(10, after: sheetCount)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheetBorder.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(sheetBorder)   // sotto il contenuto, cosi' non intercetta i clic
        sheet.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -16),
            sheetLabelBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sheetTextBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sheetButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sheetConfirm.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sheetBorder.topAnchor.constraint(equalTo: sheet.topAnchor),
            sheetBorder.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
            sheetBorder.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            sheetBorder.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
        ])
    }

    /// Tasti configurati nel pie' di pagina e nel foglio; un'azione su "Nessuna" nasconde il suo tasto.
    private func refreshKeys() {
        let autoPaste = UserDefaults.standard.bool(forKey: "autoPasteOnSelection") && CGPreflightPostEventAccess()
        copyHint.stringValue = L(autoPaste ? "panel.footer.paste" : "panel.footer.copy")
        for (cap, action) in [(copyKey, ShortcutAction.copy), (menuKey, .actionMenu),
                              (cancelKey, .cancelEdit), (saveKey, .save)] {
            let shortcut = shortcuts.shortcut(for: action)
            cap.label.stringValue = shortcut?.display ?? ""
            cap.isHidden = shortcut == nil
        }
        footerLeft.isHidden = shortcuts.shortcut(for: .copy) == nil || !footerFlash.isHidden
        footerRight.isHidden = shortcuts.shortcut(for: .actionMenu) == nil
    }

    // MARK: - Mostra / nascondi

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        if editing != nil { closeSheet() }
        search.stringValue = ""
        refreshKeys()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                         y: area.midY - size.height / 2 + area.height * 0.08))
        }
        panel.orderFrontRegardless()
        background.layoutSubtreeIfNeeded()   // la lista ha la sua altezza prima di scorrere
        reload(keeping: [], fallback: 0)
        panel.makeKey()
        panel.makeFirstResponder(search)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()   // clic fuori dal pannello
    }

    func reloadIfVisible() {
        guard panel.isVisible else { return }
        reload(keeping: Set(selectedItems().map(\.id)), fallback: tableView.selectedRowIndexes.first ?? 0)
    }

    // MARK: - Lista

    private func buildRows() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = searchItems(store.items, query: query)
        let pinned = found.fissati.map(PanelRow.item)
        let recent = found.recenti.map(PanelRow.item)
        if !query.isEmpty {
            rows = pinned + recent   // con una ricerca attiva: fissati prima, niente intestazioni
        } else {
            // Lo spazio fra le sezioni sta in una riga a parte: le due intestazioni restano identiche.
            rows = (pinned.isEmpty ? [] : [.header(L("panel.section.pinned"))] + pinned)
                + (pinned.isEmpty || recent.isEmpty ? [] : [.spacer])
                + (recent.isEmpty ? [] : [.header(L("panel.section.recent"))] + recent)
        }
    }

    private func item(at row: Int) -> ClipItem? {
        guard row >= 0, row < rows.count, case .item(let item) = rows[row] else { return nil }
        return item
    }

    /// Elementi selezionati, nell'ordine dello storico.
    private func selectedItems() -> [ClipItem] {
        let ids = Set(tableView.selectedRowIndexes.compactMap { item(at: $0)?.id })
        return store.items.filter { ids.contains($0.id) }
    }

    private func row(of id: UUID) -> Int? {
        rows.indices.first { item(at: $0)?.id == id }
    }

    /// Riseleziona gli elementi `ids` rimasti, altrimenti quello piu' vicino a `fallback`.
    private func reload(keeping ids: Set<UUID>, fallback: Int) {
        buildRows()
        tableView.reloadData()
        let itemRows = rows.indices.filter { item(at: $0) != nil }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        emptyLabel.stringValue = store.items.isEmpty ? L("panel.empty") : String(format: L("panel.noResults"), query)
        emptyLabel.isHidden = !itemRows.isEmpty
        let kept = IndexSet(ids.compactMap(row(of:)))
        if !kept.isEmpty {
            tableView.selectRowIndexes(kept, byExtendingSelection: false)
            reveal(kept.first!)
        } else if let target = itemRows.first(where: { $0 >= fallback }) ?? itemRows.last {
            tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
            reveal(target)
        }
    }

    private func move(by delta: Int) {
        var row = tableView.selectedRow
        repeat {   // salta intestazioni e spazio
            let next = row + delta
            guard next >= 0, next < rows.count else { return }
            row = next
        } while item(at: row) == nil
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        reveal(row)
    }

    /// Come scrollRowToVisible, ma la riga non finisce sotto l'intestazione flottante.
    private func reveal(_ row: Int) {
        tableView.scrollRowToVisible(row)
        guard rows.contains(where: { if case .header = $0 { return true } else { return false } }) else { return }
        let rect = tableView.rect(ofRow: row)
        if rect.minY < tableView.visibleRect.minY + 20 {
            tableView.scroll(NSPoint(x: 0, y: max(rect.minY - 20, 0)))
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === search else { return }
        reload(keeping: [], fallback: 0)
    }

    // MARK: - Azioni

    /// Messaggio di 2 secondi al posto dei tasti nel pie' di pagina.
    private func flash(_ message: String) {
        flashReset?.cancel()
        footerFlash.stringValue = message
        footerFlash.isHidden = false
        footerLeft.isHidden = true
        let reset = DispatchWorkItem { [weak self] in
            self?.footerFlash.isHidden = true
            self?.refreshKeys()
        }
        flashReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
    }

    /// Fumetto sotto la riga selezionata per 2 secondi.
    private func showBubble(_ message: String) {
        bubbleReset?.cancel()
        bubbleLabel.stringValue = message
        let size = bubble.fittingSize
        let rowRect = tableView.convert(tableView.rect(ofRow: max(tableView.selectedRow, 0)), to: background)
        let y = background.isFlipped ? rowRect.maxY + 2 : rowRect.minY - size.height - 2
        bubble.frame = NSRect(x: background.bounds.width - 22 - size.width, y: max(y, 34),
                              width: size.width, height: size.height)
        bubble.isHidden = false
        let reset = DispatchWorkItem { [weak self] in self?.bubble.isHidden = true }
        bubbleReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
    }

    private func copySelected() {
        let items = selectedItems()
        guard !items.isEmpty else { NSSound.beep(); return }
        onCopy?(items)
    }

    private func togglePinSelected() {
        let ids = Set(selectedItems().map(\.id))
        guard !ids.isEmpty else { NSSound.beep(); return }
        store.togglePin(ids: ids)   // onChange ricarica la lista mantenendo la selezione
    }

    private func deleteSelected() {
        let items = selectedItems()
        guard !items.isEmpty else { NSSound.beep(); return }
        guard onDelete?(items) == true else {
            // Solo fissati: nulla eliminato, appunti invariati.
            NSSound.beep()
            let key = shortcuts.shortcut(for: .togglePin)?.display
            showBubble(key.map { String(format: L("panel.pinnedBubble"), $0) } ?? L("panel.pinnedBubble.noKey"))
            return
        }
    }

    private func editSelected() {
        let items = selectedItems()
        guard items.count == 1 else { NSSound.beep(); return }
        openSheet(items[0])
    }

    @objc private func doubleClicked() {
        guard let item = item(at: tableView.clickedRow) else { return }
        onCopy?([item])
    }

    // MARK: - Menu azioni (scorciatoia, "⋯", tasto destro)

    private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ shortcutAction: ShortcutAction) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let shortcut = shortcuts.shortcut(for: shortcutAction) {
            menuItem.keyEquivalent = shortcut.keyEquivalent
            var mask: NSEvent.ModifierFlags = []
            if shortcut.modifiers.contains(.command) { mask.insert(.command) }
            if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
            if shortcut.modifiers.contains(.option) { mask.insert(.option) }
            if shortcut.modifiers.contains(.control) { mask.insert(.control) }
            menuItem.keyEquivalentModifierMask = mask
        }
        menuItem.target = self
        menu.addItem(menuItem)
        return menuItem
    }

    private func fillActionMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let items = selectedItems()
        guard !items.isEmpty else { return }
        let header = NSMenuItem(title: items.count == 1 ? shortName(items[0]) : String(format: L("panel.selection"), items.count),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        _ = addMenuItem(menu, L("action.copy"), #selector(menuCopy), .copy)
        addMenuItem(menu, L("action.edit"), #selector(menuEdit), .edit).isEnabled = items.count == 1
        let allPinned = items.allSatisfy(\.fissato)
        _ = addMenuItem(menu, L(allPinned ? "action.unpin" : "action.pin"), #selector(menuPin), .togglePin)
        menu.addItem(.separator())
        let delete = addMenuItem(menu, L("action.delete"), #selector(menuDelete), .delete)
        delete.isEnabled = !allPinned
        if allPinned {
            let why = NSMenuItem(title: L("action.delete.pinnedNote"), action: nil, keyEquivalent: "")
            why.isEnabled = false
            menu.addItem(why)
        } else {
            delete.attributedTitle = NSAttributedString(string: L("action.delete"), attributes: [
                .foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0),
            ])
        }
    }

    private func showActionMenu() {
        guard !selectedItems().isEmpty else { NSSound.beep(); return }
        let menu = NSMenu()
        fillActionMenu(menu)
        let rect = tableView.rect(ofRow: tableView.selectedRow)
        menu.popUp(positioning: nil, at: NSPoint(x: max(rect.maxX - 14 - 240, 0), y: rect.maxY), in: tableView)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {   // tasto destro
        let clicked = tableView.clickedRow
        if item(at: clicked) != nil, !tableView.selectedRowIndexes.contains(clicked) {
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        }
        fillActionMenu(menu)
    }

    @objc private func menuCopy() { copySelected() }
    @objc private func menuEdit() { editSelected() }
    @objc private func menuPin() { togglePinSelected() }
    @objc private func menuDelete() { deleteSelected() }

    // MARK: - Tastiera

    private func matches(_ event: NSEvent, _ action: ShortcutAction) -> Bool {
        guard let shortcut = shortcuts.shortcut(for: action) else { return false }
        let flags = event.modifierFlags
        var mods: Shortcut.Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        let code = event.keyCode == 76 ? 36 : event.keyCode   // invio del tastierino = ↩
        let wanted = shortcut.keyCode == 76 ? 36 : shortcut.keyCode
        return code == wanted && mods == shortcut.modifiers
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.window === panel else { return event }
        if editing != nil {
            if matches(event, .save) { saveEdit(); return nil }
            if matches(event, .cancelEdit) { cancelEdit(); return nil }
            return event
        }
        // Frecce fisse; ⇧+frecce estendono la selezione nella lista.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if [125, 126].contains(event.keyCode), flags.isEmpty {
            move(by: event.keyCode == 125 ? 1 : -1)
            return nil
        }
        if matches(event, .copy) { copySelected(); return nil }
        if matches(event, .edit) { editSelected(); return nil }
        if matches(event, .togglePin) { togglePinSelected(); return nil }
        if matches(event, .actionMenu) { showActionMenu(); return nil }
        if matches(event, .closePanel) {
            if search.stringValue.isEmpty {
                hide()
            } else {
                search.stringValue = ""
                reload(keeping: Set(selectedItems().map(\.id)), fallback: 0)
            }
            return nil
        }
        // Elimina agisce solo con il focus sulla lista: nel campo il tasto corregge la ricerca.
        if matches(event, .delete), panel.firstResponder === tableView { deleteSelected(); return nil }
        return event
    }

    // MARK: - Foglio di modifica

    private func openSheet(_ item: ClipItem) {
        editing = item
        bubble.isHidden = true
        refreshKeys()
        sheetLabel.stringValue = item.etichetta ?? ""
        sheetText.string = item.text
        sheetText.setSelectedRange(NSRange(location: 0, length: 0))
        sheetText.scrollToBeginningOfDocument(nil)
        updateSheetState()
        sheetConfirm.isHidden = true
        sheetButtons.isHidden = false
        sheet.isHidden = false
        setDimmed(true)
        panel.makeFirstResponder(sheetText)
    }

    /// Dietro il foglio la lista resta visibile, attenuata.
    private func setDimmed(_ dimmed: Bool) {
        for view in [searchBox, scrollView, footer, emptyLabel] as [NSView] {
            view.alphaValue = dimmed ? 0.35 : 1
        }
        search.isEnabled = !dimmed
        tableView.isEnabled = !dimmed
    }

    private func closeSheet() {
        editing = nil
        sheet.isHidden = true
        setDimmed(false)
        panel.makeFirstResponder(search)
    }

    private var hasChanges: Bool {
        guard let item = editing else { return false }
        return sheetText.string != item.text || HistoryStore.normalize(sheetLabel.stringValue) != item.etichetta
    }

    private var textIsBlank: Bool {
        sheetText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func cancelEdit() {
        if !sheetConfirm.isHidden { keepEditing(); return }
        guard hasChanges else { closeSheet(); return }
        sheetButtons.isHidden = true
        sheetConfirm.isHidden = false
    }

    @objc private func keepEditing() {
        sheetConfirm.isHidden = true
        sheetButtons.isHidden = false
        panel.makeFirstResponder(sheetText)
    }

    @objc private func discardEdit() { closeSheet() }

    @objc private func saveEdit() {
        guard let item = editing else { return }
        guard !textIsBlank, onSave?(item, sheetText.string, sheetLabel.stringValue) == true else {
            NSSound.beep()
            return
        }
        closeSheet()
        reload(keeping: [item.id], fallback: 0)
        flash(L("panel.saved"))
    }

    func textDidChange(_ notification: Notification) { updateSheetState() }

    private func updateSheetState() {
        let text = sheetText.string
        let lines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        sheetCount.stringValue = String(format: L(lines == 1 ? "edit.lines.one" : "edit.lines.other"), lines)
            + " · " + String(format: L(text.count == 1 ? "edit.chars.one" : "edit.chars.other"), text.count)
        saveButton.isEnabled = !textIsBlank
    }

    // MARK: - Tabella

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        bubble.isHidden = true
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.filteredIndexSet { item(at: $0) != nil }
    }

    /// Righe 48 (con Etichetta) / 34; intestazioni 20; spazio dopo i fissati 6.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header: return 20
        case .spacer: return 6
        case .item(let item): return item.etichetta != nil ? 48 : 34
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = PanelRowView()
        if isHeader(row) { rowView.addPanelGround() }
        return rowView
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { isHeader(row) }

    private func isHeader(_ row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = item(at: row) else {
            if case .header(let title) = rows[row] { return CaptionCellView(title) }
            return NSView()
        }
        let identifier = NSUserInterfaceItemIdentifier("ItemCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ItemCellView) ?? {
            let view = ItemCellView(frame: .zero)
            view.identifier = identifier
            return view
        }()
        cell.configure(item, pinKey: shortcuts.shortcut(for: .togglePin)?.display,
                       menuKey: shortcuts.shortcut(for: .actionMenu)?.display)
        cell.onPin = { [weak self] in self?.togglePinSelected() }
        cell.onMore = { [weak self] in self?.showActionMenu() }
        return cell
    }
}
