# Implementazione e verifiche — 19 ottobre 2026

## Incidente durante la prova sul dispositivo

Il primo APK release è stato installato sul Chromecast con `adb install -r`, firma verificata, conservando i dati. Il successivo tentativo di eseguire direttamente `flutter test -d` ha prodotto un APK universale con versionCode 2, inferiore al versionCode 1002 dell’APK ARMv7 installato. Dopo il rifiuto Android, Flutter ha automaticamente disinstallato l’app prima di riprovare. Il test è stato interrotto; i dati locali originali sono risultati rimossi. Non è stato trovato un backup completo del Chromecast sul computer.

Con autorizzazione esplicita dell’utente è stata esportata una copia dalla Fire TV. Il database è stato validato su una copia isolata: contiene i collegamenti Jellyfin/Lidarr, 3 playlist standard vuote e nessun brano, download, cronologia o accesso Google. Prima del ripristino è stato archiviato lo stato del Chromecast, quindi la copia validata è stata trasferita con controllo SHA-256 e sostituzione atomica. Jellyfin è nuovamente collegato sul Chromecast e il catalogo è visibile. Questo è un recupero parziale dei collegamenti, non dei dati locali originali. L’eventuale accesso Google non è stato recuperato. Le copie sono conservate fuori dal repository in una cartella privata; gli export temporanei sulla Fire TV sono stati rimossi dopo la verifica, senza cambiare il suo database.

Questo è un errore operativo della verifica, non un effetto delle migrazioni dell’app. `tool/install_tv_apk.py` ora verifica firma, package, versione e ABI e non contiene alcun percorso di disinstallazione/downgrade. Il test del player usa file WAV diagnostici temporanei e può collegarsi tramite `flutter drive --use-existing-app`, dopo installazione manuale verificata. Non affidare a Flutter l’installazione sopra dati da conservare.

## Funzionalità

| ID | MVP nel codice | Accesso e limite principale |
|---|---|---|
| F01 | Guida riapribile e servizi facoltativi | Home / Centro TV → guida |
| F02 | QR, codice, sessione temporanea, conferma testo | Centro TV → telefono; solo testo non segreto sulla LAN |
| F03 | Ricerca locale/Jellyfin/YouTube/plugin, filtri e varianti | Errori indipendenti; anno solo se presente nei metadati |
| F04 | Jellyfin paginato, genere/anno/iniziale/ordine persistenti | I filtri riflettono il catalogo del server |
| F05 | Coda: sposta, seleziona/rimuovi, annulla, salva | Player → Modifica coda; ordine manuale disattiva shuffle |
| F06 | CRUD playlist, copertina, ricerca e riordino | Centro TV → playlist; playlist locali |
| F07 | Operazioni persistenti, progressi, annulla/riprova, stato Lidarr | Lidarr accettato non equivale a file pronto |
| F08 | Quota, riserva di spazio, file protetti ed eliminazione | Centro TV → spazio; nessuna eliminazione automatica della libreria |
| F09 | Testo 100/125/150%, contrasto/focus, animazioni, ripetizione frecce | Centro TV → accessibilità; tastiera e componenti testati anche a 854×480 |
| F10 | Diagnostica limitata, redazione e anteprima export | Centro TV → diagnostica; errori sanitizzati prima dell’inserimento |
| F11 | Ordine/visibilità/inizio righe e contenuti fissati | Personalizza / pressione prolungata sulla copertina |
| F12 | Database, credenziali, catalogo, preferenze e download per profilo | Cambio interrompe audio/operazioni; pulizia ospite |
| F13 | Preferiti con varianti, sorgente preferita, unisci/separa | Centro TV → preferiti; nessuna scrittura su account YouTube |
| F14 | Cataloghi visitati offline con data effettiva | Errori di autenticazione non usano la cache |
| F18 | Timer durata/fine brano/fine album, dissolvenza e annulla | Timer unico con l’interfaccia ereditata; arresta audio, non la TV |
| F19 | ReplayGain su entrambi i player | Opt-in; tag del file, clipping protetto, fallback 0 dB |

