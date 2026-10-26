# Bloomee LG 0.4.0

Estende Bloomee Remote con ricerca, apertura/riproduzione di playlist YouTube Music e Jellyfin e gestione di playlist locali sulla TV. Per il telefono usare Bloomee Remote 1.1.0.

Il bridge passa alla versione 8 e aggiunge `/browse` autenticato. Il catalogo e i brani restano nella pagina LG: il bridge passa soltanto identificativi temporanei e metadati filtrati. Mentre una ricerca è in corso, la pagina continua a pubblicare lo stato del player. I comandi non vengono ripetuti dopo errori di trasporto.

Playlist locali: creazione, salvataggio della coda, aggiunta di brani o playlist, rimozione e rinomina. Persistono nel localStorage dell'app; gli account esterni non vengono modificati. La ricerca è paginata e segnala le sorgenti che non rispondono. Il contenuto delle playlist Jellyfin usa il relativo endpoint per conservarne l'ordine.

Test del catalogo e della persistenza, sanitizzazione delle risposte HTTP e controllo in Chromium di ricerca dal telefono, salvataggio della coda e revoca. Non ancora provato su TV LG fisica.
