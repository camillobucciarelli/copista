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
Un file con nome esatto `text-0.txt` nella cartella Download, che porta un testo inviato da un dispositivo Android. L'app lo trasforma nell'ultimo copiato e poi lo elimina in modo definitivo.
_Avoid_: File importato, drop file, file AirDrop

**Ricezione da Android**:
La funzione, che l'utente può abilitare e disabilitare, che trasforma ogni file di consegna nell'ultimo copiato.
_Avoid_: Importazione, sincronizzazione, watcher
