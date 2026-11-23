import Foundation

// Test della logica pura (Storico e regole delle scorciatoie), senza framework.
// Si lancia con ./test.sh.

var passed = 0
var failed = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        print("FALLITO (riga \(line)): \(message)")
    }
}

let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("copista-tests-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

func freshStore() -> HistoryStore {
    HistoryStore(fileURL: tempDir.appendingPathComponent("\(UUID().uuidString).json"))
}

func id(_ store: HistoryStore, _ text: String) -> UUID {
    store.items.first { $0.text == text }!.id
}

// MARK: - Seam 1: Storico

do { // Etichetta normalizzata e rimossa
    let store = freshStore()
    store.add("DE89 3704 0044")
    let a = id(store, "DE89 3704 0044")
    store.setEtichetta(id: a, "  IBAN  ")
    check(store.items[0].etichetta == "IBAN", "etichetta senza spazi ai bordi")
    store.setEtichetta(id: a, "   \n ")
    check(store.items[0].etichetta == nil, "etichetta di soli spazi = nessuna")
    store.setEtichetta(id: a, "IBAN")
    store.setEtichetta(id: a, "")
    check(store.items[0].etichetta == nil, "etichetta vuota la rimuove")
}

do { // Fissa/sfissa, anche su selezione mista
    let store = freshStore()
    store.add("a"); store.add("b")
    let a = id(store, "a"), b = id(store, "b")
    store.togglePin(ids: [a])
    check(store.items.first { $0.id == a }!.fissato, "fissa uno")
    store.togglePin(ids: [a, b])
    check(store.items.allSatisfy(\.fissato), "selezione mista: li fissa tutti")
    store.togglePin(ids: [a, b])
    check(store.items.allSatisfy { !$0.fissato }, "tutti fissati: li sfissa tutti")
}

do { // Limite 100 che conta e rimuove solo i non fissati
    let store = freshStore()
    store.add("fisso-vecchio")
    store.togglePin(ids: [id(store, "fisso-vecchio")])
    for i in 0..<105 { store.add("t\(i)") }
    let recenti = store.items.filter { !$0.fissato }
    check(recenti.count == 100, "100 non fissati, trovati \(recenti.count)")
    check(store.items.contains { $0.text == "fisso-vecchio" }, "il fissato più vecchio resta")
    check(!store.items.contains { $0.text == "t0" }, "il non fissato più vecchio esce")
    check(store.items.contains { $0.text == "t104" }, "il più recente c'è")
}

do { // clear / keepLatest / removeOlder risparmiano i fissati
    let store = freshStore()
    for t in ["p", "x", "y", "z"] { store.add(t) }
    store.togglePin(ids: [id(store, "p")])
    store.clear()
    check(store.items.map(\.text) == ["p"], "clear tiene i fissati")

    for t in ["a", "b", "c"] { store.add(t) }
    store.keepLatest(2)
    check(store.items.map(\.text) == ["c", "b", "p"], "keepLatest conta solo i non fissati: \(store.items.map(\.text))")

    store.removeOlder(than: -1) // tutto è "più vecchio" di un istante nel futuro
    check(store.items.map(\.text) == ["p"], "removeOlder tiene i fissati")
}

do { // remove salta i fissati e restituisce gli id rimossi
    let store = freshStore()
    store.add("a"); store.add("b")
    let a = id(store, "a"), b = id(store, "b")
    store.togglePin(ids: [a])
    check(store.remove(ids: [a]).isEmpty, "solo fissati: niente rimosso")
    check(store.items.count == 2, "storico invariato")
    let removed = store.remove(ids: [a, b])
    check(removed == [b], "selezione mista: rimuove solo il non fissato")
    check(store.items.map(\.text) == ["a"], "resta il fissato")
}

do { // Fusione da modifica: Etichetta di A o di B, pin di A o di B
    let store = freshStore()
    store.add("bbb"); store.add("aaa")
    let a = id(store, "aaa"), b = id(store, "bbb")
    store.setEtichetta(id: b, "di B")
    store.togglePin(ids: [b])
    check(store.update(id: a, text: "bbb", etichetta: nil), "update accettato")
    check(store.items.count == 1, "resta un solo elemento")
    let merged = store.items[0]
    check(merged.id == a, "resta A")
    check(merged.etichetta == "di B", "A senza etichetta prende quella di B")
    check(merged.fissato, "fissato perché lo era B")

    let s2 = freshStore()
    s2.add("bbb"); s2.add("aaa")
    let a2 = id(s2, "aaa"), b2 = id(s2, "bbb")
    s2.setEtichetta(id: b2, "di B")
    s2.togglePin(ids: [a2])
    _ = s2.update(id: a2, text: "bbb", etichetta: " di A ")
    check(s2.items.count == 1 && s2.items[0].etichetta == "di A", "A tiene la sua etichetta")
    check(s2.items[0].fissato, "fissato perché lo era A")
}

do { // update con testo vuoto o solo spazi rifiutato, Storico invariato
    let store = freshStore()
    store.add("ciao")
    let a = id(store, "ciao")
    let before = store.items
    check(!store.update(id: a, text: "", etichetta: "x"), "testo vuoto rifiutato")
    check(!store.update(id: a, text: "  \n\t ", etichetta: "x"), "solo spazi rifiutato")
    check(store.items == before, "storico invariato")
    store.add("   ")
    check(store.items == before, "add ignora testo vuoto")
}

do { // Ricopia: stesso id, Etichetta e pin restano, risale in cima
    let store = freshStore()
    store.add("uno"); store.add("due")
    let a = id(store, "uno")
    store.setEtichetta(id: a, "primo")
    store.togglePin(ids: [a])
    store.add("uno")
    check(store.items[0].id == a, "stesso id in cima")
    check(store.items[0].etichetta == "primo" && store.items[0].fissato, "etichetta e pin restano")
    check(store.items.count == 2, "nessun doppione")
}

do { // Ricerca su testo ed Etichetta, case/diacritic-insensitive, fissati prima
    let store = freshStore()
    store.add("Perché no")
    store.add("DE89 3704")
    store.add("altro testo")
    store.add("iban vecchio")
    store.setEtichetta(id: id(store, "DE89 3704"), "IBAN")
    store.togglePin(ids: [id(store, "DE89 3704")])
    let r = search(store.items, query: "iban")
    check(r.fissati.map(\.text) == ["DE89 3704"], "trova per etichetta, maiuscole ignorate")
    check(r.recenti.map(\.text) == ["iban vecchio"], "trova per testo")
    check(search(store.items, query: "PERCHE").recenti.map(\.text) == ["Perché no"], "accenti ignorati")
    let all = search(store.items, query: "  ")
    check(all.fissati.count == 1 && all.recenti.count == 3, "query vuota: tutto, fissati separati")
    check(search(store.items, query: "zzz").fissati.isEmpty && search(store.items, query: "zzz").recenti.isEmpty, "nessun risultato")
}

do { // Salvataggio e ricarica
    let url = tempDir.appendingPathComponent("persist.json")
    let store = HistoryStore(fileURL: url)
    store.add("x"); store.add("y")
    store.setEtichetta(id: id(store, "x"), "ics")
    store.togglePin(ids: [id(store, "x")])
    let reloaded = HistoryStore(fileURL: url)
    check(reloaded.items == store.items, "ricarica identica")
}

do { // Decodifica di un history.json nel formato precedente
    let url = tempDir.appendingPathComponent("old.json")
    let old = """
    [{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"vecchio","date":700000000},
     {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","text":"più vecchio","date":690000000}]
    """
    try! old.data(using: .utf8)!.write(to: url)
    let store = HistoryStore(fileURL: url)
    check(store.items.count == 2, "carica tutti gli elementi")
    check(store.items.allSatisfy { $0.etichetta == nil && !$0.fissato }, "campi nuovi assenti = nessuna etichetta, non fissato")
}

// MARK: - Seam 2: regole delle scorciatoie

let cmd = Shortcut.Modifiers.command, shift = Shortcut.Modifiers.shift

do { // Predefinite valide, esc sia nel pannello sia nel foglio
    let defaults = ShortcutAction.defaults
    for action in ShortcutAction.allCases {
        let r = validate(defaults[action] ?? nil, for: action, in: defaults)
        check(r == nil, "predefinita valida per \(action): \(String(describing: r))")
    }
    check(defaults[.closePanel]??.keyCode == 53 && defaults[.cancelEdit]??.keyCode == 53, "esc nel pannello e nel foglio")
    check(defaults[.openHistory]! == Shortcut(keyCode: 9, modifiers: [.command, .shift], key: "v"), "⌘⇧V globale")
}

do { // Riservate rifiutate in ogni ambito
    for (code, key) in [(8, "c"), (9, "v"), (7, "x"), (6, "z"), (0, "a"), (12, "q"), (43, ",")] {
        let s = Shortcut(keyCode: UInt16(code), modifiers: cmd, key: key)
        for action in [ShortcutAction.openHistory, .edit, .save] {
            check(validate(s, for: action, in: ShortcutAction.defaults) == .reserved, "⌘\(key) riservata per \(action)")
        }
    }
    // Su una tastiera diversa il carattere decide, non la posizione del tasto.
    check(validate(Shortcut(keyCode: 16, modifiers: cmd, key: "z"), for: .edit, in: [:]) == .reserved, "⌘Z su QWERTZ")
    check(validate(Shortcut(keyCode: 6, modifiers: [.command, .shift], key: "z"), for: .edit, in: [:]) == nil, "⌘⇧Z ammessa")
}

do { // Globale senza modificatore rifiutata
    check(validate(Shortcut(keyCode: 96, modifiers: [], key: "F5"), for: .openHistory, in: [:]) == .needsModifier, "F5 da solo")
    check(validate(Shortcut(keyCode: 9, modifiers: shift, key: "v"), for: .openHistory, in: [:]) == .needsModifier, "⇧ non basta")
    check(validate(Shortcut(keyCode: 9, modifiers: .option, key: "v"), for: .openHistory, in: [:]) == nil, "⌥V ammessa")
}

do { // Lettera o numero senza modificatore nel pannello rifiutati
    check(validate(Shortcut(keyCode: 0, modifiers: [], key: "a"), for: .edit, in: [:]) == .typesText, "a nel pannello")
    check(validate(Shortcut(keyCode: 18, modifiers: shift, key: "1"), for: .copy, in: [:]) == .typesText, "⇧1 nel pannello")
    check(validate(Shortcut(keyCode: 0, modifiers: [], key: "a"), for: .save, in: [:]) == .typesText, "a nel foglio")
    check(validate(Shortcut(keyCode: 0, modifiers: .control, key: "a"), for: .edit, in: [:]) == nil, "⌃A nel pannello")
    check(validate(Shortcut(keyCode: 96, modifiers: [], key: "F5"), for: .edit, in: [:]) == nil, "F5 nel pannello")
}

do { // Conflitto nello stesso ambito, con l'azione che la usa
    let s = Shortcut(keyCode: 35, modifiers: cmd, key: "p") // ⌘P = Fissa/Sfissa
    check(validate(s, for: .edit, in: ShortcutAction.defaults) == .conflict(.togglePin), "conflitto con Fissa/Sfissa")
    check(validate(s, for: .togglePin, in: ShortcutAction.defaults) == nil, "la stessa azione non è in conflitto con se stessa")
}

do { // Stessa combinazione in ambiti diversi ammessa
    let esc = Shortcut(keyCode: 53, modifiers: [], key: "esc")
    var current = ShortcutAction.defaults
    current[.closePanel] = esc
    check(validate(esc, for: .cancelEdit, in: current) == nil, "esc in pannello e foglio")
    let cmdE = Shortcut(keyCode: 14, modifiers: cmd, key: "e")
    check(validate(cmdE, for: .save, in: ShortcutAction.defaults) == nil, "⌘E nel foglio anche se usata nel pannello")
    check(validate(Shortcut(keyCode: 9, modifiers: [.command, .shift], key: "v"), for: .copy, in: ShortcutAction.defaults) == nil,
          "⌘⇧V nel pannello anche se globale")
}

do { // "Nessuna" ammessa
    for action in ShortcutAction.allCases {
        check(validate(nil, for: action, in: ShortcutAction.defaults) == nil, "Nessuna per \(action)")
    }
}

do { // Visualizzazione
    check(Shortcut(keyCode: 9, modifiers: [.command, .shift], key: "v").display == "⇧⌘V", "⇧⌘V")
    check(Shortcut(keyCode: 36, modifiers: cmd, key: "↩").display == "⌘↩", "⌘↩")
    check(Shortcut(keyCode: 53, modifiers: [], key: "esc").display == "esc", "esc")
}

print("\(passed) superati, \(failed) falliti")
exit(failed == 0 ? 0 : 1)
