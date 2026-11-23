import Foundation

struct ClipItem: Codable, Equatable {
    let id: UUID
    var text: String
    var date: Date
    /// Etichetta: testo breve facoltativo, mai vuoto (vedi `HistoryStore.normalize`).
    var etichetta: String? = nil
    /// Elemento fissato: fuori dal limite e da ogni eliminazione automatica o in blocco.
    var fissato = false
}

extension ClipItem {
    // I campi nuovi sono facoltativi: gli history.json delle versioni precedenti si caricano interi.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        etichetta = try c.decodeIfPresent(String.self, forKey: .etichetta)
        fissato = try c.decodeIfPresent(Bool.self, forKey: .fissato) ?? false
    }
}

/// Ricerca su testo ed Etichetta, senza distinguere maiuscole e accenti.
/// Restituisce Fissati e Recenti, ciascuno nell'ordine dello storico.
func searchItems(_ items: [ClipItem], query: String) -> (fissati: [ClipItem], recenti: [ClipItem]) {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    let matches = query.isEmpty ? items : items.filter {
        $0.text.range(of: query, options: options) != nil
            || $0.etichetta?.range(of: query, options: options) != nil
    }
    return (matches.filter(\.fissato), matches.filter { !$0.fissato })
}

/// Storico degli elementi copiati. L'elemento 0 e' il piu' recente.
final class HistoryStore {
    private(set) var items: [ClipItem] = []
    var onChange: (() -> Void)?
    /// Limite dei non fissati: i fissati non contano.
    let maxItems = 100

    private let fileURL: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Copista", isDirectory: true).appendingPathComponent("history.json")
    }

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        load()
    }

    /// Spazi ai bordi tolti; un'etichetta vuota equivale a nessuna.
    static func normalize(_ etichetta: String?) -> String? {
        let trimmed = etichetta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func add(_ text: String) {
        guard !Self.isBlank(text) else { return }
        if let index = items.firstIndex(where: { $0.text == text }) {
            // Ricopia: risale con nuova data, stesso id, Etichetta e pin.
            var existing = items.remove(at: index)
            existing.date = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(id: UUID(), text: text, date: Date()), at: 0)
        }
        var excess = items.filter { !$0.fissato }.count - maxItems
        while excess > 0, let last = items.lastIndex(where: { !$0.fissato }) {
            items.remove(at: last)
            excess -= 1
        }
        changed()
    }

    /// Modifica testo ed Etichetta sul posto: posizione e data restano.
    /// Testo vuoto o di soli spazi: rifiutato, storico invariato (restituisce false).
    /// Se un altro elemento B ha gia' lo stesso testo, resta solo questo, con la sua
    /// Etichetta o in mancanza quella di B, fissato se lo era uno dei due.
    @discardableResult
    func update(id: UUID, text: String, etichetta: String?) -> Bool {
        guard !Self.isBlank(text), let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var item = items[index]
        item.text = text
        item.etichetta = Self.normalize(etichetta)
        for other in items where other.id != id && other.text == text {
            item.etichetta = item.etichetta ?? other.etichetta
            item.fissato = item.fissato || other.fissato
        }
        items[index] = item
        items.removeAll { $0.id != id && $0.text == text }
        changed()
        return true
    }

    func setEtichetta(id: UUID, _ etichetta: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].etichetta = Self.normalize(etichetta)
        changed()
    }

    func setFissato(ids: Set<UUID>, _ fissato: Bool) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].fissato = fissato
        }
        changed()
    }

    /// Fissa/Sfissa: se almeno uno non e' fissato li fissa tutti, altrimenti li sfissa tutti.
    func togglePin(ids: Set<UUID>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        setFissato(ids: ids, selected.contains { !$0.fissato })
    }

    /// Elimina solo i non fissati. Restituisce gli id effettivamente rimossi.
    @discardableResult
    func remove(ids: Set<UUID>) -> Set<UUID> {
        let removed = Set(items.filter { ids.contains($0.id) && !$0.fissato }.map(\.id))
        guard !removed.isEmpty else { return [] }
        items.removeAll { removed.contains($0.id) }
        changed()
        return removed
    }

    /// Svuota tranne i fissati. Restituisce quanti elementi ha rimosso.
    @discardableResult
    func clear() -> Int {
        removeAll { !$0.fissato }
    }

    /// Tiene gli ultimi `count` non fissati, piu' tutti i fissati.
    @discardableResult
    func keepLatest(_ count: Int) -> Int {
        let keep = Set(items.filter { !$0.fissato }.prefix(count).map(\.id))
        return removeAll { !$0.fissato && !keep.contains($0.id) }
    }

    @discardableResult
    func removeOlder(than interval: TimeInterval) -> Int {
        let limit = Date().addingTimeInterval(-interval)
        return removeAll { !$0.fissato && $0.date < limit }
    }

    private func removeAll(where shouldRemove: (ClipItem) -> Bool) -> Int {
        let before = items.count
        items.removeAll(where: shouldRemove)
        let removed = before - items.count
        if removed > 0 { changed() }
        return removed
    }

    private func changed() {
        save()
        onChange?()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // Solo l'utente corrente puo' leggere il file.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