F15, F16, F17 e F20 non fanno parte della selezione implementata.

## Correzioni rispetto alla review

- R01: retry cancellati/generazionali per stop, pausa, cambio tentativo e successo.
- R02/R10: trasferimento TV unico, file per ID, timeout, quota, file temporanei e registrazione solo dopo completamento.
- R03/R13: vault Android Keystore, migrazione dopo scrittura riuscita, binding dei token al server, import validato prima dell’applicazione e rimozione del file solo dopo successo; backup senza credenziali.
- R04: validazione isolata del backup prima della sostituzione, rollback preservato se non riapribile; attesa delle copie Isar.
- R05: verifica fisica del file offline e normale risoluzione online se manca.
- R06/R20/R21: test reali, libreria Isar host, alias download legacy, contratto corretto del test Rust; CI esegue test e Clippy.
- R07/R08/R15/R16: tastiera adattiva, contrasto, semantica/azioni puntatore, simboli, cursore e cancellazione per grafema.
- R09: paginazione completa Jellyfin/YouTube con deduplicazione e arresto dei token ripetuti.
- R11/R12/R17: generazioni delle richieste, invalidazione al cambio account, controlli mounted, risultati/errori per sorgente e stati Lidarr espliciti.
- R14: errore aggiornamenti distinto da “aggiornato”, selezione ABI e numero build base esplicito.
- R18/R19: trasporto HTTP riutilizzato; normalizzazione Unicode, matching prudente degli artisti brevi e conferma ID Lidarr.
- R22: UI di avvio/riprova con conservazione dei dati; operazioni di rete non essenziali fuori dal percorso bloccante.

La verifica ha inoltre corretto pulizie Isar non attese e completato il drenaggio delle scritture prima del cambio profilo.

## Notifica Android e Cast

La schermata dell’utente mostrava “Bloomee TV / Chromecast” senza metadati. La sessione TV originale aveva già titolo/artista: quindi la loro presenza locale non dimostrava il funzionamento della notifica remota.

Sono stati aggiunti il collegamento Cast Connect alla sessione audio esistente, DISPLAY_ICON_URI/MEDIA_URI, aggiornamento della durata effettiva, header per le copertine Jellyfin e pubblicazione limitata della copertina corrente per client che non possono usare header/file locali. Nessuna credenziale finisce nell’URL pubblicato.

