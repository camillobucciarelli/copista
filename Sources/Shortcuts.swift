import Foundation

// Regole delle scorciatoie: logica pura (solo Foundation), testata in Tests/.

/// Una combinazione: tasto fisico (keyCode) + modificatori. `key` e' il carattere
/// prodotto dal tasto (minuscolo) o il nome di un tasto speciale ("esc", "↩", "F5").
struct Shortcut: Codable, Equatable {
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)
    }

    var keyCode: UInt16
    var modifiers: Modifiers
    var key: String

    /// Invio del tastierino (76) e ↩ (36) sono lo stesso tasto.
    var normalizedKeyCode: UInt16 { keyCode == 76 ? 36 : keyCode }

    /// Due combinazioni sono la stessa se tasto e modificatori coincidono.
    /// Stessa equivalenza usata per riconoscere i tasti premuti nel pannello.
    func sameKeys(as other: Shortcut) -> Bool {
        normalizedKeyCode == other.normalizedKeyCode && modifiers == other.modifiers
    }

    /// Nell'ordine di macOS: ⌃⌥⇧⌘ poi il tasto.
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (key.count == 1 ? key.uppercased() : key)
    }

    /// Tasti speciali che non producono testo, per keyCode.
    static let specialKeys: [UInt16: String] = {
        var keys: [UInt16: String] = [
            36: "↩", 76: "⌤", 48: "⇥", 49: "␣", 51: "⌫", 117: "⌦", 53: "esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        ]
        let fKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for (i, code) in fKeys.enumerated() { keys[code] = "F\(i + 1)" }
        return keys
    }()

    /// Costruisce la combinazione da un tasto premuto.
    static func make(keyCode: UInt16, modifiers: Modifiers, characters: String?) -> Shortcut? {
        if let name = specialKeys[keyCode] { return Shortcut(keyCode: keyCode, modifiers: modifiers, key: name) }
        guard let chars = characters?.lowercased(), chars.count == 1 else { return nil }
        return Shortcut(keyCode: keyCode, modifiers: modifiers, key: chars)
    }

    /// Carattere per il key equivalent di un NSMenuItem.
    var keyEquivalent: String {
        let functionKeys: [String: Int] = ["←": 0xF702, "→": 0xF703, "↑": 0xF700, "↓": 0xF701,
                                           "↖": 0xF729, "↘": 0xF72B, "⇞": 0xF72C, "⇟": 0xF72D, "⌦": 0xF728]
        switch key {
        case "↩", "⌤": return "\r"
        case "⇥": return "\t"
        case "␣": return " "
        case "⌫": return "\u{8}"
        case "esc": return "\u{1b}"
        default:
            if let code = functionKeys[key] { return String(UnicodeScalar(code)!) }
            if key.hasPrefix("F"), let n = Int(key.dropFirst()) { return String(UnicodeScalar(0xF703 + n)!) }
            return key
        }
    }
}

enum ShortcutScope { case global, panel, sheet }

enum ShortcutAction: String, CaseIterable, Codable {
    case openHistory
    case copy, edit, togglePin, delete, actionMenu, closePanel
    case save, cancelEdit

    var scope: ShortcutScope {
        switch self {
        case .openHistory: return .global
        case .save, .cancelEdit: return .sheet
        default: return .panel
        }
    }

    var title: String { L("shortcut.\(rawValue)") }

    static let defaults: [ShortcutAction: Shortcut?] = [
        .openHistory: Shortcut(keyCode: 9, modifiers: [.command, .shift], key: "v"),
        .copy: Shortcut(keyCode: 36, modifiers: [], key: "↩"),
        .edit: Shortcut(keyCode: 14, modifiers: .command, key: "e"),
        .togglePin: Shortcut(keyCode: 35, modifiers: .command, key: "p"),
        .delete: Shortcut(keyCode: 51, modifiers: [], key: "⌫"),
        .actionMenu: Shortcut(keyCode: 40, modifiers: .command, key: "k"),
        .closePanel: Shortcut(keyCode: 53, modifiers: [], key: "esc"),
        .save: Shortcut(keyCode: 36, modifiers: .command, key: "↩"),
        .cancelEdit: Shortcut(keyCode: 53, modifiers: [], key: "esc"),
    ]
}

enum ShortcutRejection: Equatable {
    /// ⌘C/V/X/Z/A/Q e ⌘, servono al sistema.
    case reserved
    /// La globale richiede ⌘, ⌥ o ⌃.
    case needsModifier
    /// Nel pannello e nel foglio un tasto che scrive testo, senza ⌘/⌥/⌃, serve alla ricerca o al testo.
    case typesText
    /// Frecce e Tab restano fisse (navigazione e selezione).
    case fixedKey
    /// Gia' usata da un'altra azione dello stesso ambito.
    case conflict(ShortcutAction)

    var message: String {
        switch self {
        case .reserved: return L("shortcut.reason.reserved")
        case .needsModifier: return L("shortcut.reason.needsModifier")
        case .typesText: return L("shortcut.reason.typesText")
        case .fixedKey: return L("shortcut.reason.fixedKey")
        case .conflict(let other): return String(format: L("shortcut.reason.conflict"), other.title)
        }
    }
}

/// `nil` = ammessa. "Nessuna" (shortcut nil) e' sempre ammessa.
func validate(_ shortcut: Shortcut?, for action: ShortcutAction,
              in current: [ShortcutAction: Shortcut?]) -> ShortcutRejection? {
    guard let shortcut else { return nil }
    let strong: Shortcut.Modifiers = [.command, .option, .control]
    let hasStrong = !shortcut.modifiers.isDisjoint(with: strong)

    if shortcut.modifiers == .command, ["c", "v", "x", "z", "a", "q", ","].contains(shortcut.key) {
        return .reserved
    }
    switch action.scope {
    case .global:
        if !hasStrong { return .needsModifier }
    case .panel, .sheet:
        if ["←", "→", "↑", "↓", "⇥"].contains(shortcut.key), !hasStrong { return .fixedKey }
        let producesText = Shortcut.specialKeys[shortcut.keyCode] == nil || shortcut.keyCode == 49   // 49 = spazio
        if producesText, !hasStrong { return .typesText }
        // Nel foglio ↩ va a capo.
        if action.scope == .sheet, ["↩", "⌤"].contains(shortcut.key), !hasStrong { return .typesText }
    }
    for other in ShortcutAction.allCases where other != action && other.scope == action.scope {
        if let used = current[other] ?? nil, used.sameKeys(as: shortcut) { return .conflict(other) }
    }
    return nil
}

/// Scorciatoie configurate, in UserDefaults. Chiave assente = predefinita;
/// dato vuoto = "Nessuna".
final class ShortcutSettings {
    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard let data = defaults.data(forKey: key(action)) else { return ShortcutAction.defaults[action] ?? nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    var current: [ShortcutAction: Shortcut?] {
        Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, shortcut(for: $0)) })
    }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: key(action))
        onChange?()
    }

    func reset(_ action: ShortcutAction) {
        defaults.removeObject(forKey: key(action))
        onChange?()
    }
}
