import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // solo barra dei menu, nessuna icona nel Dock
app.run()
