# Bloomee TV 1.2.1

Correzioni di YouTube Music, ricerca e riproduzione automatica, trovate durante il porting di Bloomee su LG webOS.

## Correzioni

- **Artista negli album di YouTube Music.** I brani di un album senza artista proprio mostravano "Album • 2006" al posto del nome, nel player, nella coda, nei preferiti e nel raggruppamento delle versioni. Ora l’artista viene dalla testata dell’album.
- **"Altri risultati" nella ricerca.** Una pagina arrivata dopo il limite di 12 secondi spostava comunque la posizione della sorgente, e la pagina successiva saltava risultati mai mostrati. Ora una pagina viene accettata solo se la ricerca la sta ancora aspettando.
- **Riproduzione automatica.** I brani simili cercati per la coda precedente venivano aggiunti alla coda appena avviata. Ora vengono scartati.

I brani già salvati con l’artista sbagliato non vengono riscritti automaticamente.

## Installazione

APK **ARMv7**, per dispositivi Android TV/Google TV con compatibilità ARM a 32 bit, Android 7.0/API 24 o successivo.

Scarica `BloomeeTV-1.2.1-armeabi-v7a.apk` e installalo come aggiornamento. Package: `it.fabiodalez.bloomeetv`. Versione app: **1.2.1**, build base **8**, versionCode ARMv7 **1008**.

Firma SHA-256 attesa: `5c:d3:c7:38:20:31:22:c0:e5:73:20:31:cc:3e:10:23:17:d6:7d:c9:d3:4a:7c:cf:f3:41:da:34:c5:30:03:5f`, uguale alle release precedenti: l’aggiornamento in place conserva i dati. Non disinstallare la versione esistente.

## Verifiche

- 101 test Flutter passati con Flutter 3.35.4, inclusi i nuovi test di `test/tv/review_fixes_test.dart`: quelli su artista dell’album e riproduzione automatica falliscono sul codice di 1.2.0 e passano con la correzione.
- Analisi statica senza errori o warning (restano segnalazioni informative di stile).
- CI: Flutter Analyze & Test e Rust Clippy & Test passati.
- Le correzioni non sono state provate su un Chromecast reale.

Licenza GPL-2.0; Bloomee originale di HemantKArya.
