> Stato successivo: implementati gli MVP F01–F14, F18 e F19; F15–F17 e F20 restano nel piano. Dettagli e limiti in [IMPLEMENTAZIONE_E_VERIFICHE.md](IMPLEMENTAZIONE_E_VERIFICHE.md).

# Piano di 20 funzionalità aggiuntive per Bloomee TV

Data: 19 ottobre 2026. Riferimento: [review di usabilità e stabilità](REVIEW_USABILITA_STABILITA.md), base Git `1c1b4aa` e working tree esaminato.

L'obiettivo è rendere semplice iniziare ad ascoltare, gestire libreria e download dal divano e recuperare gli errori senza usare ADB. L'utente di riferimento usa una TV condivisa, un telecomando a cinque tasti e, facoltativamente, YouTube Music, Jellyfin e Lidarr in rete domestica. Le preferenze estetiche non sono state oggetto di un'intervista: questo è un piano funzionale ricavato dall'app esistente.

Le funzionalità seguenti sono **proposte, non implementate**. Ricerca vocale, testi sincronizzati, equalizzatore, crossfade, preferiti locali, ripristino della coda e timer esistono già nel core o nell'interfaccia ereditata: il piano non li conta nuovamente come novità. Le estensioni TV indicano esplicitamente cosa aggiungono.

## Prima delle nuove funzionalità

Serve una fase di consolidamento, separata dalle 20 proposte: cancellazione dei retry audio, download Jellyfin atomici, protezione dei segreti, rollback affidabile, fallback per file offline assenti, correzione dei test e CI effettiva. Vanno inoltre sistemati contrasto, tastiera e caricamento completo degli elenchi. Sono difetti dell'esistente, non nuove funzioni.

**Condizione di partenza:** test Flutter e Rust significativi verdi, analisi senza warning, build Android riproducibile e prove D-pad su almeno Google TV ARMv7 e un dispositivo TV ARM64. Il test di migrazione richiede anche di chiarire il supporto degli ID legacy. Il riferimento pratico per il collaudo è la matrice in fondo alla review.

Per dimensionare il lavoro si assume uno sviluppatore con esperienza Flutter/Rust, riuso del motore e dei DAO esistenti e nessun servizio cloud proprietario. Le stime sono giorni di sviluppo per MVP e test mirati; escludono provisioning hardware, attese di servizi esterni e QA trasversale. Aggiungere circa il 25% per integrazione, accessibilità e collaudo. L'ordine è per valore e dipendenze, non una promessa di date.

## Indice e ordine consigliato

| # | Funzionalità | Priorità | Stima MVP | Dipendenze |
| --- | --- | --- | --- | --- |
| F01 | Configurazione iniziale guidata per TV | Alta | 2–3 gg | Consolidamento |
| F02 | Configurazione da telefono con QR e abbinamento | Alta | 5–8 gg | Segreti protetti, F01 |
| F03 | Ricerca unificata con filtri avanzati | Alta | 4–6 gg | Paginazione e stati sorgente corretti |
| F04 | Esplorazione Jellyfin per genere, anno e iniziale | Alta | 3–5 gg | Paginazione Jellyfin corretta |
| F05 | Editor della coda da telecomando | Alta | 3–5 gg | Retry audio corretto |
| F06 | Editor playlist completo per TV | Alta | 4–7 gg | F05, persistenza verificata |
| F07 | Centro operazioni Locale e Lidarr | Alta | 5–8 gg | Download affidabili, F10 |
| F08 | Gestione spazio con quote e pulizia guidata | Alta | 3–5 gg | F07 |
| F09 | Preferenze di accessibilità specifiche per TV | Alta | 4–6 gg | Contrasto, tastiera e semantica corretti |
| F10 | Diagnostica consultabile ed esportabile | Alta | 3–5 gg | Redazione dei segreti |
| F11 | Home personalizzabile | Media | 3–5 gg | F03, F04 |
| F12 | Profili domestici separati | Media | 8–12 gg | Migrazioni verificate, F01, F10 |
| F13 | Raccolta preferiti unificata fra sorgenti | Media | 5–8 gg | F03, F12 |
| F14 | Catalogo consultabile offline con stato di freschezza | Media | 4–7 gg | F04, F08, F12 |
| F15 | Più sessioni di ascolto e segnalibri | Media | 3–5 gg | F05, F12 |
| F16 | Modalità testi da divano con offset regolabile | Media | 3–5 gg | F09 |
| F17 | Preset audio TV per dispositivi e contesti | Media | 3–5 gg | F09, F12 |
| F18 | Spegnimento dopo il brano/album con dissolvenza | Media | 2–4 gg | Retry e Stop corretti, F05 |
| F19 | Volume percepito più uniforme | Esplorativa | 5–8 gg | F17, prove audio dedicate |
| F20 | Coda condivisa per ospiti tramite telefono | Esplorativa | 6–10 gg | F02, F05, F12 |

