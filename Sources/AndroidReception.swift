import Foundation

/// Ricezione da Android: ogni file di consegna (`text-0.txt`, oppure
/// `text-0 N.txt` quando macOS rinomina un doppione) nella cartella Download
/// diventa un elemento dello storico. Poi il file viene eliminato in modo definitivo.
final class AndroidReception {
    /// Riceve il testo di un file di consegna. Il piu' recente arriva per ultimo.
    var onText: ((String) -> Void)?
    /// Se `true`, i file di consegna restano in Download fino alla ripresa.
    var isPaused = false {
        didSet { if !isPaused { scan() } }
    }

    private(set) var isRunning = false

    private let folder: URL
    private let maxBytes = 1_000_000
    private let namePattern = try! NSRegularExpression(pattern: #"^text-0( \d+)?\.txt$"#)
    private var source: DispatchSourceFileSystemObject?
    private var pendingScan: DispatchWorkItem?
    /// File gia' consegnati la cui eliminazione e' fallita: si riprova solo
    /// l'eliminazione, il testo non torna negli appunti.
    private var delivered: [String: Date] = [:]

    init(folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.folder = folder
    }

    /// Ritorna `false` se l'app non ha accesso alla cartella Download.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        // La lettura della cartella causa la richiesta di permesso di macOS.
        guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil else { return false }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleScan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        isRunning = true
        scan()   // file gia' presenti all'avvio
        return true
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
        isRunning = false
    }

    /// Breve attesa: un file appena apparso puo' essere ancora in scrittura.
    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func scan() {
        guard isRunning, !isPaused else { return }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }

        var files: [(url: URL, date: Date, size: Int)] = []
        for name in names where isDeliveryFileName(name) {
            let url = folder.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  attrs[.type] as? FileAttributeType == .typeRegular else { continue }
            files.append((url, attrs[.modificationDate] as? Date ?? Date(), (attrs[.size] as? Int) ?? 0))
        }
        delivered = delivered.filter { path, _ in files.contains { $0.url.path == path } }

        // Dal piu' vecchio al piu' recente: l'ultimo arrivato diventa l'ultimo copiato.
        for file in files.sorted(by: { $0.date < $1.date }) {
            if delivered[file.url.path] == file.date {
                if (try? fm.removeItem(at: file.url)) != nil { delivered[file.url.path] = nil }
                continue
            }
            guard file.size <= maxBytes,
                  let data = try? Data(contentsOf: file.url),
                  let text = String(data: data, encoding: .utf8) else { continue }   // il file resta

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onText?(text)
            }
            if (try? fm.removeItem(at: file.url)) == nil {
                delivered[file.url.path] = file.date
            }
        }
    }

    private func isDeliveryFileName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return namePattern.firstMatch(in: name, range: range) != nil
    }
}
