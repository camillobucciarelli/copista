import AppKit

// PROTOTYPE (#19): come mostra il pannello etichette ed Elementi fissati?
// Avvio con `-variant a|b|c`. Senza argomento l'app si comporta come sempre.

enum PrototypeVariant: String, CaseIterable {
    case a, b, c, d

    var name: String {
        switch self {
        case .a: return "Sezione in cima"
        case .b: return "Al loro posto"
        case .c: return "Schede"
        case .d: return "Scelta"
        }
    }

    /// nil = app reale. `-variant x` arriva nelle UserDefaults (dominio argomenti).
    static let atLaunch: PrototypeVariant? = {
        guard let raw = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["variant"] as? String
        else { return nil }
        return PrototypeVariant(rawValue: raw.lowercased()) ?? .a
    }()

    /// Simboli matita da provare per "Modifica" (variante D); solo quelli presenti su questo macOS.
    static let editSymbols: [String] = [
        "pencil.line", "square.and.pencil", "pencil.circle", "pencil.tip",
        "pencil.and.outline", "pencil.and.list.clipboard",
    ].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    func shifted(by delta: Int) -> PrototypeVariant {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + delta + all.count) % all.count]
    }

    static func seed() -> [ClipItem] {
        let now = Date()
        let raw: [(String, String?, Bool)] = [
            ("Ci vediamo alle 18 davanti alla stazione", nil, false),
            ("IT60 X054 2811 1010 0000 0123 456", "IBAN", true),
            ("https://github.com/camillobucciarelli/copista/issues/19", nil, false),
            ("Via Roma 12\n20121 Milano MI\nItalia", "Indirizzo casa", true),
            ("let x = items.filter { !$0.fissato }.count", nil, false),
            ("Cordiali saluti,\nCamillo Bucciarelli\nSviluppatore\n+39 333 123 4567", "Firma email", true),
            ("ok", nil, false),
            ("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.", nil, false),
            ("ssh deploy@192.168.1.40 -p 2222", "Server di casa", false),
            ("Codice fiscale: BCCCLL80A01H501U", "Codice fiscale", false),
            ("SELECT *\nFROM elementi\nWHERE fissato = 1\nORDER BY data DESC;", nil, true),
            ("Grazie mille!", nil, false),
            ("Riunione spostata a giovedì, stessa ora. Porta il portatile e il caricatore, la sala non ha prese vicino al tavolo.", nil, false),
            ("4 x 250 g farina, 2 uova, 1 bustina di lievito", "Ricetta torta", false),
            ("npm run build && npm test", nil, false),
        ]
        return raw.enumerated().map { i, r in
            var item = ClipItem(id: UUID(), text: r.0, date: now.addingTimeInterval(Double(-i * 600)))
            item.etichetta = r.1
            item.fissato = r.2
            return item
        }
    }
}