## Specifiche degli MVP

### F01. Configurazione iniziale guidata per TV

**Valore:** arrivare al primo ascolto senza dover capire plugin, server e differenza tra le due librerie.

**Novità rispetto a oggi:** l'onboarding generico esiste; si aggiunge un percorso TV orientato alle scelte “Ascolta online”, “Collega Jellyfin”, “Ho già un server Lidarr”, con tutti i servizi saltabili. Spiegare Locale/Lidarr e preferiti locali/YouTube nel punto in cui servono. Mostrare prova del telecomando e collegamento al recupero in caso di plugin non disponibile.

**Implementazione:** stato a passi riprendibile usando `OnboardingService`, `TvConfig` e il bootstrap esistente; azioni di verifica idempotenti, senza doppia installazione dei plugin. Aggiungere “Riapri configurazione” nelle impostazioni.

**Accettazione:** percorso completabile soltanto con D-pad; Back non cancella impostazioni già salvate; possibile proseguire senza account e recuperare dopo perdita di rete. Obiettivo da validare con utenti: prima traccia entro due minuti in condizioni di rete normali, esclusi login esterni.

### F02. Configurazione da telefono con QR e abbinamento

**Valore:** evitare di digitare URL e chiavi lunghe dal telecomando.

**MVP:** la TV mostra QR e codice temporaneo; il telefono abbinato può inviare URL/configurazione o testo a un campo selezionato. La TV mostra cosa sta per salvare e può interrompere la sessione. Limitare inizialmente a un telefono e rete locale, senza account cloud.

**Implementazione:** servizio locale con sessione autenticata, scadenza, limitazione dei tentativi e arresto quando si chiude l'abbinamento. Il QR non deve contenere segreti durevoli. Il trasporto dei segreti deve essere protetto: validare prima un canale cifrato utilizzabile dai browser previsti, oppure escludere le credenziali dalla prima versione e usare il telefono solo per testo non sensibile. Non esporre una pagina HTTP anonima di amministrazione. Google continua a usare il proprio flusso: non introdurre un modulo che raccolga la password Google.

**Accettazione:** codici scaduti/errati e client non abbinati non possono leggere o modificare dati; nessuna chiave nei log; una riconnessione non duplica il salvataggio. Test su due browser mobili e su rete che isola i client, con errore comprensibile.

### F03. Ricerca unificata con filtri avanzati

**Valore:** trovare rapidamente una specifica versione senza cercare in ogni catalogo separatamente.

**Novità:** ricerca YouTube e riga Jellyfin esistono. Si aggiungono filtro sorgente, presenza locale, anno/versione, ordinamento e raggruppamento dei duplicati con scelta esplicita della versione. Mantenere tracce live e studio distinte.

**Implementazione:** risultati con identità sorgente e sessione di ricerca; fan-out controllato ai connettori e query locale ai DAO; continuazioni indipendenti, caricamento parziale e cache con chiavi comprensive di filtri. Le capacità non offerte da una sorgente vanno mostrate correttamente, senza promettere filtri lato server inesistenti.

**Accettazione:** query rapida A→B non riporta A; un server indisponibile non nasconde gli altri; filtri conservati tornando da un album; tutte le pagine accessibili senza perdere il focus.

### F04. Esplorazione Jellyfin per genere, anno e iniziale

**Valore:** rendere usabile una grande collezione senza scrivere titoli.

