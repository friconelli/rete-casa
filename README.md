# Rete Casa

App macOS (SwiftUI, SwiftPM, nessuna dipendenza, macOS 13+) che controlla la rete di casa (router Starlink, mesh, Fire Stick, NAS) e dice **dove sta il problema**: Starlink, Wi‑Fi di casa, un mesh spento o la chiavetta agganciata al nodo sbagliato.

## Funzioni
- **Panoramica**: Wi‑Fi del Mac (banda, canale, segnale), ping a router e internet, velocità (test di Apple), Fire Stick, numero di dispositivi Starlink.
- **Diagnosi**: regole che confrontano ping verso router e verso internet. Router senza perdite ma internet con perdite = è Starlink; ping al router instabile = è il Wi‑Fi di casa. Segnala anche un mesh che non risponde più e permette di copiare il report.
- **Dispositivi**: scansione della rete locale; riconosce router/mesh Starlink (indirizzo del costruttore 74:24:9f), NAS con Plex e Fire TV.
- **Fire Stick** (via ADB): segnale, banda, velocità del collegamento, ping, app in primo piano, velocità reale scaricando 25 MB dalla chiavetta, e **«Cerca segnale migliore»**: riavvia il suo Wi‑Fi (fino a 5 volte) finché si aggancia a un segnale sopra la soglia.
- **Wi‑Fi del Mac**: dettagli e «Riconnetti Wi‑Fi» (spegne/riaccende per rifare la scelta di nodo e banda); elenco reti salvate.
- **Monitor**: ping leggeri ogni pochi secondi con grafico, da tenere acceso durante una partita (non occupa la linea).

## Limiti
- Starlink non permette di scegliere il nodo mesh a cui si collega un dispositivo: l'app può solo far rifare la scelta (riconnessione) finché il segnale è buono.
- Il cambio rete del Mac dal programma può essere rifiutato da macOS (errore -3900): in quel caso si usa il menu Wi‑Fi.
- Il **test di velocità** e la velocità reale del Fire Stick occupano la linea per 15‑20 s: non usarli durante uno streaming.
- Per il Fire Stick serve `adb` (`brew install --cask android-platform-tools`) e il Debug ADB attivo sulla chiavetta.

## Build
```bash
swift build                          # sviluppo
./Scripts/build_app.sh --install     # app universale (arm64 + x86_64) in /Applications
./.build/debug/ReteCasa --selftest [--fs 192.168.1.x] [--speed]   # misure da terminale, senza finestra
./.build/debug/ReteCasa --snapshot out.png --wait 30 [--page diagnosis]   # PNG della finestra
```
L'app è firmata ad‑hoc: al primo avvio clic destro → Apri.

## Aggiornamenti
All'avvio controlla le GitHub Releases di `friconelli/rete-casa`; se c'è una versione più nuova propone di aggiornare e riavviare. Controllo manuale: **Rete Casa → Verifica aggiornamenti…**. Per pubblicare: `git tag v1.1.0 && git push origin v1.1.0` (GitHub Actions compila e carica `ReteCasa.zip`).

## Icona
Generata con Codex (`codex exec`, prompt in `icon/PROMPT_CODEX.md`): artwork a tutto campo in `icon/ReteCasa-art.png`; `Scripts/make_icon.sh` compone la tessera arrotondata e produce `Resources/AppIcon.icns`.
