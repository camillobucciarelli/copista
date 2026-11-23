# `sharingType = .none` nasconde pannello e finestra di modifica dalla condivisione schermo?

Ricerca per [#15](https://github.com/camillobucciarelli/copista/issues/15) (parte di #14). Data: 2026-11-23. Fonti consultate: documentazione Apple (JSON di developer.apple.com), header dell'SDK macOS 27.2 di Xcode installato, Apple Developer Forums (risposte DTS), documentazione Electron. Il codice dell'app non è stato modificato.

## Risposta breve

**Parzialmente, e sempre meno.** `sharingType = .none` è un'impostazione a livello di *CGWindow*: la rispettano le API legacy di cattura per finestra (`CGWindowListCreateImage` e simili), non la cattura dello schermo intero né ScreenCaptureKit. Apple ora definisce `.none` "una costante legacy che macOS non usa più" e dice esplicitamente di non usarla per nascondere contenuti alla cattura. Non esiste un'API pubblica per impedire la cattura né per sapere quando è in corso.

| Caso | Esclusa? | Livello di evidenza |
|---|---|---|
| macOS 11–14, cattura per finestra con `CGWindowListCreateImage` / `CGWindowList*` | Sì (la finestra viene omessa, oppure al suo posto c'è nero) | Fatto: header SDK + DTS |
| macOS 11–14, cattura di display/schermo (`CGDisplayStream`, `CGDisplayCreateImage`), registratori, controllo remoto | Non garantito: secondo DTS "non ha effetto" | Fatto: DTS (lug 2024) |
| macOS 12.3+, ScreenCaptureKit | Non garantito: nessun contratto documentato. Comportamento incoerente: a volte omessa all'avvio dello stream, poi ricompare | Fatto: forum con conferma DTS di un possibile bug |
| macOS 15.4+, ScreenCaptureKit (QuickTime, Screenshot, app recenti) | **No**: la finestra viene catturata | Fatto: forum + DTS ("nessuna API pubblica") + Electron ("cambiamento intenzionale") |
| macOS 15+, API legacy | Ritirate (obsolete) nell'SDK 15, quindi irrilevanti per i client aggiornati | Fatto: header SDK |
| Zoom / Teams / Meet in Chrome, nello specifico | Dipende dall'API usata da ognuno: non verificabile dalle fonti primarie. Su 15+ vale la riga di ScreenCaptureKit | Deduzione |

## Fatti osservati

1. **Documentazione AppKit, `NSWindow.SharingType.none`**: "A legacy constant that macOS no longer uses. `NSWindowSharingNone` can cause content to not be available in certain sharing situations. Don't use this value to hide or omit content from being captured. Instead, use FairPlay Streaming (FPS)."
   - <https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none>
2. **Header SDK `NSWindow.h`** (SDK macOS 27.2): con `NSWindowSharingNone` "your window will also not be able to participate in a number of system services, so this setting should be used with caution". L'enum ha ormai solo `None` e `ReadOnly`.
3. **Header SDK `CGWindow.h`**, su `CGWindowListCreateImage`: "Any on-screen window with sharing type `kCGWindowSharingNone` will not be included in the image." La funzione è marcata `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)`: deprecata in 14.0, obsoleta in 15.0. Anche `CGDisplayStream*` è obsoleta in 15.0 (`SCREEN_CAPTURE_OBSOLETE(10.8,14.0,15.0)`), e lo stesso vale per `CGDisplayCreateImage` (`10.6,14.4,15.0`). Gli header di cattura di display e di ScreenCaptureKit **non nominano mai** lo stato di condivisione.
4. **Apple DTS (Kevin Elliott), luglio 2024**, nel thread [App content protection failure](https://developer.apple.com/forums/thread/760234). In sostanza: `kCGWindowSharingState` / `NSWindowSharingNone` cambiano solo come la finestra è trattata *a livello CGWindow* (per esempio `CGWindowListCreateImage` mette un rettangolo nero o fallisce). Quasi tutti i registratori di schermo e le app di controllo remoto lavorano *sotto* quel livello, quindi l'impostazione non ha effetto, e il comportamento è "basically deliberate". DTS non conosce un modo "buono" per impedire la cattura: gli unici casi nel sistema sono DVD Player e i contenuti HLS protetti con FairPlay, entrambi privati. Su macOS non esiste una notifica di screenshot.
5. **Apple DTS, luglio 2025**, nel thread [On macOS 15.4+, NSWindow with kCGWindowSharingStateSharingNone still captured by ScreenCaptureKit](https://developer.apple.com/forums/thread/792152), risposta accettata: "At this time there are no public APIs for preventing screen capture." Suggerisce di aprire una richiesta su Feedback Assistant.
6. **Apple DTS, novembre 2025**, nel thread [ScreenCaptureKit sample initially omits application with NSWindowSharingNone](https://developer.apple.com/forums/thread/808016). Con il sample Apple di ScreenCaptureKit, una finestra `NSWindowSharingNone` manca all'inizio dello stream e ricompare dopo aver cambiato un filtro. QuickTime, che usa ScreenCaptureKit, la cattura subito. DTS lo tratta come possibile bug (FB21115847), senza soluzione.
7. **Documentazione Electron**, `win.setContentProtection` (su macOS imposta `NSWindowSharingNone`): "due to an intentional change in macOS, newer Mac applications that use ScreenCaptureKit will capture your window despite `win.setContentProtection(true)`." Fonte secondaria rispetto ad Apple, ma è la documentazione ufficiale del progetto che usa questa API in produzione. <https://www.electronjs.org/docs/latest/api/browser-window>

## Applicabilità a `NSAlert`

- `alert.window` è un `NSWindow` normale, accessibile prima di `runModal()` (Copista lo usa già per `initialFirstResponder`), quindi gli si può impostare `sharingType`. Non esiste una restrizione documentata.
- Osservazione locale (macOS 27.2.1): con un probe AppKit, impostando `alert.window.sharingType = .none` prima di `runModal()`, durante il modale si rilegge `rawValue == 0`, quindi `runModal` non reimposta il valore. **Non è stato possibile verificare l'effetto sulla cattura**: in questa sessione `screencapture` non ha il permesso di Registrazione schermo ("could not create image from display"). Il probe è riportato sotto per ripetere il test a mano.
- Il valore vale per la finestra, non per l'app: il pannello e l'alert vanno impostati separatamente. Si eredita il limite del punto precedente: su macOS 15+ non nasconde nulla a ScreenCaptureKit.

## Effetti collaterali

- **Servizi di sistema**: secondo l'header, la finestra "non potrà partecipare a vari servizi di sistema" (fatto 2). L'elenco non è documentato.
- **Screenshot per lo store**: sulle versioni e i percorsi dove l'impostazione è rispettata (cattura per finestra legacy, macOS ≤ 14), lo screenshot della finestra con ⌘⇧4 + spazio può uscire nero o vuoto. Su macOS 15+ con gli strumenti di sistema basati su ScreenCaptureKit è probabile che lo screenshot riesca comunque. È una deduzione dai fatti 3–6, non verificata. Per sicurezza conviene un'opzione di debug, o una build, che non imposti `.none` quando si producono gli screenshot (`screenshots/`, `store/`).
- **Falsa sicurezza**: è il rischio maggiore. L'utente crede che lo storico non si veda in una chiamata, e invece si vede.

## Cosa le fonti non stabiliscono

- Quale API usano oggi Zoom, Teams e Chrome/Meet per catturare lo schermo su ogni versione di macOS. Sono closed source o con flag variabili, e non esiste una fonte primaria stabile. Su macOS 15+ le API legacy sono obsolete nell'SDK, quindi un client aggiornato usa quasi certamente ScreenCaptureKit (deduzione).
- Se le versioni di macOS 15.0–15.3 si comportassero diversamente dalla 15.4+. Il thread del 2025 cita "15.4+", e nessuna fonte Apple data la modifica.
- Il comportamento esatto su macOS 26 e 27: non esistono note di rilascio che lo menzionino. Le fonti del 2025 (DTS) e la documentazione attuale ("no longer uses") fanno pensare che non sia cambiato nulla.

## Raccomandazione

1. **Non promettere l'esclusione dalla condivisione.** Se si imposta `sharingType = .none` (una riga per finestra, sul `KeyPanel` e su `alert.window` prima di `runModal`), va presentato come *best-effort*, utile solo con i catturatori legacy per finestra.
2. **Alternativa robusta, sotto il controllo dell'app**: dato che non esiste un'API per rilevare la cattura (fatti 4–5), l'unica difesa affidabile è **non mostrare il contenuto**. Per esempio un'opzione "Modalità presentazione" o "Nascondi anteprime", attivata a mano dall'utente o da scorciatoia, che oscura il testo degli elementi nel pannello. Rilevare la cattura tramite euristiche (cercare processi come zoom.us o Teams, o l'indicatore in barra dei menu) è fragile e non c'è un'API documentata. Lo sconsiglio.
3. **Le esclusioni di `SCContentFilter`** (`excludingWindows:` / `excludingApplications:`) le sceglie *chi cattura*, non Copista: non sono una leva per noi.
4. Se il requisito è importante, aprire una richiesta su Feedback Assistant come suggerisce DTS (fatto 5).

## Probe per il test manuale

Va eseguito da un terminale che ha il permesso di Registrazione schermo. Mostra un `NSPanel` rosso e un `NSAlert` con l'accessorio rosso, poi lancia `screencapture` (processo separato) e controlla se il rosso compare. Per confrontare, aggiungere `--readonly`.

```swift
// swiftc -o probe probe.swift && ./probe /tmp/probe && ./probe /tmp/probe --readonly
import AppKit
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
let out = CommandLine.arguments[1], shareNone = !CommandLine.arguments.contains("--readonly")
func capture(_ name: String, _ rect: NSRect) -> String {
    let h = NSScreen.screens[0].frame.height, path = "\(out)-\(name).png"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(h - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
    try? p.run(); p.waitUntilExit()
    guard let d = NSImage(contentsOfFile: path)?.tiffRepresentation, let rep = NSBitmapImageRep(data: d),
          let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB) else { return "\(name): no image" }
    return "\(name): " + (c.redComponent > 0.8 && c.greenComponent < 0.2 ? "VISIBILE" : "NON visibile")
}
let frame = NSRect(x: 200, y: 200, width: 300, height: 200)
let panel = NSPanel(contentRect: frame, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.backgroundColor = .red; if shareNone { panel.sharingType = .none }; panel.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    print(capture("panel", frame.insetBy(dx: 40, dy: 40))); panel.orderOut(nil)
    let alert = NSAlert(); alert.messageText = "probe"
    let acc = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120)); acc.wantsLayer = true
    acc.layer?.backgroundColor = NSColor.red.cgColor; alert.accessoryView = acc
    if shareNone { alert.window.sharingType = .none }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        print("alert sharingType durante il modale:", alert.window.sharingType.rawValue)
        print(capture("alert", alert.window.convertToScreen(acc.convert(acc.bounds, to: nil)).insetBy(dx: 40, dy: 30)))
        exit(0)
    }
    alert.runModal()
}
app.run()
```

Per Zoom, Teams e Meet: avviare una condivisione dell'intero schermo con il pannello aperto e guardare l'anteprima dal lato di chi riceve. Ripetere su ogni versione di macOS da supportare.