**Novità:** alle schede Recenti/Album A–Z/Artisti/Casuali si aggiungono indice alfabetico, generi, decenni, ordinamento persistente e percorso di navigazione. Il superamento del limite 400 è una correzione preliminare.

**Implementazione:** estendere `JellyfinClient` con pagine, conteggi e filtri supportati dal server; UI progressiva e ripristino di sezione/posizione. Ricavare i filtri dal catalogo effettivo.

**Accettazione:** 1.000 album percorribili con salti alfabetici; lettere senza risultati non bloccano; filtro anno combinabile con genere; contenuti non latini raggiungibili e ordinamento riproducibile.

### F05. Editor della coda da telecomando

**Valore:** correggere la prossima musica senza interrompere l'ascolto.

**Novità:** la coda TV oggi permette di scegliere un brano. Aggiungere “Riproduci dopo”, “Sposta su/giù”, “Rimuovi”, selezione multipla e “Salva come playlist”.

**Implementazione:** azioni esplicite su `QueueManager`, selezione per ID stabile e indice di occorrenza, modalità spostamento con OK/frecce/Back, annullamento dell'ultima modifica. Operazioni atomiche se nel frattempo cambia il brano.

**Accettazione:** tutti i comandi funzionano senza drag; riordino e rimozione conservano il brano corrente; duplicati intenzionali gestiti correttamente; Back annulla lo spostamento; annullamento ripristina l'ordine.

### F06. Editor playlist completo per TV

**Valore:** creare e curare raccolte dal divano.

**Novità:** CRUD e import playlist esistono nelle schermate ereditate. Si aggiunge un flusso TV uniforme per nome, copertina, ricerca interna, selezione multipla, riordino e duplicazione.

**Implementazione:** riusare `PlaylistDAO` e `TrackDAO`, componenti di editing di F05 e tastiera corretta; transazioni, nomi univoci, salvataggio esplicito e conferma delle eliminazioni. L'MVP modifica playlist locali, senza promettere scrittura di quelle YouTube.

**Accettazione:** playlist vuota e da 1.000 tracce modificabili con D-pad; riavvio mantiene ordine e copertina; eliminare una playlist non elimina tracce condivise con altre raccolte.

### F07. Centro operazioni Locale e Lidarr

**Valore:** sapere cosa è stato richiesto, cosa sta scaricando e cosa è pronto.

**Novità:** Scaricati e progresso del download manager esistono; il nuovo centro collega trasferimenti locali e richieste Lidarr con stati persistenti distinti: preparazione, richiesto, ricerca, trasferimento, importazione, pronto, errore.

**Implementazione:** adattatori verso eventi Rust e query Lidarr, record persistente per richiesta, polling solo quando serve, backoff e collegamento al contenuto in Jellyfin quando realmente individuato. Esporre limiti di ciò che il server comunica. Non presentare l'accettazione del comando come file disponibile.

**Accettazione:** una richiesta resta visibile dopo riavvio; retry non duplica l'album; annullamento locale lascia il file coerente; errore del server conserva dettagli utili e permette un'azione. L'eventuale annullamento Lidarr deve specificare se annulla solo la ricerca o anche il download gestito esternamente.

### F08. Gestione spazio con quote e pulizia guidata

**Valore:** evitare che i download saturino lo spazio limitato di un Chromecast.

**MVP:** spazio libero, totale per album/sorgente, quota configurabile, elenco dei contenuti da rimuovere e protezione dei preferiti scelti dall'utente. Separare cache delle immagini, cataloghi e audio scaricato.

**Implementazione:** inventario DB/filesystem, pulizia atomica con riconciliazione dei record e soglia minima prima di iniziare un trasferimento. Non cancellare automaticamente musica protetta o in riproduzione.

**Accettazione:** con spazio insufficiente il download si ferma prima della scrittura; eliminazione aggiorna elenco e contatore; file assente non impedisce la pulizia; cancellazione della cache non rimuove audio offline.

### F09. Preferenze di accessibilità specifiche per TV

**Valore:** rendere l'app leggibile a distanza e utilizzabile con esigenze diverse.

