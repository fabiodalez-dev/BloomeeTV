# Bloomee Remote 1.1.1

App Android in italiano per cercare musica e controllare Bloomee su Android TV/Google TV e LG webOS con Homebrew Channel/root. Android 7 o successivo. Package `it.fabiodalez.bloomee_remote`.

## Collegamento

1. Installa Bloomee Remote 1.1.1. Per ricerca e playlist serve almeno Bloomee TV 1.3.0 o LG 0.4.0; il pacchetto aggiornato include Android TV 1.3.1 e LG 0.4.1.
2. Collega telefono e TV alla stessa rete locale.
3. Android TV: **Centro TV → telefono → Collega Bloomee Remote**. LG: **Impostazioni → Telecomando dal cellulare → Collega / nuovo codice**.
4. Nel telefono inserisci indirizzo completo e codice mostrati sulla TV. Su LG la porta è 18794; su Android usa quella mostrata.

Il codice vale cinque minuti. Una sessione dura fino a dodici ore; su Android termina anche quando Bloomee passa in background o cambia profilo. Per revocare i telefoni disattiva il telecomando oppure genera un nuovo codice. Il telefono ricorda soltanto l'ultimo indirizzo TV; riaprendolo potrebbe servire un nuovo codice.

## Uso

- **Cerca**: cerca brani o playlist in YouTube Music, Jellyfin e nella libreria locale. Tocca un brano per riprodurlo; dal menu puoi aggiungerlo alla coda. **Altri risultati** apre le pagine successive.
- **Playlist**: sfoglia le playlist già esistenti negli account configurati sulla TV e nella libreria locale. Aprile, scegli un brano oppure usa **Riproduci tutto**, **Casuale** o **In coda**.
- **In ascolto**: play/pausa, precedente/successivo, posizione, volume del player, casuale e ripeti coda.
- **Coda**: seleziona uno dei primi 500 brani in coda.

L'app non crea, rinomina o modifica playlist. I ricevitori 1.3.1/0.4.1 rifiutano anche questi comandi dal protocollo remoto. Le playlist esistenti sulla TV sono conservate.

Le sorgenti e gli account si configurano sulla TV. Il catalogo remoto trasmette titolo, artista e riferimenti temporanei, senza URL audio o credenziali. I comandi passano via HTTP sulla LAN. Il volume regola Bloomee, non il volume generale del televisore.

## Build

Con Flutter 3.35.4, JDK 17 e Android SDK:

```sh
cd remote
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Output: `remote/build/app/outputs/flutter-apk/app-release.apk`, universale ARMv7/ARM64/x86_64. La build riusa la chiave release locale del progetto TV, se presente; altrimenti usa la chiave debug. Mantieni la stessa firma per aggiornare in place.

Ricevitore Android: `lib/tv/services/tv_remote_*`. Ricevitore LG: `webos/phone_remote.py`, `webos/phone-remote.js` e `webos/phone-catalog.js`.
