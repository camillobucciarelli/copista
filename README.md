# Copista

App per la barra dei menu di macOS. Tiene lo storico dei testi copiati.

## Compilazione

```bash
./build.sh
open build/Copista.app
```

Requisito: Xcode Command Line Tools. macOS 13 o successivo.

## Uso

| Azione | Risultato |
|---|---|
| `Cmd+V` | Incolla l'ultimo elemento (comportamento di sistema) |
| `Cmd+Shift+V` | Apre / chiude la lista |
| `↑` `↓` | Sceglie un elemento |
| `Invio` o clic | Incolla l'elemento scelto |
| `⌫` o icona cestino | Elimina l'elemento dalla lista |
| `Esc` | Chiude la lista |
| Icona nella barra | Pulizia dello storico, sospensione, uscita |

## Permessi

- **Accessibilità**: necessario per l'incolla automatico dalla lista.
  Senza permesso, l'elemento scelto va negli appunti e si incolla con `Cmd+V`.
- La firma è ad-hoc. Dopo ogni nuova compilazione macOS può chiedere di nuovo
  il permesso (rimuovere e aggiungere di nuovo l'app in Accessibilità).

## Dati

- Storico: `~/Library/Application Support/Copista/history.json` (testo in chiaro, max 100 elementi).
- Gli elementi marcati come riservati dai password manager non sono registrati.
