# Rete Casa

App macOS SwiftUI (SwiftPM, nessuna dipendenza) per diagnosticare la rete di casa (Starlink + 2 mesh, Fire Stick, Synology/Plex). Struttura copiata da port-manager/crocini: `Sources/ReteCasa`, `Scripts/build_app.sh`, `Resources/Info.plist`.

- Bundle id `com.federicomancinelli.retecasa`. Repo GitHub previsto: `friconelli/rete-casa` (da creare; finché non esiste l'Updater tratta il 404 come «aggiornato»).
- Build **universale** (arm64 + x86_64), target macOS 13: niente API più nuove senza `#available`.
- Livelli: `Shell.swift` (processi con timeout) → `Network.swift` (ping, Wi‑Fi via `system_profiler -json`, `networkQuality -c -s`, scansione ARP+porte) e `FireStick.swift` (ADB) → `Diagnosis.swift` (regole pure: `Snapshot` → `[Finding]`) → `AppModel.swift` (stato, azioni) → viste.
- Le regole di `Diagnosis` vengono dalle prove fatte a mano: router senza perdite + internet con perdite = Starlink; ping al router alto = Wi‑Fi del Mac/di casa; Fire Stick sotto ‑72 dBm = agganciato al nodo lontano.
- Il Fire Stick si riconosce da porte 5555/55443/60000; router/mesh dal prefisso MAC `74:24:9f`. I nodi Starlink visti vengono salvati in UserDefaults (`knownNodes`) per segnalare un mesh scomparso.
- `networksetup -setairportnetwork` da processo fallisce con -3900: per il Mac si usa lo spegni/riaccendi (`-setairportpower`).
- Prove senza finestra: `ReteCasa --selftest [--fs IP] [--speed]`; istantanea: `--snapshot out.png --wait 30 --page <status|devices|fireStick|mac|monitor|activity>`.
- **Icona**: generata con Codex, artwork a tutto campo senza bordi (la tessera la compone `make_icon.sh`). Nel Bash tool `cp` è interattivo: usare `/bin/cp -f`.
- Il test di velocità e la velocità del Fire Stick saturano la linea: mai lanciarli in automatico, né durante uno streaming.
- **Flusso**: `AppModel.runFullCheck()` esegue i passaggi (`steps`) e poi `recompute()` → `Diagnosis.analyze`. Ogni `Finding` può avere una `FindingAction` (`AppModel.perform`) mostrata come pulsante in `FindingRow`.
- **Nodi Starlink**: salvati in UserDefaults (`knownNodeInfo`: MAC → ultimo IP; `nodeNames`) e mostrati anche se spenti. Un'azione che riavvia il Wi‑Fi (Mac o Fire Stick) interrompe la rete/riproduzione: chiedere conferma per il Fire Stick.
