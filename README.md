# Copista

App per la barra dei menu di macOS. Tiene lo storico dei testi copiati.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/camillobucciarelli)

## Compilazione

```bash
./build.sh
open build/Copista.app
```

Requisito: Xcode Command Line Tools. macOS 11 o successivo.

## Lingue

Italiano, inglese, spagnolo, francese, tedesco, portoghese (Brasile). L'app usa la lingua di macOS; se la lingua non è disponibile, usa l'inglese.
I testi sono in `Resources/<lingua>.lproj/`. Per una nuova lingua, copiare `en.lproj` e tradurre i valori.

Il sito (`site/`) ha le stesse lingue: ogni pagina contiene tutte le lingue e mostra quella del browser, oppure quella nel link (`index.html#en`).
I testi della scheda del Mac App Store sono in `store/<locale>/` (sottotitolo, descrizione, parole chiave, testo promozionale, novità). Vanno copiati a mano in App Store Connect.

## Uso

| Azione | Risultato |
|---|---|
| `Cmd+V` | Incolla l'ultimo elemento (comportamento di sistema) |
| `Cmd+Shift+V` | Apre / chiude la lista |
| `↑` `↓` | Sceglie un elemento |
| `Invio` o clic | Copia l'elemento scelto negli appunti e chiude la lista; poi `Cmd+V` lo incolla nell'app di prima. Con l'opzione "Incolla automaticamente" del menu (spenta all'inizio, richiede un permesso) incolla da solo |
| `⌘`-clic, `⇧`-clic, `⇧`+`↑` `↓` | Seleziona più elementi |
| `Invio` con più elementi | Copia gli elementi come un solo testo, uno per riga, nell'ordine della lista. Il testo unito non entra nello storico |
| `⌫` | Elimina gli elementi selezionati |
| Icona cestino | Elimina l'elemento della riga |
| `Esc` | Chiude la lista |
| Icona nella barra | Pulizia dello storico, sospensione, uscita |

## Apertura al login

Impostazioni › Generali › "Apri al login". All'inizio è spenta. Richiede macOS 13 o successivo:
su macOS 11 e 12 la voce non compare.

Lo stato è quello di macOS: la stessa opzione è in Impostazioni di Sistema › Generali › Elementi login.
Se lì Copista è stato spento, solo l'utente può riaccenderlo da lì; Copista apre quel pannello.

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

## Sito

Il sito (home, supporto, privacy) è in `site/`: HTML scritto a mano, un solo `style.css`, immagini in `site/img/`, nessuna build. Il workflow `Site` carica ogni file sotto `site/` in un bucket Cloudflare R2 dietro un dominio personalizzato, a ogni push su `main` che cambia `site/` e a mano con `workflow_dispatch`.

- Secret del repository: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID`, `R2_BUCKET`. Variabile opzionale `SITE_BASE_URL` (URL pubblico del dominio).
- R2 non serve l'indice di cartella: ogni link nomina il file (`index.html`, `support.html`, `privacy.html`). La radice `/` funziona solo con una Transform Rule di Cloudflare impostata a mano (Rewrite URL: path `/` → `/index.html`).
Prima configurazione (bucket, dominio, secret, primo upload): `tool/site_setup.sh`, una procedura guidata.

## Licenza

GNU AGPL-3.0, con i permessi aggiuntivi per la distribuzione sugli store in [LICENSE-EXCEPTIONS.txt](LICENSE-EXCEPTIONS.txt). Vedi [LICENSE](LICENSE).
