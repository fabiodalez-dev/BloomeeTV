> Revisione iniziale del 19 ottobre 2026. Per lo stato successivo delle correzioni e le verifiche effettive, leggere [IMPLEMENTAZIONE_E_VERIFICHE.md](IMPLEMENTAZIONE_E_VERIFICHE.md).

# Review di usabilità e stabilità di Bloomee TV

Data: 19 ottobre 2026. Base Git: `1c1b4aa`, branch `tv-remote`, con le modifiche locali presenti al momento della review. Il bootstrap dei plugin era già modificato e `tv-env.sh` era già presente come file non tracciato: non sono stati modificati da questa attività.

## Valutazione

L'app ha una direzione TV riconoscibile e una buona base per l'ascolto domestico: focus evidente, navigazione per righe, player persistente e integrazione dei brani Jellyfin nello stesso motore audio. L'affidabilità delle operazioni in errore, dei download e dei dati richiede ancora interventi prima di una distribuzione più ampia. Una build riuscita da sola non basta a qualificarla come stabile.

Il problema principale di usabilità è la distanza tra ciò che viene promesso e ciò che il flusso effettivamente completa: elenchi parziali presentati come completi, richieste Lidarr descritte come download avviati, preferiti locali e preferiti YouTube con nomi simili. Il problema principale di stabilità è la gestione non uniforme di timer, risposte asincrone e persistenza.

**22 rilievi: 0 P0, 8 P1, 14 P2.** P1 indica un problema significativo da risolvere prima della prossima release destinata a un pubblico più ampio; P2 un problema con impatto circoscritto o un percorso alternativo. La gravità è distinta dal livello di verifica: una conseguenza dedotta dal codice non viene presentata come crash osservato.

Non emergono motivi per ridisegnare da zero l'interfaccia. Copertine, righe e griglie sono appropriate per un catalogo musicale su TV. La struttura è coerente con il compito; i punti deboli sono leggibilità, stato delle operazioni e uniformità con le schermate ereditate.

| Dimensione dell'interfaccia | Valutazione / 4 | Motivo |
| --- | ---: | --- |
| Accessibilità | 2 | D-pad e focus curati; contrasto dei pulsanti selezionati e semantica incompleti. |
| Prestazioni | 2 | Liste lazy e immagini ridimensionate presenti; avvio con rete e alcune raccolte costruite interamente. Nessun profiling hardware. |
| Adattamento a viewport e testo | 1 | Tastiera con overflow riprodotto; molte dimensioni fisse. |
| Coerenza del tema | 3 | Token TV centralizzati; discontinuità con schermate e messaggi ereditati. |
| Chiarezza della composizione | 4 | Gerarchia basata sui contenuti, senza decorazioni che dominino la musica. |
| **Totale indicativo** | **12/20** | Serve un ciclo di consolidamento. Valutazione euristica, non certificazione di accessibilità. |

## Metodo e limiti

Esaminati bootstrap e routing, shell/focus TV, tastiera e componenti, Home, ricerca, artista, raccolte, player/coda, impostazioni, client YouTube/Jellyfin/Lidarr, risoluzione audio, errori del player, download, database, backup/migrazione, manifest Android, configurazione build e workflow. Ispezionati gli screenshot TV di ricerca e album presenti nel repository. Gli screenshot sono materiale di riferimento, non acquisizioni di questa esecuzione.

