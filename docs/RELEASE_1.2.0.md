# Bloomee TV 1.2.0

Ricerca progressiva più rapida sul Chromecast, coda modificabile e un Centro TV per gestire ascolto, libreria e dispositivo.

## Ricerca e telecomando

- Brani e artisti arrivano per primi; album e playlist seguono senza bloccarli. Nelle prove sul Chromecast: primi brani/artisti in circa 0,6–0,8 secondi, album entro circa 1–1,4 secondi. I tempi dipendono dalla rete e dai servizi.
- “Tutto”, “Brani”, “Album” e “Artisti” sono sempre visibili sotto la barra; gli altri filtri sono richiudibili. Focus iniziale su “Parla” e spaziature allineate.
- Prima pagina per sorgente, paginazione esplicita, cache di ricerca in memoria e cataloghi offline separati dalle preferenze.
- Ricerca vocale con annullamento corretto, guida iniziale mostrata una volta sola, nessun ribbon DEBUG nella release. Jellyfin appare solo se configurato.

## Coda, libreria e ascolto

- Riordino della vera coda di riproduzione, rimozione multipla, annulla e salvataggio come playlist.
- Creazione e modifica di playlist locali, preferiti con varianti, contenuti fissati e Home personalizzabile.
- Profili separati e modalità ospite; cataloghi già visitati consultabili offline.
- Timer a durata, fine brano o fine album, con dissolvenza: interrompe l’audio, senza spegnere la TV. ReplayGain opzionale su entrambi i player.
- Centro TV con operazioni, download, quota/spazio, accessibilità, diagnostica e inserimento testo dal telefono tramite QR temporaneo.

## Stabilità

- Download atomici, controllo dei file offline, cancellazione dei tentativi di riproduzione obsoleti e risposte di ricerca indipendenti.
- Credenziali cifrate con Android Keystore e isolate per profilo, backup/import validati e pulizia delle immagini al cambio account.
- Aggiornamenti dal fork con selezione dell’APK per ABI; strumento di installazione verificata che non disinstalla né esegue downgrade.

## Limiti noti

- **La notifica condivisa Google sul telefono continua a mostrare “Bloomee TV / Chromecast”.** Titolo, album e copertina sono stati verificati sul protocollo Cast, ma questo non risolve la presentazione della notifica.
- Il Cast da un sender reale non è dichiarato risolto: un ricevitore completo richiede sender compatibile e configurazione/registrazione Google Cast.
- Le API interne di YouTube Music e i plugin possono cambiare. I vecchi brani già salvati con un conteggio riproduzioni al posto dell’artista non vengono riscritti automaticamente.
- F15–F17 e F20 del piano restano pianificate. Le funzionalità implementate sono MVP F01–F14, F18 e F19.

## Installazione

APK **ARMv7**, per dispositivi Android TV/Google TV con compatibilità ARM a 32 bit, Android 7.0/API 24 o successivo.

Scarica `BloomeeTV-1.2.0-armeabi-v7a.apk` e installalo come aggiornamento. Package: `it.fabiodalez.bloomeetv`. Versione app: **1.2.0**, build base **7**, versionCode ARMv7 **1007**.

Firma SHA-256: `5c:d3:c7:38:20:31:22:c0:e5:73:20:31:cc:3e:10:23:17:d6:7d:c9:d3:4a:7c:cf:f3:41:da:34:c5:30:03:5f`. La firma coincide con le release precedenti; l’aggiornamento in place conserva i dati. Non disinstallare la versione esistente.

## Verifiche

- 96 test Flutter passati; analisi statica senza errori o warning (rimangono segnalazioni informative di stile).
- 5 test Python dell’installatore, 3 test Rust e 2 test Kotlin JVM passati.
- Verifiche sul Chromecast reale: ricerca, categorie e focus, modifica della coda, riproduzione nativa e timer; due test Android nativi per credenziali e login.

Dettagli e limiti delle verifiche: [IMPLEMENTAZIONE_E_VERIFICHE.md](https://github.com/fabiodalez-dev/BloomeeTV/blob/v1.2.0/docs/IMPLEMENTAZIONE_E_VERIFICHE.md). Licenza GPL-2.0; Bloomee originale di HemantKArya.
