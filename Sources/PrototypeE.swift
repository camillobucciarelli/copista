import AppKit

// PROTOTYPE (#19) variante E "Proposta design": pannello a se', dai mockup
// Proposta-lista / Proposta-azioni / Proposta-modifica. Solo colori semantici:
// segue chiaro/scuro del sistema anche a pannello aperto.

// MARK: - Colori semantici (i bianchi rgba del mockup)

private enum EColor {
    /// rgba(255,255,255,0.08): riempimento di campi e tasti.
    static var fill: NSColor {
        if #available(macOS 14.0, *) { return .quaternarySystemFill }
        return NSColor.labelColor.withAlphaComponent(0.06)
    }
    /// rgba(255,255,255,0.14): pulsante secondario.
    static var strongFill: NSColor {
        if #available(macOS 14.0, *) { return .tertiarySystemFill }
        return NSColor.labelColor.withAlphaComponent(0.1)
    }
    /// Testo e icone sopra l'evidenziazione d'accento.
    static var onAccent: NSColor { .alternateSelectedControlTextColor }
}

// MARK: - Viste di base

/// Vista con sfondo, bordo e raggio risolti all'aspetto corrente (si aggiorna da sola).
class FillView: NSView {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var border: NSColor? { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }

    init(fill: NSColor? = nil, border: NSColor? = nil, radius: CGFloat = 0) {
        super.init(frame: .zero)
        wantsLayer = true
        self.fill = fill
        self.border = border
        self.radius = radius
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill?.cgColor
            layer?.borderColor = border?.cgColor
        }
        layer?.borderWidth = border == nil ? 0 : 1
        layer?.cornerRadius = radius
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Tasto stile <kbd>: 11pt, padding 1×5, raggio 4, bordo sottile.
private func keycap(_ text: String, filled: Bool) -> NSView {
    let box = FillView(fill: filled ? EColor.fill : nil, border: .separatorColor, radius: 4)
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11)
    label.textColor = filled ? .labelColor : .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(label)
    NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 5),
        label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5),
        label.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
        label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1),
    ])
    return box
}

private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                  color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
}

/// Pulsante a pillola (Annulla / Salva) e pulsante icona 22×22 delle righe.
private final class PillButton: FillView {
    let button = NSButton()
    init(title: String, symbol: String? = nil, fill: NSColor?, titleColor: NSColor, weight: NSFont.Weight = .regular,
         padding: CGFloat, height: CGFloat, radius: CGFloat, target: AnyObject, action: Selector) {
        super.init(fill: fill, radius: radius)
        button.isBordered = false
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = titleColor
            button.title = ""
        } else {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: weight), .foregroundColor: titleColor,
            ])
        }
        addSubview(button)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
        if symbol != nil {   // quadrato height×height, immagine centrata
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: height),
                button.widthAnchor.constraint(equalTo: widthAnchor),
                button.heightAnchor.constraint(equalTo: heightAnchor),
            ])
        } else {
            widthAnchor.constraint(equalTo: button.widthAnchor, constant: padding * 2).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }
}

/// La riga selezionata: accento, raggio 6, margine 10 ai lati; sempre "in evidenza"
/// (testo bianco) anche col fuoco nel campo di ricerca.
private final class ERowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 0), xRadius: 6, yRadius: 6).fill()
    }
}

private func shortName(_ item: ClipItem) -> String {
    if let label = item.etichetta { return label }
    let line = preview(item.text)
    return line.count > 40 ? String(line.prefix(40)) + "…" : line
}