Eseguite analisi Flutter, suite Flutter, suite Rust e due prove widget mirate. Avviata anche una build APK debug, il cui esito è riportato sotto. Verificati i link pubblici di [release](https://github.com/fabiodalez-dev/BloomeeTV/releases/tag/v1.1.0) e [issue](https://github.com/fabiodalez-dev/BloomeeTV/issues). La pagina della release conferma nome dell'APK ARMv7 e aggiornamento con la stessa firma.

Non eseguiti accessi a Google o server privati, richieste reali a Lidarr, reset/ripristino di dati dell'utente, installazioni su TV fisiche, prove manuali complete da telecomando, misure di frame time/RAM o ascolti prolungati. L'emulatore già attivo è un telefono, quindi non dimostra il comportamento della shell TV. I rischi di lifecycle, perdita di dati e rete descritti sotto derivano dall'implementazione salvo indicazione di una prova specifica.

## Risultati dei controlli

| Controllo | Esito osservato | Interpretazione |
| --- | --- | --- |
| Flutter 3.35.4 / Dart 3.9.2 | Toolchain disponibile, coerente con i workflow | Nessun aggiornamento delle dipendenze effettuato. |
| `flutter analyze --no-fatal-infos` | 0 errori, 12 warning, 107 info | Non è un controllo verde: i warning restano fatali. Alcune info riguardano BuildContext usati dopo await. |
| `flutter test` | 14 segnaposto superati; test migrazione fallito per `libisar.dylib` mancante | I 14 passaggi non verificano comportamenti. |
| Stessa suite con Isar host disponibile | 14 segnaposto superati; migrazione fallita a `legacy_migration_service_test.dart:188`, download attesi 1, ottenuti 0 | Il blocco ambientale nascondeva un secondo problema. Va chiarito il contratto tra fixture e migratore. |
| `cargo test --locked --manifest-path rust/Cargo.toml` | 2 superati, 1 fallito | Test della validazione manifest non allineato al livello che effettua il controllo. |
| Prova timer del player | Fallita: callback attese 0, osservate 1 dopo reset | Difetto riprodotto, R01. |
| Prova tastiera a 854×480 logici | Fallita: overflow orizzontale di 74 px e verticale di 18 px | Difetto riprodotto, R07. La dimensione è logica, non la risoluzione nominale del pannello. |
| `flutter build apk --debug --no-pub --target-platform android-arm64 --split-per-abi` | Riuscita, `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`, Gradle 377,3 s | Conferma compilazione Dart/Kotlin/Rust e packaging debug ARM64. Non prova comportamento TV, firma release o altre ABI. Warning locale di disallineamento delle versioni XML SDK. |

La libreria Isar già presente nella cache dei pacchetti è stata collegata temporaneamente per la seconda esecuzione e il collegamento è stato rimosso. Nessun database dell'utente è stato usato. Le due prove diagnostiche sono conservate in [review/reproduction_test.dart](review/reproduction_test.dart); si eseguono esplicitamente con `flutter test --no-pub docs/review/reproduction_test.dart`. Sono attese fallire nello stato esaminato e non fanno parte della suite predefinita in `test/`.

## Rilievi P1

### R01. Un retry audio sopravvive a Stop e ai cambi manuali

**Stabilità, riprodotto.** `lib/services/player/player_error_handler.dart:154–168,223–237`; chiamanti `lib/services/bloomee_player.dart:507–519,770–775`.

Il timer di riconnessione viene cancellato quando si programma un altro retry o si distrugge il servizio, ma non in `resetCircuitBreaker`, `registerAttempt` o `markTrackSuccess`. Dopo un errore, Stop azzera il circuito senza cancellare il timer; la callback successiva richiama `_retryCurrentTrack`, che riparte con `doPlay: true`. Anche una pausa o un cambio manuale possono essere superati da un retry pendente.

**Correzione:** invalidare/cancellare il retry per Stop, pausa, cambio brano e successo; legarlo a ID del brano e generazione del tentativo. **Accettazione:** errore seguito da Stop/Pausa/Next non produce ripartenze tardive, con timer simulati e su dispositivo.

### R02. I download Jellyfin possono sovrascriversi e lasciare file parziali

**Integrità dei dati, verificato nel codice.** `lib/tv/lidarr_action.dart:128–154`.

Il percorso usa soltanto artista e titolo sanificati. Due versioni dello stesso brano, oppure titoli che diventano uguali dopo la sanificazione, condividono il file. `openWrite()` lo tronca. Il trasferimento scrive direttamente nel percorso definitivo, senza timeout, verifica di completezza, file temporaneo o pulizia sul fallimento. Il percorso bypassa il download manager Rust.

**Correzione:** nome basato su ID sorgente, staging `.part`, timeout/cancellazione, controllo dei byte e rename atomico; usare un unico gestore download. **Accettazione:** due tracce omonime restano distinte; interruzione di rete o spazio esaurito non danneggiano una traccia già scaricata.

### R03. I segreti dei connettori finiscono nel database e nei backup ordinari

**Protezione dei dati, verificato nel codice.** `lib/tv/tv_config.dart:32–45,125–167`; `lib/services/db/dao/settings_dao.dart:12–18`; `lib/services/db/db_provider.dart:189–207`; `android/app/src/main/AndroidManifest.xml:23–26`.

Cookie Google, token Jellyfin e chiave Lidarr sono stringhe nel database Isar; il backup binario copia l'intero database. La mascheratura visiva non protegge il contenuto del file. È inoltre ammesso traffico HTTP per tutti gli host dell'app, quindi un servizio configurato in HTTP riceve le credenziali senza protezione TLS.

**Correzione:** storage protetto per i segreti, esclusione dai backup ordinari o esportazione cifrata esplicita; comunicare chiaramente quando si configura HTTP. Non è stata provata un'esfiltrazione. **Accettazione:** un backup di libreria non contiene cookie/chiavi; dopo migrazione i servizi continuano a funzionare e il logout rimuove i segreti.

### R04. Il ripristino può eliminare la copia di rollback anche se il recupero fallisce

**Integrità dei dati, verificato nel codice.** `lib/services/db/db_provider.dart:316–388`.

Il `finally` cancella `dbv3.restore_rollback.isar` anche quando il ripristino della copia originale o la riapertura del database hanno generato un secondo errore. Viene così eliminato un possibile punto di recupero proprio nel caso più difficile.

**Correzione:** cancellare il rollback solo dopo riapertura e validazione riuscite; conservare percorso e istruzioni di recupero negli altri casi. **Accettazione:** errori simulati di copia, spazio e apertura mantengono almeno una copia valida e non dichiarano successo.

### R05. Un record offline impedisce il fallback anche quando il file manca

**Riproduzione, verificato nel codice.** `lib/services/player/media_resolver_service.dart:60–74`.

La presenza del record download basta a restituire un URI locale: non viene controllata l'esistenza del file. Se un file è stato eliminato/spostato o il ripristino ha importato percorsi non validi, il player continua a scegliere il percorso locale anziché provare lo streaming. I retry ripetono la stessa scelta.

**Correzione:** verificare il file prima di preferirlo, riconciliare i record e offrire riscaricamento o streaming. **Accettazione:** eliminando il file di una traccia scaricata, con rete disponibile parte la sorgente online; offline compare una spiegazione utilizzabile.

### R06. La CI non esegue i test dichiarati e la regressione Flutter è quasi tutta vuota

**Garanzia di qualità, verificato.** `.github/workflows/checkout.yml:23–67`; `test/regression_test.dart`.

I job chiamati “Flutter Analyze & Test” e “Rust Clippy & Test” eseguono soltanto analisi Dart e `cargo check`. I 14 test di regressione hanno corpi senza asserzioni. I difetti di migrazione e il test Rust fallito non sono intercettati da quei workflow; inoltre i 12 warning rendono già non verde la configurazione di analisi esistente.

**Correzione:** sostituire i segnaposto con test comportamentali, preparare Isar host, eseguire test Flutter/Rust e Clippy, aggiungere smoke test D-pad e build Android. **Accettazione:** un test deliberatamente rotto blocca la PR; nessun test TODO viene contato come copertura.

### R07. La tastiera TV non entra in viewport logici piccoli

**Usabilità/adattamento, riprodotto.** `lib/tv/ui/tv_widgets.dart:709–810`.

Il dialogo ha righe di 13 tasti larghi 56 px più margini, pannello largo 840 px e controlli non adattivi. A 854×480 logici la prova widget rileva 74 px di overflow a destra e 18 px in basso. Alcuni tasti o azioni possono risultare tagliati; non si può estendere questo risultato a tutte le TV 720p senza conoscere la densità logica.

**Correzione:** calcolare larghezze e numero di colonne dai vincoli, mantenere azione/conferma raggiungibili e supportare scorrimento con D-pad. **Accettazione:** 854×480, 960×540 e 1280×720 logici, scala testo 1/1,3/1,5, nessun overflow e ogni tasto raggiungibile.

### R08. Il testo dei pulsanti con focus ha contrasto insufficiente

**Accessibilità, misurato sui token.** `lib/tv/ui/tv_widgets.dart:291–321`; `lib/tv/screens/tv_player_screen.dart:387–415`.

Bianco `#FFFFFF` sul rosa `#FF4D6D` ha contrasto circa **3,21:1**. Il testo dei pulsanti è di 17 px e non rientra nella soglia per testo grande: non raggiunge il riferimento AA 4,5:1 per testo normale. Il testo principale `#F4EEF8` sullo stesso rosa è circa 2,82:1. Il problema si manifesta proprio nello stato che l'utente sta leggendo.

**Correzione:** testo scuro sul rosa o fondo più scuro, verificando anche tastiera e pulsanti circolari. **Accettazione:** contrasto almeno 4,5:1 per le etichette normali in tutti gli stati. Il testo secondario sul fondo scuro, circa 6,30:1 su `surfaceHi`, è invece una base valida. I rapporti sono calcolati in sRGB, senza assumere il contrasto degli screenshot compressi.

## Rilievi P2

### R09. Cataloghi e raccolte si interrompono senza indicarlo

**Completezza/usabilità, verificato nel codice.** `tv_jellyfin_screen.dart:77–83`; `ytmusic_account.dart:159–189,250–277`; entrambi sotto `lib/tv/`.

Jellyfin si ferma a 400 album/artisti. YouTube ricerca, liste account e `collection()` non seguono continuazioni; il distinto `browseAll()` le gestisce in alcune viste “Tutti”, con limite 20 pagine. Anche download e play-all delle raccolte usano solo i brani caricati. **Correzione:** paginazione progressiva, conteggi e stato “altri risultati”. **Verifica:** libreria con 401+ album e playlist con più pagine, senza omissioni/duplicati.

### R10. Il download di una singola traccia Jellyfin segue il percorso plugin

**Download, verificato nel codice.** `lib/tv/lidarr_action.dart:87–101,115–120`; `lib/blocs/downloader/cubit/downloader_cubit.dart:433–444`.

L'azione `track` chiama sempre `downloadSong`, mentre l'adattatore Jellyfin è invocato soltanto dal download di una lista. Il brano con ID `jellyfin::…` arriva quindi al manager dei plugin, senza il ramo diretto presente per gli album. **Correzione:** applicare lo stesso adattatore a entrambe le azioni. **Verifica:** traccia singola e album Jellyfin funzionano con lo stesso server, senza cercare un plugin Jellyfin.

### R11. Le risposte vecchie possono ricomparire dopo logout o cambio account

**Stato/privacy locale, rischio dedotto dal codice.** `lib/tv/screens/tv_home_screen.dart:89–127`.

Il cambio configurazione svuota le liste, ma le richieste già in volo controllano solo `mounted`. Una vecchia risposta può ripopolare Home dopo la disconnessione. I reload di Jellyfin e YouTube partono inoltre per ogni incremento del notifier condiviso. **Correzione:** generazione per servizio/account e cancellazione delle richieste; pulizia cache account. **Verifica:** risposte artificialmente ritardate dopo logout non mostrano contenuti dell'account precedente.

### R12. Alcuni salvataggi aggiornano controller e State dopo await senza guardia

**Lifecycle, rischio dedotto dal codice.** `lib/tv/screens/tv_settings_screen.dart:108–158,186–215,354–365`.

Connessione/scollegamento possono completarsi dopo lo smontaggio della schermata e chiamare `clear`, `setState` o `requestFocus` su oggetti già disposti. La semplice selezione di un'altra sezione spesso mantiene la pagina montata nell'IndexedStack: non è di per sé una riproduzione del crash. **Correzione:** guardie `mounted`, gestione delle operazioni pendenti e risultati indipendenti dalla vista. **Verifica:** smontare la pagina durante login lento, successo ed errore.

### R13. L'importazione del file di configurazione lo cancella prima di applicarlo

**Recuperabilità, verificato nel codice.** `lib/tv/tv_config.dart:87–116`.

`tv-config.json` viene cancellato dopo il parsing, prima della validazione dei campi e delle verifiche di rete. Un errore può lasciare configurazione parziale e nessun file da correggere; l'unico feedback è nel log. **Correzione:** validazione completa e applicazione atomica prima della cancellazione, con esito visibile e gestione protetta degli errori. **Verifica:** JSON valido ma campi errati o server irraggiungibile non perde l'input senza spiegazione.

### R14. L'updater confonde rete non disponibile con nessun aggiornamento

**Fiducia/installazione, verificato nel codice.** `lib/services/bloomee_updater_tools.dart`, funzioni `getAppUpdates`, `extractUpUrl`, `isUpdateAvailable`.

Il ramo TV intercetta gli errori GitHub e restituisce `results: false` con la versione corrente. La scelta asset riconosce la parola `android` e prende il primo risultato, senza confrontare l'ABI; il nome pubblicato `BloomeeTV-1.1.0-armeabi-v7a.apk` porta al fallback sulla pagina web. I build number sopra 1000 sono confrontati modulo 1000. **Correzione:** distinguere errore/nessuna release/disponibile, selezionare ABI e confrontare versioni senza modulo. **Verifica:** offline, 404, limite GitHub e release con più ABI producono risultati distinti e corretti.

### R15. Focus da telecomando e semantica accessibile non coincidono

**Accessibilità, verificato nel codice, TalkBack da collaudare.** `lib/tv/tv_focus.dart:48–175`; `lib/tv/ui/tv_widgets.dart:128–165`; `lib/tv/screens/tv_player_screen.dart:397–415`.

Molti controlli TV sono `Focus` con handler di tasti, senza ruolo/azione semantica esplicita. Titoli delle card ed etichette di alcuni controlli sono fratelli del nodo focusabile; il sistema non ha un contratto unico di nome, ruolo, stato e attivazione. **Correzione:** componente condiviso con `Semantics` per azione, selected/toggled/disabled e label, verificato con albero semantico e TalkBack. Non è stata certificata l'inaccessibilità di ogni singolo controllo.

### R16. La tastiera non permette tutte le credenziali e cancella per unità UTF-16

**Inserimento testo, verificato nel codice.** `lib/tv/ui/tv_widgets.dart:682–704`.

Il set dei tasti a schermo manca, per esempio, di `$`, `;`, `[` e `]`: alcune password e URL IPv6 non si possono inserire soltanto col telecomando. Backspace usa `substring(length - 1)`, che può spezzare emoji/caratteri composti immessi da una tastiera esterna. Non c'è modifica del testo al cursore. **Correzione:** caratteri completi, editing con selezione/cursore e cancellazione per grafemi. **Verifica:** password con simboli e nomi con emoji restano validi dopo una cancellazione.

### R17. Ricerca e richieste lunghe hanno stati poco affidabili o poco persistenti

**Comprensibilità, verificato nel codice.** `lib/tv/screens/tv_search_screen.dart:149–193,226–235,439–448`; `lib/tv/lidarr_action.dart:181–206,251–271`.

La ricerca Jellyfin mantiene i risultati precedenti durante una nuova query e ignora gli errori. In “Tutto”, fallimenti parziali YouTube diventano liste vuote; il fallback può diventare “nessun risultato”. Lidarr usa snackbar di pochi secondi per operazioni che possono durare minuti; “download avviato” significa spesso soltanto comando di ricerca accettato. **Correzione:** stati per sorgente, retry visibile, query associata ai risultati e ricevuta persistente della richiesta. **Verifica:** rete lenta, 401 e zero risultati sono distinguibili; una richiesta rimane consultabile.

### R18. I client HTTP dei connettori non hanno un ciclo di vita esplicito

**Risorse/prestazioni, rischio da misurare.** `lib/tv/tv_config.dart:32–33,125–131`; costruttori dei tre client sotto `lib/tv/connectors/`.

I getter creano nuovi client, che a loro volta creano `http.Client()` senza esporre `close()`. Ricerca “Tutto” avvia quattro chiamate e le configurazioni aggiornano più schermate anche non visibili. Non sono stati misurati socket o memoria in crescita. **Correzione:** ownership esplicita, client condivisi per servizio, chiusura/cancellazione e limiti di concorrenza. **Verifica:** cento ricerche e cambi sezione con risorse stabili e nessuna risposta obsoleta.

### R19. Il matching degli artisti può confondere nomi non latini o corti

**Qualità dei risultati, verificato nel codice.** `lib/tv/screens/tv_artist_screen.dart:21–22,107–120`; `lib/tv/connectors/lidarr_client.dart:58–101`.

La normalizzazione elimina tutto ciò che non è ASCII alfanumerico; nomi non latini possono diventare vuoti. Il filtro usa anche `contains`, così un nome vuoto o molto corto può accettare artisti diversi. La deduplicazione dei brani per solo titolo può eliminare versioni live/studio. **Correzione:** ID stabili, normalizzazione Unicode e criterio prudente per omonimi/versioni; mostrare candidato Lidarr effettivo. **Verifica:** artisti in giapponese/arabo, nomi corti e brani con versioni distinte.

### R20. Il test reale di migrazione non soddisfa il contratto sui download

**Persistenza/qualità, riprodotto.** `test/legacy_migration_service_test.dart:145–154,185–190`; `lib/services/db/legacy/legacy_migration_service.dart:360–378`.

Con Isar host disponibile la migrazione dichiara successo, ma il contatore download è 0 anziché 1. La fixture usa un ID legacy download concatenato e un percorso Windows mentre la traccia ha un ID differente: va verificato se il migratore debba ricondurlo tramite sorgente/URL oppure se la fixture sia obsoleta. Non è provata la perdita generalizzata dei download reali. **Correzione:** chiarire e testare formati legacy, mapping, file mancanti e report degli elementi saltati, conservando sempre l'origine. **Verifica:** fixture realistiche per ogni formato supportato e rapporto esplicito dei dati non migrati.

### R21. Un test Rust verifica la versione manifest al livello sbagliato

**Coerenza dei test, riprodotto.** `rust/src/api/plugin/manifest.rs:194–196,369–382`; `rust/src/api/plugin/plugin_unpacker.rs:123–131`.

Il test si aspetta che `Manifest.validate()` rifiuti `manifest_version: 2`, ma quel controllo è stato spostato esplicitamente all'installazione. L'unpacker lo esegue ancora. Non è quindi dimostrato che si possano installare manifest incompatibili. **Correzione:** separare parsing compatibile e policy d'installazione nei test. **Verifica:** parsing previsto valido, installazione incompatibile respinta, suite Rust interamente verde.

### R22. L'avvio attende rete e componenti nativi prima di mostrare l'app

**Avvio/recupero, verificato nel codice, durata da misurare.** `lib/main.dart:155–168`; `lib/services/bootstrap.dart:21–57`; `lib/services/plugin_bootstrap_service.dart:84–98`.

Il bootstrap attende riconciliazione repository remoti, database, Rust e player prima di `runApp`. La riconciliazione remota degrada senza bloccare definitivamente, ma il tempo di attesa resta sulla schermata iniziale; errori iniziali di Rust/DB/player non hanno una schermata Flutter di recupero. **Correzione:** UI iniziale immediata con fasi osservabili, rete non essenziale in background e recupero sicuro. **Verifica:** avvio offline, catalogo lento, DB non apribile e plugin indisponibile hanno esito visibile e nessuno spinner indefinito.

## Review dei percorsi d'uso

| Percorso | Punti validi | Miglioramento necessario |
| --- | --- | --- |
| Primo avvio | Bootstrap e onboarding esistenti | Guida TV con servizi opzionali, descrizione di Locale/Lidarr e uscita verso musica locale anche in errore. |
| Navigazione D-pad | Focus a bordo spesso, ripristino di riga, protezione da doppio OK, sezioni inattive escluse dal focus | Collaudare pressioni ripetute, ritorno da dialoghi, pagine ancora in caricamento e ripristino dopo standby. Le numerose callback temporizzate non sostituiscono test. |
| Home | Copertine, storico e sorgenti riunite | Rendere esplicite sorgente, caricamento parziale e riconnessione; evitare dati di sessioni vecchie. |
| Ricerca | Voce, tastiera e filtri visibili | Mostrare query e risultati coerenti, errori per sorgente, paginazione e ricerca vocale annullabile senza riutilizzare testo parziale involontario. |
| Album/artista | Play, Casuale e Scarica con lista che scorre separatamente | Accesso al titolo completo, metadati/versioni corretti e nessuna promessa di lista completa senza continuazioni. |
| Player/coda | Seek da frecce, etichette ai comandi, coda lazy | Feedback persistente su buffering/errore e chiarezza tra preferiti locali e YouTube. La coda TV oggi permette il salto, non editing completo. |
| Download/Lidarr | Distinzione fra destinazione locale e server; anteprima album singolo | Stati durevoli, annullamento, byte/spazio e conferma del candidato effettivamente inviato. Più album sono richiesti in sequenza con riepilogo finale. |
| Impostazioni | Segreti mascherati, stato collegamento, verifica del server | URL validati, simboli completi, errori comprensibili e comportamento esplicito quando si conserva una credenziale cambiando host. |
| Libreria/offline/backup | DAO distinti, snapshot Isar, possibilità di rollback | Testare file assenti, ripristino fallito e servizi che mantengono riferimenti al vecchio DB; separare backup dati da segreti. |
| Lettura dal divano | Buona gerarchia nelle pagine album e contrasto del testo secondario sui fondi | Sottotitoli 13 px ed etichette player 11 px sono piccoli: verifica reale a 2–3 metri, testo ingrandito e nomi lunghi. |

## Aspetti da conservare

- Separazione del motore audio, coda, resolver e gestione errori; generazioni del player già presenti per evitare alcune risposte obsolete.
- Retry con backoff e limite di errori consecutivi: la strategia esiste e va completata nella cancellazione.
- Liste/griglie costruite progressivamente in molte viste; `memCacheWidth` per le copertine TV.
- Focus TV condiviso, bordi visibili e disattivazione delle scorciatoie desktop in modalità TV.
- Connettori Jellyfin/Lidarr con client HTTP iniettabile, adatto a test senza server reali.
- Timeout presenti nella maggior parte delle richieste di metadati e distinguibilità iniziale delle autenticazioni fallite.
- Rollback previsto dal ripristino, file legacy conservati dopo migrazione e sistema di plugin isolato in Rust/WASM. Le garanzie vanno verificate con test d'errore.

## Ordine di intervento

1. **Blocco stabilità e dati:** R01–R06, R10, R20–R21. Cancellazione retry, download atomici, rollback, offline affidabile e test effettivi. Non aggiornare indiscriminatamente tutte le dipendenze.
2. **Blocco accessibilità e input:** R07–R08, R12, R15–R16. Adattamento dei vincoli, contrasto e semantica. La skill `impeccable` suggerisce `harden`, `adapt` e `clarify` per questi interventi.
3. **Blocco dati remoti:** R09, R11, R13–R14, R17–R19, R22. Paginazione, isolamento sessioni, rete osservabile e avvio resiliente; poi `optimize` su misure reali.
4. **Rifinitura:** `impeccable polish` dopo le correzioni e nuova review per controllarne gli effetti. Le 20 evoluzioni di prodotto sono in [PIANO_20_FUNZIONALITA.md](PIANO_20_FUNZIONALITA.md).

## Collaudo richiesto prima di dichiarare stabile una release

| Scenario | Esito richiesto |
| --- | --- |
| Chromecast/Google TV ARMv7 e TV ARM64 | Installazione, avvio, focus e riproduzione; aggiungere Fire TV solo con test del relativo motore vocale e WebView. |
| Telecomando: 100 passi, pressioni lunghe e doppio OK | Nessun focus invisibile, salto involontario, attivazione doppia o blocco; includere menu, righe virtualizzate, dialoghi, player e Back. |
| Viewport logici piccoli/grandi e testo 150% | Tastiera e azioni utilizzabili; nessun overflow. |
| Rete persa, server lento, 401/403/429/5xx | Errore comprensibile, retry limitato e annullabile; nessuna ripartenza dopo Stop. |
| Logout con richieste pendenti | Nessun contenuto della vecchia sessione né cookie nel backup ordinario. |
| Download interrotto, omonimi e spazio pieno | Nessuna sovrascrittura, file parziale riconoscibile e possibilità di riprendere/annullare. |
| 1.000 album / playlist di più pagine | Tutti gli elementi raggiungibili, conteggi corretti, focus conservato durante la paginazione. |
| Backup valido/corrotto e rollback fallito | Dati originali recuperabili; nessun successo dichiarato in anticipo. |
| Due ore di audio, crossfade, standby/resume | Nessun crash/ANR, comportamento audio coerente e memoria senza crescita continua. Misurare frame time e memoria su hardware reale. |
| Aggiornamento APK con stessa firma | Dati e sessioni conservati, ABI corretta e comportamento di errore verificato con firma incompatibile. |

Questa attività corregge la documentazione e consegna evidenze e piano. I difetti dell'app descritti qui restano da implementare e ricollaudare.
