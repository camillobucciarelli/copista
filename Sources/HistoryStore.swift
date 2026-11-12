import Foundation

struct ClipItem: Codable, Equatable {
    let id: UUID
    let text: String
    var date: Date
}

/// Storico degli elementi copiati. L'elemento 0 e' il piu' recente.
final class HistoryStore {
    private(set) var items: [ClipItem] = []
    var onChange: (() -> Void)?
    let maxItems = 100

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Copista", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ text: String) {
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.date = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(id: UUID(), text: text, date: Date()), at: 0)
        }
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        changed()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        changed()
    }

    func clear() {
        items.removeAll()
        changed()
    }

    func keepLatest(_ count: Int) {
        guard items.count > count else { return }
        items.removeLast(items.count - count)
        changed()
    }

    func removeOlder(than interval: TimeInterval) {
        let limit = Date().addingTimeInterval(-interval)
        items.removeAll { $0.date < limit }
        changed()
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
