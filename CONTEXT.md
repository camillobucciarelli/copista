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
L'elemento più recente dello storico. È sempre uguale al contenuto degli appunti di sistema, quindi `Cmd+V` lo incolla.
_Avoid_: Corrente, primo elemento

**File di consegna**:
Un file nella cartella Download che porta un testo inviato da un dispositivo Android. Ha nome `text-0.txt`, oppure `text-0 N.txt` quando macOS rinomina un doppione.
_Avoid_: File importato, drop file, file AirDrop

**Ricezione da Android**:
La funzione, spenta finché l'utente non la abilita, che trasforma ogni file di consegna in un elemento e poi elimina il file in modo definitivo. Il file di consegna più recente diventa l'ultimo copiato.
_Avoid_: Importazione, sincronizzazione, watcher