Un ricevitore Cast completo richiede anche sender compatibile e registrazione Google del package/dispositivo per installazioni sideload. Non può sostituire il receiver ID di YouTube o altre app. [Documentazione Google](https://developers.google.com/cast/docs/android_tv_receiver/core_features).

## Esiti

- Flutter: 96 test automatici passati nell’ultima esecuzione host, comprese migrazione, coda, backup/rollback, vault, cache/profili, pairing, ricerca, download/quota, tastiera, isolamento dei DAO, pulizia immagini e timer. Analisi statica: zero errori e warning; rimangono segnalazioni informative di stile.
- Python: 5 test dell’installatore passati (aggiornamento valido e rifiuti per downgrade/firma/ABI/package).
- Rust: 3 test passati. Clippy termina, con avvisi esistenti.
- Chromecast: editor aperto e riordino verificato anche nel passaggio effettivo al brano successivo. Test di integrazione con tre WAV temporanei passato: riordino/annulla, riproduzione nativa, metadati, ReplayGain su entrambi i player, collegamento alla sessione Cast e arresto tramite timer. La fixture viene rimossa al termine. Due test Android nativi passati sul dispositivo: cifratura/persistenza e isolamento per profilo delle credenziali, origine HTTPS esatta per il login. Al termine è stata reinstallata la release e verificata l’assenza del ribbon DEBUG.
- Notifica del telefono: l’utente ha confermato che resta “Bloomee TV / Chromecast” anche con la build 1005; problema aperto. Cast da un sender reale: verifica completa ancora pendente. La pubblicazione dei campi sulla TV non basta a dichiararli risolti sul telefono.

I controlli remoti su Lidarr vengono testati con risposte simulate; non sono stati richiesti nuovi album sul server per fare le prove.

## Correzioni dopo la prova dell’utente sul Chromecast

La ricerca caricava automaticamente tutte le continuazioni YouTube e plugin, e tutti i risultati Jellyfin, prima di pubblicare la sorgente. Questo poteva richiedere minuti. Ora pubblica la prima pagina per sorgente, continua soltanto con “Altri risultati” e applica un limite di risposta di 12 secondi. Le sorgenti completate rimangono visibili anche se un’altra non risponde. Il filtro Jellyfin scompare quando il servizio non è configurato. Le raccolte e le discografie mantengono il caricamento completo previsto.

Il richiamo iniziale alla guida viene registrato alla prima comparsa, non a ogni avvio; le installazioni già configurate lo saltano e la guida resta nel Centro TV. “Annulla” nella ricerca vocale usa il componente TV con un solo sistema di evidenziazione; l’annullamento scarta anche le parole parziali. Anche la schermata di avvio nasconde esplicitamente il banner debug.

La release ARMv7 build 1004 è stata compilata e installata con controllo firma/versione/ABI, mantenendo la stessa installazione del recupero. Sul Chromecast sono stati verificati Home senza richiamo iniziale né ribbon DEBUG e pulsante vocale senza doppio bordo. Nella ricerca reale “Ramones”, la schermata acquisita a 14 secondi dall’invio mostrava risultati e nessuna sorgente ancora in caricamento; a 5 secondi risultavano ancora in corso le sorgenti remote. È una singola prova sulla rete corrente, non una garanzia di tempo per ogni ricerca. Gli screenshot della prova restano in `/tmp/bloomeetv-1004-*.png` e `/tmp/bloomeetv-search-at-*.png` sul computer di lavoro.

## Secondo intervento sulla ricerca e sulla notifica — build 1005

La prova dell’utente ha confermato che 14 secondi restavano troppi. Sono stati eliminati ulteriori costi:

- Le richieste iniziano prima del salvataggio delle preferenze e della verifica dei file scaricati. La verifica locale avviene nella propria sorgente.
- Brani e artisti partono per primi. Album/playlist iniziano dopo il primo risultato utile, oppure dopo un massimo di due secondi se la prima fase è lenta. Nessuna sorgente attende il completamento delle altre.
- Jellyfin chiede pagine da 20 risultati e non calcola il conteggio totale. Nella ricerca globale non viene interrogato due volte lo stesso catalogo YouTube tramite client diretto e plugin.
- Le risposte di ricerca sono conservate per due minuti solo in memoria, con invalidazione al cambio account/profilo. Non riscrivono la cache offline.
- Il catalogo persistente è separato in `tv-catalog.json`: le preferenze non riscrivono megabyte di catalogo. Migrazione atomica dal vecchio file, serializzazione/controllo dei limiti in isolate e nessuna ricostruzione della Home per ogni risposta della cache.
- I modelli dei risultati vengono decodificati una volta sola, anziché ripetutamente durante filtri e rendering. I filtri sono richiudibili; i primi quattro brani sono righe compatte, gli altri si espandono. La paginazione è in fondo ai risultati.

Misure sulla release ARMv7 nel Chromecast reale, ricerca nuova `nirvana`: artisti disponibili al controller in **655 ms**, brani in **770 ms**, album/playlist entro **1375 ms**. Seconda ricerca della stessa query dopo scadenza della cache: **658/775 ms** per artisti/brani. Ripetizione immediata: brani **46 ms**, tutte le sorgenti entro **100 ms**. I tempi sono registrati senza includere il testo della query nei log. Sono prove puntuali sulla rete corrente; non garantiscono la latenza di ogni servizio. Il test widget verifica che il primo titolo sia raggiungibile e visibile nel viewport TV senza scorrimento.

Per la notifica sono stati consultati Context7 (`/websites/developers_google_cast`) e i riferimenti ufficiali di [Cast Connect](https://developers.google.com/cast/docs/android_tv_receiver/core_features), [MediaInfoModifier](https://developers.google.com/android/reference/com/google/android/gms/cast/tv/media/MediaInfoModifier) e [notifiche condivise di Google](https://support.google.com/chromecast/answer/7206638?hl=en).

Una lettura effettiva del protocollo Cast, prima della modifica, mostrava già titolo e un’immagine, ma `metadataType: 0` (generico). Il collegamento locale alla MediaSession quindi non dimostrava una notifica completa. Ora il bridge pubblica esplicitamente `MEDIA_TYPE_MUSIC_TRACK` (3), titolo/artista/album e immagini pubblicamente leggibili senza credenziali, trasmettendo gli aggiornamenti dei modifier come richiesto dall’SDK. Dopo l’installazione, una lettura Cast durante la riproduzione ha confermato **tipo 3, titolo, album e un’immagine**. Due nuovi test Kotlin JVM verificano i valori musicali e il rifiuto di URL locali o con credenziali. È stato inoltre corretto il parser YouTube che poteva interpretare “18K riproduzioni” come artista; i vecchi elementi già salvati in coda non vengono riscritti automaticamente.

La scheda condivisa sul telefono è gestita da Google: la documentazione ne descrive dispositivo, fornitore e comandi, senza promettere tutti i metadati. Il formato Cast è ora verificato sulla rete, ma l’utente ha confermato che la notifica continua a mostrare “Bloomee TV / Chromecast”: il problema non è risolto. L’utente ha scelto di mantenere solo l’app TV, senza aggiungere un controller per telefono.

## Categorie visibili e focus della ricerca, build 1006

“Tutto”, “Brani”, “Album” e “Artisti” restano immediatamente sotto la barra di ricerca, anche con i filtri chiusi. Le playlist e i filtri aggiuntivi rimangono in “Filtri”. Gli artisti erano presenti nei risultati, ma la selezione rapida era stata nascosta insieme ai filtri: ora è sempre accessibile. Il pulsante “Parla” ha autofocus ed è il primo elemento interattivo della pagina, quindi anche l’ingresso tramite la shell TV lo seleziona.

Barra, categorie e risultati condividono i margini orizzontali da 48 punti; i pulsanti sono separati da 12 punti e la barra dalle categorie da 16. I test verificano allineamento e accessibilità a 960×540, primo titolo visibile senza scorrimento, risultati artista e focus iniziale/ingresso shell.

Sulla build 1006 installata nel Chromecast è stata verificata la riga completa sotto la barra, con il pulsante “Parla” evidenziato all’ingresso dal menu. Nei log delle ricerche reali della stessa build: brani in 572 ms, artisti in 586 ms, album in 1027 ms; una ricerca dedicata agli artisti ha restituito Jellyfin in 124 ms e YouTube in 486 ms. Sono misure puntuali, non garanzie sulla rete. Nessun errore fatale o eccezione Flutter non gestita nei log filtrati della prova.

Verifica finale: suite host di 96 test passata; dopo l’ultimo allineamento del messaggio vuoto sono stati ripetuti e superati i 18 test della ricerca, inclusi i tre nuovi casi per categorie/spaziature, focus e risultati artista.

APK ARMv7 finale compilato e installato in place con controllo firma, versione e ABI. Il dispositivo conferma versionCode 1006 e lo stesso firstInstallTime precedente all’aggiornamento. Dopo l’ultimo allineamento è stata nuovamente verificata la ricerca aperta dal menu: categorie visibili, messaggio vuoto allineato e focus su “Parla”. Screenshot locale: `/tmp/bloomeetv-1006-final-search.png`. Analisi finale: zero errori/warning, 251 segnalazioni informative.

## Pubblicazione 1.2.0

La release pubblica usa versione 1.2.0+7 (ARMv7 versionCode 1007), con lo stesso codice funzionale verificato nella build 1006. Per il pacchetto di pubblicazione sono stati ripetuti i 96 test Flutter e l’analisi statica (zero errori/warning, 251 info), quindi compilato l’APK release ARMv7. Verificati package, versione, ABI, assenza del flag debuggable e firma identica alle release precedenti. APK e SHA256SUMS.txt sono allegati alla release GitHub; il file locale tv-env.sh resta fuori dalla pubblicazione.