private func preview(_ text: String) -> String {
    String(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ").prefix(200))
}

/// Intestazione di sezione: 10pt semibold, maiuscolo, spaziatura .06em, secondario, rientro 18.
private final class ECaptionView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    init(_ title: String) {
        super.init(frame: .zero)
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

// MARK: - Riga

final class ECellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let previewLabel = NSTextField(labelWithString: "")
    let pinState = NSImageView()
    fileprivate var pinButton: PillButton!
    fileprivate var moreButton: PillButton!
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

        pinState.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Fissato")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        pinState.imageScaling = .scaleProportionallyDown
        pinState.setAccessibilityLabel("Fissato")
        pinButton = PillButton(title: "Fissa", symbol: "pin", fill: EColor.onAccent.withAlphaComponent(0.18),
                               titleColor: EColor.onAccent, padding: 0, height: 22, radius: 5,
                               target: self, action: #selector(pinClicked))
        moreButton = PillButton(title: "Altre azioni", symbol: "ellipsis", fill: EColor.onAccent.withAlphaComponent(0.18),
                                titleColor: EColor.onAccent, padding: 0, height: 22, radius: 5,
                                target: self, action: #selector(moreClicked))

        let texts = NSStackView(views: [titleLabel, previewLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 0
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Contenitore a destra, largo fisso (22 + 6 + 22), uguale per ogni riga:
        // glifo di stato e pulsanti condividono lo stesso bordo destro.
        let buttons = NSStackView(views: [pinButton, moreButton])
        buttons.spacing = 6
        let trailing = NSView()
        for view in [texts, trailing, pinState, buttons] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        trailing.addSubview(pinState)
        trailing.addSubview(buttons)
        addSubview(texts)
        addSubview(trailing)
        textField = previewLabel
        // margine riga 10 + padding 8 a sinistra, 10 + 6 a destra
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
            // il glifo sta centrato nello stesso quadrato 22×22 dell'ultimo pulsante
            pinState.centerXAnchor.constraint(equalTo: trailing.trailingAnchor, constant: -11),
            pinState.centerYAnchor.constraint(equalTo: trailing.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    func configure(_ item: ClipItem) {
        fissato = item.fissato
        hasTitle = item.etichetta != nil
        titleLabel.isHidden = !hasTitle
        titleLabel.stringValue = item.etichetta ?? ""
        previewLabel.stringValue = preview(item.text)
        previewLabel.font = .systemFont(ofSize: hasTitle ? 11 : 13)
        toolTip = String(item.text.prefix(600))
        let name = shortName(item)
        pinButton.button.image = NSImage(systemSymbolName: fissato ? "pin.fill" : "pin", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        pinButton.button.toolTip = fissato ? "Sfissa (⌘P)" : "Fissa (⌘P)"
        pinButton.button.setAccessibilityLabel("\(fissato ? "Sfissa" : "Fissa") \(name)")
        moreButton.button.toolTip = "Azioni (⌘K)"
        moreButton.button.setAccessibilityLabel("Altre azioni per \(name)")
        refresh()
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { refresh() } }

    private func refresh() {
        let selected = (superview as? NSTableRowView)?.isSelected ?? false
        pinButton.isHidden = !selected        // pulsanti solo sulla riga selezionata
        moreButton.isHidden = !selected
        pinState.isHidden = selected || !fissato
        let onAccent = backgroundStyle == .emphasized
        titleLabel.textColor = onAccent ? EColor.onAccent : .labelColor
        previewLabel.textColor = onAccent
            ? EColor.onAccent.withAlphaComponent(hasTitle ? 0.85 : 1)
            : (hasTitle ? .secondaryLabelColor : .labelColor)
        pinState.contentTintColor = .controlAccentColor
    }

    @objc private func pinClicked() { onPin?() }
    @objc private func moreClicked() { onMore?() }
}

// MARK: - Pannello

final class PrototypeEController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate,
                                  NSTextViewDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store: HistoryStore
    private let panel: KeyPanel
    private let background = NSVisualEffectView()
    private let searchBox = FillView(fill: EColor.fill, radius: 7)
    private let search = NSTextField(string: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = text("", size: 13, color: .secondaryLabelColor)
    private let footer = NSView()
    private var footerKeys: NSStackView!
    private let footerFlash = text("", size: 11, color: .labelColor)
    private let bubble = NSVisualEffectView()
    private let bubbleLabel = text("", size: 11)
    private let protoState = text("", size: 10, color: .secondaryLabelColor)
    private let contextMenu = NSMenu()
    private var rows: [PanelRow] = []
    private var flashReset: DispatchWorkItem?
    private var bubbleReset: DispatchWorkItem?
    private var keyMonitor: Any?
    private var responderObservation: NSKeyValueObservation?

    // Editor a scheda
    private let card = NSVisualEffectView()
    private var cardTop: NSLayoutConstraint!
    private let labelBox = FillView(fill: EColor.fill, border: .separatorColor, radius: 6)
    private let cardLabel = NSTextField(string: "")
    private let textBox = FillView(fill: EColor.fill, border: .separatorColor, radius: 6)
    private let cardText = NSTextView()
    private let cardCount = text("", size: 11, color: .secondaryLabelColor)
    private var cardButtons: NSStackView!
    private var cardConfirm: NSStackView!
    private var editing: ClipItem?

    var onLeave: ((PrototypeVariant) -> Void)?

    init(store: HistoryStore) {
        self.store = store
        // 400 di contenuto come nei mockup + 46 di barra PROTOTIPO
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 446),
                         styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        buildUI()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        // Bordo d'accento sul campo che ha il fuoco (come nel mockup dell'editor).
        responderObservation = panel.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            self?.updateFocusBorders()
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

        background.material = .popover   // adattivo: segue chiaro/scuro (.hudWindow e' solo scuro)
        background.blendingMode = .behindWindow
        background.state = .active
        panel.contentView = background

        // Ricerca: 28 alto, raggio 7, riempimento, lente 14, testo 13
        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))!)
        glass.imageScaling = .scaleProportionallyDown
        glass.contentTintColor = .secondaryLabelColor
        search.placeholderString = "Cerca testo o etichetta"
        search.setAccessibilityLabel("Cerca negli appunti")
        search.font = .systemFont(ofSize: 13)
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

        // Lista: niente stile "inset" di sistema, margini e raggi come il mockup
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
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
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byTruncatingTail

        // Pie' di pagina: 30 alto, padding 14, filo superiore, tasti
        let rule = FillView(fill: .separatorColor)
        let left = NSStackView(views: [keycap("↩", filled: true), text("copia", size: 11, color: .secondaryLabelColor)])
        let right = NSStackView(views: [keycap("⌘K", filled: true), text("azioni", size: 11, color: .secondaryLabelColor)])
        left.spacing = 4
        right.spacing = 4
        footerKeys = left
        footerFlash.isHidden = true
        for view in [rule, left, right, footerFlash] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            rule.topAnchor.constraint(equalTo: footer.topAnchor),
            rule.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            left.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footerFlash.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            footerFlash.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        // Fumetto "Fissato: sfissa (⌘P)…": raggio 6, padding 5×8, 11pt
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

        // Barra PROTOTIPO
        let protoBox = FillView(fill: NSColor.systemOrange.withAlphaComponent(0.22))
        let protoTitle = text("PROTOTIPO — variante E (Proposta design)", size: 11, weight: .bold)
        protoState.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
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

        for view in [searchBox, scrollView, emptyLabel, footer, protoBox, card, bubble] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        bubble.translatesAutoresizingMaskIntoConstraints = true   // posizionato a mano sotto la riga
        cardTop = card.topAnchor.constraint(equalTo: background.topAnchor, constant: -400)

        NSLayoutConstraint.activate([
            searchBox.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            searchBox.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            searchBox.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            searchBox.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: 30),
            footer.bottomAnchor.constraint(equalTo: protoBox.topAnchor),

            protoBox.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            protoBox.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            protoBox.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            protoStack.leadingAnchor.constraint(equalTo: protoBox.leadingAnchor, constant: 14),
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

    private func caption(_ string: String) -> NSTextField {
        text(string, size: 11, color: .secondaryLabelColor)
    }

    /// Scheda di modifica: inset 10, raggio 10, padding 14/16/12.
    private func buildCard() {
        card.material = .menu
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        card.isHidden = true
        let cardBorder = FillView(fill: EColor.strongFill, border: .separatorColor, radius: 10)   // velo per staccarla dalla lista

        let heading = text("Modifica elemento", size: 13, weight: .semibold)

        // Etichetta: campo 26 alto, raggio 6, padding 0×8
        cardLabel.font = .systemFont(ofSize: 13)
        cardLabel.placeholderString = "facoltativa"
        cardLabel.isBordered = false
        cardLabel.drawsBackground = false
        cardLabel.focusRingType = .none
        cardLabel.cell?.isScrollable = true
        cardLabel.cell?.wraps = false
        cardLabel.translatesAutoresizingMaskIntoConstraints = false
        labelBox.addSubview(cardLabel)
        NSLayoutConstraint.activate([
            labelBox.heightAnchor.constraint(equalToConstant: 26),
            cardLabel.leadingAnchor.constraint(equalTo: labelBox.leadingAnchor, constant: 8),
            cardLabel.trailingAnchor.constraint(equalTo: labelBox.trailingAnchor, constant: -8),
            cardLabel.centerYAnchor.constraint(equalTo: labelBox.centerYAnchor),
        ])

        // Testo: 84 alto (4 righe da 18), raggio 6, padding 6×8, scorre
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        cardText.isRichText = false
        cardText.allowsUndo = true
        cardText.font = .systemFont(ofSize: 13)
        cardText.textColor = .labelColor
        cardText.defaultParagraphStyle = paragraph
        cardText.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph,
                                     .foregroundColor: NSColor.labelColor]
        cardText.drawsBackground = false
        cardText.focusRingType = .none
        cardText.textContainerInset = NSSize(width: 8, height: 6)
        cardText.textContainer?.lineFragmentPadding = 0
        cardText.isVerticallyResizable = true
        cardText.autoresizingMask = .width
        cardText.textContainer?.widthTracksTextView = true
        cardText.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = cardText
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textBox.addSubview(scroll)
        NSLayoutConstraint.activate([
            textBox.heightAnchor.constraint(equalToConstant: 84),
            scroll.topAnchor.constraint(equalTo: textBox.topAnchor, constant: 1),
            scroll.bottomAnchor.constraint(equalTo: textBox.bottomAnchor, constant: -1),
            scroll.leadingAnchor.constraint(equalTo: textBox.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: textBox.trailingAnchor, constant: -1),
        ])

        // Pulsanti a destra, ciascuno col suo tasto sotto (gap 3), distanza 10
        let cancel = PillButton(title: "Annulla", fill: EColor.strongFill, titleColor: .labelColor,
                                padding: 14, height: 24, radius: 6, target: self, action: #selector(escInEditor))
        let save = PillButton(title: "Salva", fill: .controlAccentColor, titleColor: EColor.onAccent, weight: .semibold,
                              padding: 18, height: 24, radius: 6, target: self, action: #selector(saveEdit))
        func withKey(_ button: NSView, _ key: String) -> NSStackView {
            let stack = NSStackView(views: [button, keycap(key, filled: false)])
            stack.orientation = .vertical
            stack.spacing = 3
            return stack
        }
        cardButtons = NSStackView(views: [NSView(), withKey(cancel, "esc"), withKey(save, "⌘↩")])
        cardButtons.spacing = 10
        cardButtons.alignment = .top

        let question = text("Scartare le modifiche?", size: 13, weight: .medium)
        let keep = PillButton(title: "Continua a modificare", fill: EColor.strongFill, titleColor: .labelColor,
                              padding: 14, height: 24, radius: 6, target: self, action: #selector(keepEditing))
        let discard = PillButton(title: "Scarta", fill: .systemRed, titleColor: EColor.onAccent, weight: .semibold,
                                 padding: 18, height: 24, radius: 6, target: self, action: #selector(discardEdit))
        cardConfirm = NSStackView(views: [question, NSView(), keep, discard])
        cardConfirm.spacing = 10
        cardConfirm.isHidden = true

        // Nota in fondo con filo superiore
        let noteRule = FillView(fill: .separatorColor)
        let note = caption("Con modifiche non salvate, esc chiede conferma.")

        let stack = NSStackView(views: [heading, caption("Etichetta"), labelBox, caption("Testo"), textBox, cardCount,
                                        cardButtons, cardConfirm, noteRule, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(10, after: labelBox)
        stack.setCustomSpacing(10, after: cardCount)
        stack.setCustomSpacing(10, after: cardButtons)
        stack.setCustomSpacing(10, after: cardConfirm)
        stack.setCustomSpacing(8, after: noteRule)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardBorder.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardBorder)   // sotto il contenuto, cosi' non intercetta i clic
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            labelBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            textBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cardButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cardConfirm.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noteRule.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noteRule.heightAnchor.constraint(equalToConstant: 1),
            cardBorder.topAnchor.constraint(equalTo: card.topAnchor),
            cardBorder.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardBorder.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardBorder.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
    }

    private func updateFocusBorders() {
        let responder = panel.firstResponder
        let labelFocused = (responder as? NSTextView)?.delegate === cardLabel
        labelBox.border = labelFocused ? NSColor.controlAccentColor.withAlphaComponent(0.8) : .separatorColor
        textBox.border = responder === cardText ? NSColor.controlAccentColor.withAlphaComponent(0.8) : .separatorColor
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
            rows = (pinned.isEmpty ? [] : [.header("Fissati")] + pinned)
                + (recent.isEmpty ? [] : [.header("Recenti")] + recent)
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
        guard (obj.object as? NSTextField) === search else { return }
        reload(keeping: nil, fallback: 0)
    }

    // MARK: - Azioni

    /// Messaggio di 2 secondi al posto di "↩ copia" nel pie' di pagina.
    private func flash(_ message: String) {
        flashReset?.cancel()
        footerFlash.stringValue = message
        footerFlash.isHidden = false
        footerKeys.isHidden = true
        let reset = DispatchWorkItem { [weak self] in
            self?.footerFlash.isHidden = true
            self?.footerKeys.isHidden = false
        }
        flashReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
    }

    /// Fumetto sotto la riga selezionata, a 22 dal bordo destro, per 2 secondi.
    private func showBubble(_ message: String) {
        bubbleReset?.cancel()
        bubbleLabel.stringValue = message
        let size = bubble.fittingSize
        var rowRect = tableView.rect(ofRow: max(tableView.selectedRow, 0))
        rowRect = tableView.convert(rowRect, to: background)
        let y = background.isFlipped ? rowRect.maxY + 2 : rowRect.minY - size.height - 2
        bubble.frame = NSRect(x: background.bounds.width - 22 - size.width, y: y, width: size.width, height: size.height)
        bubble.isHidden = false
        let reset = DispatchWorkItem { [weak self] in self?.bubble.isHidden = true }
        bubbleReset = reset
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
            showBubble("Fissato: sfissa (⌘P) per poterlo eliminare")
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
        if delete.isEnabled {   // rosso come nel mockup
            delete.attributedTitle = NSAttributedString(string: "Elimina", attributes: [
                .foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0),
            ])
        } else {
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
        menu.popUp(positioning: nil, at: NSPoint(x: rect.maxX - 14 - 240, y: rect.maxY), in: tableView)
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
        case 36, 76:
            if let i = selected { copy(i) }
            return nil
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
        bubble.isHidden = true
        cardLabel.stringValue = item.etichetta ?? ""
        cardText.string = item.text
        cardText.setSelectedRange(NSRange(location: 0, length: 0))
        cardText.scrollToBeginningOfDocument(nil)
        updateCount()
        cardConfirm.isHidden = true
        cardButtons.isHidden = false
        card.isHidden = false
        background.layoutSubtreeIfNeeded()
        cardTop.constant = -card.frame.height - 10
        background.layoutSubtreeIfNeeded()
        setDimmed(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            cardTop.animator().constant = 10
        }
        panel.makeFirstResponder(cardText)
    }

    /// Dietro la scheda la lista resta visibile al 35%.
    private func setDimmed(_ dimmed: Bool) {
        for view in [searchBox, scrollView, footer, emptyLabel] as [NSView] {
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        bubble.isHidden = true
        updateState()
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.filteredIndexSet { item(at: $0) != nil }
    }

    /// Didascalie: margine 4 sopra (10 dalla seconda), 12 di testo, 4 sotto. Righe 44 / 30.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = item(at: row) else { return row == 0 ? 20 : 26 }
        return item.etichetta != nil ? 44 : 30
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ERowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = item(at: row) else {
            if case .header(let title) = rows[row] { return ECaptionView(title) }
            return nil
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