**Novità:** aggiungere impostazioni TV per dimensione testo, contrasto elevato, focus più marcato, riduzione di scale/animazioni e velocità di ripetizione dei tasti. Correggere contrasto e semantica di base resta un requisito per tutti, indipendente da questa modalità.

**Implementazione:** token TV derivati da preferenze e impostazioni di sistema; componenti con label/ruolo/stato e anteprima regolazioni. Conservare sempre un'azione per tornare ai valori leggibili.

**Accettazione:** testo al 150% senza azioni tagliate; controllo con TalkBack di menu, card, tastiera e player; nessuna animazione di scala quando disabilitata; il focus è riconoscibile anche senza distinguere il rosa.

### F10. Diagnostica consultabile ed esportabile

**Valore:** capire se un problema riguarda rete, server, plugin, spazio o audio e inviare un bug riproducibile.

**MVP:** stato dei servizi, versione app/plugin, ultimo errore, spazio e test guidati non distruttivi. Esportazione manuale di un rapporto ridotto; nessuna telemetria remota automatica.

**Implementazione:** errori tipizzati, buffer limitato e redazione prima della persistenza di cookie, Authorization, API key, query token e percorsi privati. Usare dati di F07; evitare che la diagnosi faccia partire download o modifichi server.

**Accettazione:** rapporto d'esempio con segreti sintetici non contiene nessuno di essi; errori classificati senza mostrare stack trace come istruzioni per l'utente; timeout e “annulla test” funzionano. L'esportazione richiede un'azione dell'utente e mostra il contenuto condiviso.

### F11. Home personalizzabile

**Valore:** trovare subito la musica rilevante per quel salotto.

**MVP:** fissare playlist, artisti e album, ordinare o nascondere le righe e scegliere la sezione iniziale. Nascondere un servizio scollegato senza impedire di riconfigurarlo.

**Implementazione:** configurazione Home versionata, componenti TV di riordino e riferimenti stabili ai contenuti; placeholder utilizzabile per elementi rimossi o temporaneamente irraggiungibili.

**Accettazione:** personalizzazione persistente; riavvio e cambio sorgente non perdono i pin; un contenuto non più disponibile può essere rimosso senza aprirlo; modalità modifica chiaramente distinta dall'ascolto.

### F12. Profili domestici separati

**Valore:** separare cronologie, preferiti e impostazioni di chi condivide la TV.

**MVP:** profili locali con nome/avatar, selettore rapido e profilo ospite senza storico durevole. Scegliere esplicitamente se e quali server vengono condivisi; cookie Google separati per profilo.

**Implementazione:** `profileId` nei dati pertinenti, migrazione del DB esistente in un profilo iniziale, credenziali protette per profilo, cache e notifier isolati. Cambiare profilo deve definire il destino della riproduzione in corso e dei download condivisi.

**Accettazione:** nessuna cronologia o cookie del profilo A nella UI/cache/export di B; migrazione senza duplicazioni; logout di un profilo non scollega gli altri; ospite pulito all'uscita. Un PIN locale può proteggere le impostazioni, senza presentarlo come isolamento di sistema.

### F13. Raccolta preferiti unificata fra sorgenti

**Valore:** salvare “questo album” senza dover ricordare dove è stato trovato.

**Novità:** i preferiti locali esistono. Aggiungere entità unificata con più versioni/sorgenti, badge “sul server”, “offline”, “online”, scelta della sorgente predefinita e risoluzione manuale dei duplicati.

**Implementazione:** livello di identità sopra gli ID dei connettori, collegamenti verificabili per artista/album/durata e possibilità di separare un raggruppamento errato. Preferire automaticamente una sorgente soltanto con regola visibile e modificabile.

**Accettazione:** album omonimi di artisti diversi non si fondono; live e studio restano distinguibili; scollegando un servizio non si perde il preferito; il significato del cuore rimane esplicitamente locale. Sincronizzazione in scrittura con YouTube fuori dall'MVP.

### F14. Catalogo consultabile offline con stato di freschezza

**Valore:** sfogliare la libreria e trovare i download anche quando il server non risponde.

