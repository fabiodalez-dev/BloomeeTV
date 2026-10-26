# Bloomee TV 1.3.0 e Bloomee Remote 1.1.0

Ricerca e playlist dal cellulare, su Android TV e sull'edizione LG webOS 0.4.0. Le correzioni della 1.2.1 restano incluse.

## Dal cellulare

- **Cerca**: cerca brani o playlist in YouTube Music, Jellyfin e nella libreria locale; filtra la sorgente, carica altri risultati, riproduci o aggiungi alla coda. Le sorgenti rispondono separatamente e gli errori parziali sono visibili.
- **Playlist**: apri le playlist dell'account YouTube Music collegato, quelle Jellyfin e le playlist locali. Sfoglia i brani, riproduci tutto, avvia in ordine casuale o aggiungi alla coda.
- **Playlist locali**: crea una playlist, salva la coda, aggiungi risultati/brani o intere playlist, rinomina e rimuovi brani. I dati restano nella TV. Le playlist degli account esterni sono consultate senza modificarle.

Aggiorna sia Bloomee Remote sia il ricevitore TV. Le versioni precedenti accettano i comandi musicali ma non la ricerca. Le credenziali restano nella TV; il protocollo usa riferimenti temporanei invece di inviare URL audio o token al cellulare. Un cambio account/profilo invalida i risultati precedenti.

Android: package `it.fabiodalez.bloomeetv`, versione 1.3.0, build base 1300 (ARMv7 2300, ARM64 3300). Remote: `it.fabiodalez.bloomee_remote`, 1.1.0, codice 2. Firma release locale compatibile con i pacchetti precedenti. Android 7/API 24 o successivo.

LG: `org.bloomee.webos`, versione 0.4.0, bridge 8. Richiede il setup webOS con Homebrew Channel e root già supportato dal progetto. Le playlist locali LG risiedono nel localStorage dell'app; su Android usano la libreria del profilo.

La ricerca remota riguarda brani e playlist, non pagine artista o album. La coda mostra i primi 500 elementi. I cataloghi richiedono la configurazione delle sorgenti sulla TV; YouTube Music continua a dipendere dal resolver già installato per la riproduzione Android.

Verifiche: suite Flutter TV completa, test mirati del protocollo e della gestione playlist/account, test dell'app con risposte in ritardo e schermo piccolo con tastiera/testo grande, test Python/JavaScript LG e audit del focus in Chromium. Prova completa dell’APK nell’emulatore collegato al ricevitore HTTP LG e alla pagina webOS reale in Chromium, con catalogo/audio di prova: creazione playlist, ricerca, riproduzione, aggiunta a playlist e riproduzione completa. La verifica su TV fisiche resta da fare.
