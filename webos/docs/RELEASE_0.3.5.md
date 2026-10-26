# Bloomee LG 0.3.5: telecomando Android

- Nuova voce **Impostazioni → Telecomando dal cellulare** per abbinare Bloomee Remote.
- API LAN nativa `/pair`, `/state`, `/command`, porta 18794. Codice di sei cifre per cinque minuti, token casuale in memoria per dodici ore, cinque tentativi errati, revoca esplicita.
- La pagina LG pubblica solo titolo, artista, tempi, volume e coda (primi 500). Comandi validati e confermati dalla pagina prima di rispondere al telefono; nessun URL audio, cookie o token Jellyfin esce dal bridge.
- Riproduci/pausa, precedente/successivo, posizione, volume del player, casuale, ripeti coda e selezione di un elemento della coda.
- Il bridge locale passa alla versione 7 per sostituire una versione precedente rimasta attiva.

Verifiche: test Python con richieste HTTP reali, test JavaScript della mailbox e sanitizzazione, audit del focus su 34 schermate in Chromium con abbinamento, comando volume e revoca, APK Android su emulatore collegato al ricevitore Python con riproduzione simulata. La prova su LG fisica resta da fare.

Sorgenti precedenti importati dal checkout locale Bloomee webOS, commit `0e5c6f3`, versione 0.3.4. Le configurazioni esistenti in `/var/lib/bloomee-webos` restano separate dal pacchetto.