**Novità:** cache plugin e ascolto offline esistono; si aggiunge una cache consultabile delle viste TV Jellyfin/YouTube, con indicazione dell'ultimo aggiornamento e filtro dei contenuti effettivamente riproducibili offline.

**Implementazione:** snapshot paginati per profilo/sorgente, TTL e aggiornamento in background; quota da F08. Cache metadati separata dai file audio. Svuotare i dati account alla disconnessione secondo policy esplicita.

**Accettazione:** avvio senza rete mostra il catalogo già acquisito e la sua data; un elemento non scaricato non appare come riproducibile offline; aggiornamento non sposta il focus; logout non conserva liste private consultabili da altri profili.

### F15. Più sessioni di ascolto e segnalibri

**Valore:** alternare un album, una lunga playlist e un ascolto condiviso senza perdere la posizione.

**Novità:** il ripristino di una singola coda esiste. Aggiungere più sessioni salvate con titolo, coda, posizione, modalità e data, più segnalibri su singole tracce.

**Implementazione:** snapshot versionati per profilo con limite numerico; ri-risoluzione delle sorgenti all'apertura, senza conservare URL firmati scaduti. Mostrare eventuali brani mancanti prima di ripartire.

**Accettazione:** ripresa di due sessioni distinte dopo riavvio; nessuna riproduzione automatica solo aprendo l'elenco; una sorgente scollegata offre sostituzione o salto esplicito; posizione valida anche se cambia la durata dichiarata.

### F16. Modalità testi da divano con offset regolabile

**Valore:** seguire i testi comodamente o correggere una sincronizzazione imperfetta.

**Novità:** testi sincronizzati e fullscreen esistono. Aggiungere dimensione/righe regolabili, offset per brano, contrasto dedicato e comandi da telecomando per attivare/disattivare lo scorrimento automatico.

**Implementazione:** estensione di `LyricsCubit` e fullscreen lyrics, offset locale persistito per ID traccia/versione e layout con animazioni ridotte. Nessuna nuova promessa di copertura dei testi: dipende dai provider.

**Accettazione:** offset applicato senza alterare la posizione audio; reset immediato; testi mancanti/non sincronizzati spiegati; nomi lunghi, RTL e cambio brano non bloccano i comandi.

### F17. Preset audio TV per dispositivi e contesti

**Valore:** scegliere facilmente una resa per casse TV, soundbar o ascolto serale.

**Novità:** equalizzatore a 10 bande e preset nel core esistono. Aggiungere un flusso TV con confronto immediato originale/preset, preset personali nominati e assegnazione per profilo/contesto di ascolto. Non dichiarare correzione acustica automatica.

**Implementazione:** riusare `PlayerEngine` e impostazioni EQ; controlli da frecce, guadagno limitato e nessun cambiamento brusco del volume. Ridurre le scritture mentre si tiene premuta una freccia.

**Accettazione:** cambio preset coerente durante crossfade e fra i due player; nessun blocco col D-pad; bypass ripristina i valori senza perderli; gain massimo documentato e controllato.

### F18. Spegnimento dopo il brano/album con dissolvenza

**Valore:** terminare l'ascolto in un punto naturale senza troncare il brano.

**Novità:** il timer generico esiste. Aggiungere opzioni TV “dopo questo brano”, “alla fine di questo album” e dissolvenza finale, con conto alla rovescia visibile e annullabile.

**Implementazione:** estendere il timer esistente con condizioni sulla coda e stato audio, non con un secondo timer indipendente. Gestire esplicitamente repeat, crossfade, skip e ripresa dopo standby.

**Accettazione:** la condizione scatta una sola volta; nessun retry fa ripartire l'audio dopo la fine; annullamento ripristina il volume; standby non lascia un timer applicato al profilo successivo.

### F19. Volume percepito più uniforme

**Valore:** ridurre i salti fastidiosi tra tracce da sorgenti diverse.

**MVP:** preferenza opt-in che usa gain di loudness disponibile nei metadati, con target e limiti conservativi. Se manca il dato, usare bypass dichiarato. Il processamento/analisi dei file locali può essere una seconda fase, evitando analisi costose dei flussi in tempo reale nell'MVP.

