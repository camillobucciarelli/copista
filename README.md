# Copista

App per la barra dei menu di macOS. Tiene lo storico dei testi copiati.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/camillobucciarelli)

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

## Ricezione da Android

Voce di menu "Ricevi testo da Android". All'inizio è spenta.

Quando invii un testo da Android al Mac, il testo arriva in Download come file `text-0.txt`
(oppure `text-0 2.txt`, `text-0 3.txt`… se il primo esiste già). Con la funzione attiva, Copista:

1. legge il file;
2. mette il testo negli appunti e in cima allo storico (`Cmd+V` lo incolla);
3. elimina il file in modo definitivo (non va nel Cestino).

| Caso | Risultato |
|---|---|
| File vuoto | Il file è eliminato, nessun elemento nuovo |
| File non UTF-8 o più grande di 1 MB | Il file resta, nessun elemento nuovo |
| "Sospendi registrazione" attivo | Il file resta; Copista lo legge alla ripresa |
| File già presente all'avvio | Copista lo legge |

Limite: il file non porta il segnale "riservato" dei password manager. Una password inviata
da Android entra nello storico in chiaro. Eliminare l'elemento a mano dalla lista.

## Permessi

- **Cartella Download**: necessario per "Ricevi testo da Android". macOS lo chiede alla prima attivazione.

- **Accessibilità**: necessario per l'incolla automatico dalla lista.
  Senza permesso, l'elemento scelto va negli appunti e si incolla con `Cmd+V`.
- La firma è ad-hoc. Dopo ogni nuova compilazione macOS può chiedere di nuovo
  il permesso (rimuovere e aggiungere di nuovo l'app in Accessibilità).

## Dati

- Storico: `~/Library/Application Support/Copista/history.json` (testo in chiaro, max 100 elementi).
- Gli elementi marcati come riservati dai password manager non sono registrati.

## Mac App Store

Il job `appstore` (sui tag `v*` e a mano con `workflow_dispatch`) esegue `appstore.sh`. Prerequisiti una tantum sul Mac del runner:

- Nel portachiavi login: "Apple Distribution" e "3rd Party Mac Developer Installer" (nomi sovrascrivibili con `SIGN_APP` / `SIGN_PKG`).
- Provisioning profile in `~/.private_keys/Copista_AppStore.provisionprofile` (o `PROFILE`).
- Chiave API `AuthKey_<ID>.p8` in `~/.private_keys`.
- Secret del repository `ASC_KEY_ID` e `ASC_ISSUER_ID`.
- Il runner va avviato da terminale con `./run.sh` (non come servizio LaunchAgent), altrimenti codesign non può usare il portachiavi di login.

Prova locale senza upload: `BUILD_NUMBER=1 ./appstore.sh --no-upload`.

## Licenza

MIT. Vedi [LICENSE](LICENSE).
