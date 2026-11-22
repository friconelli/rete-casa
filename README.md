# Rete Casa

App macOS (SwiftUI, SwiftPM, nessuna dipendenza, macOS 13+) che controlla la rete di casa (router Starlink, mesh, Fire Stick, NAS) e dice **dove sta il problema**: Starlink, Wi‑Fi di casa, un mesh spento o la chiavetta agganciata al nodo sbagliato.

## Funzioni
- **Stato**: un unico pulsante, **Analisi completa**, fa in sequenza quello che si farebbe a mano: Wi‑Fi del Mac, ping a router e internet, scansione dei dispositivi, router e mesh Starlink, Fire Stick, Synology/Plex (e, se lo spunti, la velocità). Ogni passaggio mostra il suo esito.
- **Cosa non va**: i problemi trovati, in italiano semplice, ciascuno con il pulsante per provare a risolverlo (cerca connessione migliore, riconnetti il Fire Stick, cerca segnale migliore, rifai l'analisi).
- **La tua rete**: mappa con Internet, router e mesh (anche quando uno è spento: resta in elenco come «non risponde») e i dispositivi (Fire Stick, Synology/Plex, Mac). I nodi si possono rinominare in **Dispositivi** (es. «Mesh salone»).
- **Diagnosi**: confronta i ping verso router e verso internet. Router senza perdite ma internet con perdite = è Starlink; ping al router instabile = è il Wi‑Fi di casa. Segnala un mesh che non risponde e un Fire Stick agganciato al nodo sbagliato.
- **Fire Stick** (via ADB): segnale, banda, collegamento, ping, app in primo piano, velocità reale; **«Riconnetti Fire Stick»** (cerca di nuovo l'indirizzo e riprova 6 volte) e **«Cerca segnale migliore»** (riavvia il suo Wi‑Fi fino a 5 volte finché supera la soglia).
- **Wi‑Fi del Mac**: dettagli e **«Cerca connessione migliore»** (riavvia il Wi‑Fi fino a 4 volte finché passa ai 5 GHz o a un segnale forte); elenco reti salvate.
- **Monitor**: ping leggeri con grafico, da tenere acceso durante una partita (non occupa la linea).

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
./.build/debug/ReteCasa --snapshot out.png --wait 30 [--page status]   # PNG della finestra
```
L'app è firmata ad‑hoc: al primo avvio clic destro → Apri.

## Aggiornamenti
All'avvio controlla le GitHub Releases di `friconelli/rete-casa`; se c'è una versione più nuova propone di aggiornare e riavviare. Controllo manuale: **Rete Casa → Verifica aggiornamenti…**. Per pubblicare: `git tag v1.1.0 && git push origin v1.1.0` (GitHub Actions compila e carica `ReteCasa.zip`).

## Icona
Generata con Codex (`codex exec`, prompt in `icon/PROMPT_CODEX.md`): artwork a tutto campo in `icon/ReteCasa-art.png`; `Scripts/make_icon.sh` compone la tessera arrotondata e produce `Resources/AppIcon.icns`.