**Implementazione:** prima uno spike per verificare i metadati e il supporto effettivo del motore sulle piattaforme target; poi pipeline di gain compatibile con EQ, volume utente e crossfade. Non sommare due normalizzazioni della stessa sorgente.

**Accettazione:** campione audio di riferimento con loudness diverso, nessun clipping introdotto e confronto livello/peak misurato; comportamento coerente nei due player e bypass istantaneo. Se lo spike non dimostra un percorso affidabile, rinviare la funzione senza aggiungere un interruttore inefficace.

### F20. Coda condivisa per ospiti tramite telefono

**Valore:** permettere agli ospiti di proporre musica senza passarsi il telecomando o accedere agli account della TV.

**MVP:** sessione locale temporanea aperta dalla TV, telefono abbinato che cerca e propone un brano, approvazione del proprietario o regola di aggiunta limitata. Nessuna lettura di cronologia, credenziali o raccolte private; nessun controllo amministrativo al telefono ospite.

**Implementazione:** riusare abbinamento F02 e operazioni coda F05, con capability ristrette, limiti di richieste/coda, duplicati controllati e revoca immediata. La TV resta titolare dell'audio. Fuori dall'MVP: casting universale, multiroom e account ospite cloud.

**Accettazione:** due telefoni possono proporre senza sovrascriversi; ospite revocato non invia comandi; sessione scaduta non si riapre automaticamente; nessun guest legge token o cambia server; traffico eccessivo non rende il D-pad inutilizzabile.

## Rilasci proposti

| Passaggio | Contenuto | Criterio di uscita |
| --- | --- | --- |
| Consolidamento | Correzioni della review e CI | Matrice di base superata; nessuna nuova funzione mescolata al recupero dati. |
| A: ingresso e controllo | F01, F02, F05, F09, F10 | Primo ascolto, input da telecomando/telefono e diagnosi comprensibili; abbinamento protetto. |
| B: catalogo e gestione | F03, F04, F06, F07, F08 | Collezioni grandi, playlist e operazioni lunghe utilizzabili e persistenti. |
| C: esperienza domestica | F11, F12, F13, F14, F15 | Isolamento profili, Home personale e dati offline coerenti. |
| D: ascolto e ospiti | F16, F17, F18, F19, F20 | Prove audio, timer/standby e accesso ospiti superati; F19 subordinata allo spike. |

Ogni passaggio può uscire in più release piccole. F10 precede l'integrazione finale di F07; F02 può inizialmente essere limitata a testo non sensibile se il trasporto protetto non è pronto. Evitare di avviare profili e cache offline prima di stabilire il nuovo modello dati, altrimenti serviranno migrazioni duplicate.

## Verifiche comuni e misure di successo

- Tutte le funzioni hanno un percorso completo con frecce, OK e Back, compresi errore, vuoto e caricamento. Conservare focus e selezione dopo paginazione o aggiornamento.
- Testare 854×480, 960×540 e 1280×720 logici, testo al 150%, nomi lunghi, contenuti non latini, 1.000 album e code con duplicati.
- Testare rete lenta/assente, sessione scaduta, risposte fuori ordine, spazio pieno e riavvio durante un'operazione. Nessun risultato vecchio dopo logout o cambio profilo.
- Per operazioni sensibili, testare segreti assenti da log/backup, abbinamento scaduto e rollback conservato. Nessuna telemetria esterna necessaria per misurare gli MVP.
- Raccogliere in prove moderate: tempo al primo ascolto, numero di pressioni per trovare un album e successo nel correggere la coda. Confrontare con una misura iniziale dell'app attuale; non esistono ancora baseline misurate.
- Obiettivi tecnici da verificare su hardware, non risultati già ottenuti: nessun crash/ANR nel test di due ore, nessuna crescita continua della RAM e risposta visiva al D-pad entro 100 ms nelle operazioni locali. Separare latenza dell'interfaccia e attesa del servizio remoto.

La prima decisione di prodotto suggerita è iniziare da F01, F05 e F10 dopo il consolidamento: riducono difficoltà di ingresso e assistenza, migliorando anche la capacità di valutare tutte le funzioni successive.
