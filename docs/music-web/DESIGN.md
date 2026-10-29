# music.fabiodalez.it — progetto

Web app di musica che sostituisce Monochrome su `music.fabiodalez.it`. Motore: il bridge YouTube Music di Bloomee (`webos/bridge.py`) portato a Python 3. Interfaccia e funzioni: riprese da Mochy Music (Kotlin/Compose, GPL-3.0, https://github.com/realidkroo/Mochy-Music). Nessuna parte locale (niente Jellyfin, Lidarr, download sul dispositivo).

## Decisioni

- **Hosting**: cPanel `fabiodalez.it` (LiteSpeed + CloudLinux). Il selettore Python è disattivato per l'account, quindi l'app gira con Passenger configurato a mano.
- **Multiutente**: account propri del server, password scrypt, sessioni in cookie `HttpOnly; Secure; SameSite=Lax`, registrazione solo con codice d'invito generato dall'amministratore. Niente Firebase.
- **Dati**: SQLite in `~/music-app/data/music.db` (WAL), fuori dalla docroot.
- **Temi**: scuro, chiaro, automatico (segue il sistema); accento dinamico preso dalla copertina in entrambi.

## Ambiente sul server (verificato il 2026-10-29)

- App: `~/music-app` (`passenger_wsgi.py`), venv `~/music-app/venv` da `/opt/alt/python311` (3.11.18).
- `~/music-app/venv/bin/lswsgi` compilato da `wsgi-lsapi-2.1` con gli header di CPython 3.11 e `libpython3.11.so.1.0` di `/opt/alt`; lanciato da `~/music-app/run-lswsgi`.
- `~/music.fabiodalez.it/.htaccess`: `PassengerAppRoot`, `PassengerBaseURI "/"`, `PassengerPython "/home/fabiodal/music-app/run-lswsgi"`.
- Riavvio: `touch ~/music-app/tmp/restart.txt` e `pkill -u fabiodal -f lswsgi`.

## Vincoli misurati

- **YouTube dall'IP del cPanel**: VISIONOS (con `visitorData` anonimo) dà flussi completi, Range a metà file → 206. IOS e ANDROID_VR rifiutano (403) oltre il primo MB: solo riserva.
- **Gli URL googlevideo sono legati all'IP** del server: l'audio passa tutto dal proxy.
- **LiteSpeed bufferizza l'intera risposta WSGI** (anche con `X-Accel-Buffering: no` e blocchi da 64 KB). Niente streaming continuo né SSE: il proxy audio risponde a **pezzi Range limitati** (1 MB, primo pezzo più piccolo per partire prima), che `<audio>` richiede da solo. Misurato: ~1,1–1,4 s per MB, circa 50 s di Opus 160 kbps.
- La prima richiesta dopo un avvio a freddo può superare 15 s: risoluzione con tentativi e cache di `visitorData` e URL.

## Server

- `engine/innertube.py`: client WEB_REMIX per search, browse, next (radio), suggerimenti; account opzionale per utente via cookie (SAPISIDHASH), salvato cifrato.
- `engine/player.py`: risoluzione VISIONOS → IOS → ANDROID_VR, scelta itag (Opus 251 poi AAC 140), cache fino a 5 min prima della scadenza, rifiuti ricordati 10 min.
- `engine/lyrics.py` (da Mochy): LRCLIB, BetterLyrics, SimpMusic, KuGou; sincronizzati per riga e, dove c'è, per parola.
- `api/`: JSON sotto `/api/*`, audio sotto `/audio/<id>`, tutto dietro sessione; limiti di richieste per utente.
- `db.py`: utenti, inviti, sessioni, preferiti, playlist e brani, cronologia, coda salvata, impostazioni.

## Interfaccia (Svelte + Vite → file statici serviti da LiteSpeed)

Da Mochy: Home a righe, Esplora, ricerca con suggerimenti e filtri, pagine artista/album/playlist, player a schermo intero con copertina grande e testi sincronizzati, mini‑player, libreria a schede, statistiche stile Recap, equalizzatore a 10 bande (Web Audio, preset e regolazione manuale; i profili AutoEq per cuffia non ci sono ancora), crossfade, timer di spegnimento. Media Session API per tasti multimediali e schermata di blocco. PWA installabile. Desktop e mobile, mouse/touch/tastiera.

Fuori: Apple Music (Widevine), download locali, Jellyfin/Lidarr. Possibile in seguito: fonte lossless Tidal (modulo monochrome di Mochy).

## Stato (2026-10-29)

Online su https://music.fabiodalez.it. Codice in `music-web/`:

- `server/` — WSGI senza dipendenze oltre a `cryptography`: `musicweb/youtube.py` (motore), `auth.py`, `library.py`, `lyrics.py`, `app.py` (rotte). Test: `server/.venv/bin/python -m unittest tests.test_server` (con `LIVE=1` anche YouTube, BetterLyrics e LRCLIB veri). Sviluppo locale: `server/devserver.py` (porta 8799) e `ui/dist`.
- `ui/` — Svelte 5 + Vite, font Roboto Flex (OFL). Google Sans Flex di Mochy **non** è open source: non usarlo.
- `deploy/deploy.sh` — test, build, rsync di server e interfaccia, `.htaccess`, riavvio e verifica. Non tocca `~/music-app/data`, venv e lswsgi.
- Amministrazione da shell: `ssh fabiodalez.it 'cd music-app && venv/bin/python manage.py users|invite|set-password|admin|disable'`.

## Primo avvio e account YouTube

- Wizard per ogni utente (`ui/src/screens/Onboarding.svelte`, flag `settings.onboarded`): benvenuto, nome, tema, YouTube Music, importazione (brani che ti piacciono → preferiti, playlist → copie locali, album e artisti salvati → preferiti), artisti preferiti, riproduzione automatica e crossfade. Si riapre da Impostazioni → Profilo.
- YouTube Music si collega in due modi (`ui/src/components/YouTubeConnect.svelte`):
  - **codice tipo TV** (`server/musicweb/oauth.py`): device flow di Google con scope `youtube`; token Bearer su InnerTube WEB_REMIX, rinnovato da solo. Richiede un client OAuth «TV e dispositivi con input limitato» creato dall'amministratore (Impostazioni → Accesso a YouTube con codice), salvato in `data/google-oauth.json` (0600). Con la schermata di consenso in modalità test, gli account vanno aggiunti come utenti di test (massimo 100). Non ancora verificato con un client vero: se YouTube Music rifiuta il token, l'errore lo dice e resta il cookie.
  - **cookie** incollato dagli strumenti per sviluppatori, cifrato con Fernet.

## Trappole scoperte

- **Misure delle copertine**: il server immagini di Google risponde solo a certe misure e cambiano da immagine a immagine (96, 256, 320, 344 a volte danno errore). Sicure: 60, 120, 160, 226, 544, 720, 1200 (`ui/src/lib/format.js`); se una fallisce si riprova con l'URL originale.
- **CORS sulle immagini**: le richieste `crossOrigin` del browser a `yt3.googleusercontent.com` ricevono 429. Il colore della copertina passa da `/api/thumb` (solo host di immagini Google, 60 px).
- **Ricerca "Tutto"**: da ottobre 2026 YouTube Music la restituisce come elenco piatto di `itemSectionRenderer`, più la scheda del risultato migliore; le sezioni con titolo esistono solo nei filtri.
- **Passenger su /api**: il prefisso può arrivare in `SCRIPT_NAME`; `Request.path` li ricompone.
- **Riavvio**: `pkill -f '[l]swsgi'`, non `pkill -f lswsgi` (ucciderebbe la shell SSH che lo esegue).
