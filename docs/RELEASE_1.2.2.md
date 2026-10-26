# Bloomee TV 1.2.2 con Bloomee Remote

Questa versione aggiunge il ricevitore LAN per l'app Android Bloomee Remote e conserva tutte le correzioni della 1.2.1: artista negli album YouTube Music, pagine di ricerca in ritardo e radio automatica della coda precedente.

La prima compilazione locale 1.2.2, build base 1202, usava ancora i sorgenti 1.2.0. Usare la ricompilazione con build base **1203**, versionCode **2203** su ARMv7 e **3203** su ARM64. Il pacchetto completo e gli APK nella cartella `build/Bloomee-Remote` vengono sostituiti con quelli corretti. Bloomee Remote 1.0.0 e Bloomee LG 0.3.5 non cambiano.

Package TV `it.fabiodalez.bloomeetv`, firma release locale uguale alla 1.2.1; Android 7/API 24 o successivo. Per aggiornare scegliere l'ABI del dispositivo e installare in place, senza disinstallare. Il verificatore `tool/install_tv_apk.py` controlla package, firma, versione e ABI prima dell'installazione.

Il telecomando si attiva in **Centro TV → telefono → Collega Bloomee Remote**. Il telefono e la TV devono essere sulla stessa rete. Indirizzo e codice permettono di controllare riproduzione, coda, posizione e volume del player. La scelta di nuovi album e playlist avviene sulla TV.

Il telecomando è stato provato con test automatici e con l'app Android su emulatore collegata al protocollo HTTP LG. La prova su televisori Android TV e LG fisici resta da fare.
