# Copista

App per la barra dei menu di macOS che tiene lo storico dei testi copiati dall'utente.

## Language

**Storico**:
La lista ordinata degli elementi copiati, dal più recente al più vecchio.
_Avoid_: Lista, cronologia, history

**Elemento**:
Un testo nello storico.
_Avoid_: Clip, voce, item

**Ultimo copiato**:
L'elemento più recente dello storico. È uguale al contenuto degli appunti di sistema, quindi `Cmd+V` lo incolla. La selezione di un elemento copia soltanto; un'opzione del menu, spenta all'inizio, incolla in automatico dopo che l'utente ha concesso il permesso. Unica eccezione: dopo un incolla multiplo gli appunti contengono il testo unito.
_Avoid_: Corrente, primo elemento

**Incolla multiplo**:
L'azione che copia più elementi selezionati come testo unito, da incollare con un solo `Cmd+V`.
_Avoid_: Incolla in sequenza, multi-paste

**Testo unito**:
Il testo prodotto da un incolla multiplo: gli elementi selezionati nell'ordine dello storico, separati da un ritorno a capo. Va negli appunti di sistema ma non diventa un elemento. Alla prima eliminazione dallo storico, l'ultimo copiato lo sostituisce negli appunti.
_Avoid_: Elemento unito, testo combinato

**File di consegna**:
Un file nella cartella Download che porta un testo inviato da un dispositivo Android. Ha nome `text-0.txt`, oppure `text-0 N.txt` quando macOS rinomina un doppione.
_Avoid_: File importato, drop file, file AirDrop

**Ricezione da Android**:
La funzione, spenta finché l'utente non la abilita, che trasforma ogni file di consegna in un elemento e poi elimina il file in modo definitivo. Il file di consegna più recente diventa l'ultimo copiato.
_Avoid_: Importazione, sincronizzazione, watcher
