import Foundation

/// Tutto ciò che è stato misurato finora.
struct Snapshot {
    var wifi: WiFiInfo?
    var router: PingStats?
    var internet: PingStats?
    var speed: SpeedResult?
    var bestDownMbps: Double?
    var devices: [LANDevice] = []
    var knownNodeMACs: Set<String> = []
    var fireStick: FireStickStatus?
    var plexOK: Bool?
}

struct Verdict {
    var severity: Severity
    var headline: String
    var detail: String
}

/// Le regole sono quelle emerse dai controlli fatti a mano: separano "problema di Starlink"
/// da "problema del Wi‑Fi di casa" confrontando ping verso router e verso internet.
enum Diagnosis {
    static func analyze(_ s: Snapshot) -> [Finding] {
        var out: [Finding] = []
        let routerOK = s.router.map { !$0.isUnreachable && $0.loss <= 1 } ?? false

        // Starlink / internet
        if let net = s.internet {
            if net.isUnreachable {
                out.append(Finding(severity: .bad, area: .starlink, title: "Internet non raggiungibile",
                                   detail: routerOK ? "Il router risponde ma non esce su internet."
                                                    : "Non risponde nemmeno il router: il problema è nel collegamento Wi‑Fi del Mac.",
                                   suggestion: routerOK ? "Controlla l'app Starlink: ostruzioni, interruzioni, meteo." : "Riconnetti il Wi‑Fi del Mac."))
            } else if routerOK && net.loss >= 3 {
                out.append(Finding(severity: .bad, area: .starlink,
                                   title: "Starlink perde pacchetti (\(fmt(net.loss))%)",
                                   detail: "Il router di casa risponde senza perdite, ma verso internet se ne perde una parte: il limite è il collegamento col satellite.",
                                   suggestion: "Guarda nell'app Starlink le interruzioni e le ostruzioni. Da casa non si risolve."))
            } else if routerOK, let r = s.router, net.avg - r.avg > 120 {
                out.append(Finding(severity: .warn, area: .starlink, title: "Latenza alta verso internet (\(fmt(net.avg)) ms)",
                                   detail: "Il router è veloce, ma il tratto verso internet è lento.",
                                   suggestion: "Di solito è la rete Starlink in un momento di carico."))
            } else {
                out.append(Finding(severity: .ok, area: .starlink, title: "Collegamento a internet stabile",
                                   detail: "Latenza media \(fmt(net.avg)) ms, \(fmt(net.loss))% di pacchetti persi."))
            }
        }

        if let sp = s.speed {
            let pct = s.bestDownMbps.flatMap { $0 > 0 ? Int(sp.downMbps / $0 * 100) : nil }
            let ref = pct.map { " (\($0)% del massimo che hai misurato)" } ?? ""
            if sp.downMbps < 8 {
                out.append(Finding(severity: .bad, area: .starlink, title: "Velocità molto bassa: \(fmt(sp.downMbps)) Mbps",
                                   detail: "Troppo poco anche per uno streaming in HD\(ref).",
                                   suggestion: "Controlla l'app Starlink (ostruzioni, orario di punta, pioggia)."))
            } else if sp.downMbps < 25 {
                out.append(Finding(severity: .warn, area: .starlink, title: "Velocità bassa: \(fmt(sp.downMbps)) Mbps",
                                   detail: "Basta per una partita in HD ma con poco margine\(ref).",
                                   suggestion: "Durante lo streaming non usare altra rete in casa."))
            } else {
                out.append(Finding(severity: .ok, area: .starlink, title: "Velocità buona: \(fmt(sp.downMbps)) Mbps",
                                   detail: "In upload \(fmt(sp.upMbps)) Mbps\(ref)."))
            }
        }

        // Wi‑Fi del Mac
        if let w = s.wifi {
            if w.rssi < -72 {
                out.append(Finding(severity: .warn, area: .macWiFi, title: "Segnale Wi‑Fi del Mac debole (\(w.rssi) dBm)",
                                   detail: "Sei collegato in \(w.band.rawValue), canale \(w.channel).",
                                   suggestion: "Avvicinati a un mesh o usa «Riconnetti Wi‑Fi» per rifare la scelta del nodo."))
            } else if w.band == .ghz24 && w.linkMbps < 150 {
                out.append(Finding(severity: .info, area: .macWiFi, title: "Il Mac è sui 2,4 GHz",
                                   detail: "Collegamento a \(w.linkMbps) Mbps: più lento dei 5 GHz.",
                                   suggestion: "«Riconnetti Wi‑Fi» spesso lo riporta sui 5 GHz."))
            } else {
                out.append(Finding(severity: .ok, area: .macWiFi, title: "Wi‑Fi del Mac a posto",
                                   detail: "\(w.band.rawValue), canale \(w.channel), \(w.rssi) dBm, collegamento \(w.linkMbps) Mbps."))
            }
        }
        if let r = s.router, !r.isUnreachable, (r.loss > 2 || r.avg > 80) {
            out.append(Finding(severity: .warn, area: .macWiFi, title: "Wi‑Fi di casa instabile verso il router",
                               detail: "Ping al router: \(fmt(r.avg)) ms in media, \(fmt(r.loss))% persi. Il problema è dentro casa, non in Starlink.",
                               suggestion: "Riconnetti il Wi‑Fi o avvicinati a un nodo mesh."))
        }

        // Mesh
        let nodes = s.devices.filter(\.isStarlinkNode)
        if !s.devices.isEmpty {
            let current = Set(nodes.map(\.mac))
            let missing = s.knownNodeMACs.subtracting(current)
            if !missing.isEmpty {
                out.append(Finding(severity: .bad, area: .mesh,
                                   title: missing.count == 1 ? "Un nodo Starlink non risponde" : "\(missing.count) nodi Starlink non rispondono",
                                   detail: "Mancano: \(missing.sorted().joined(separator: ", ")). Era visibile nelle scansioni precedenti.",
                                   suggestion: "Stacca la corrente al mesh per 10 secondi e riattaccala."))
            } else if nodes.isEmpty {
                out.append(Finding(severity: .info, area: .mesh, title: "Nessun dispositivo Starlink riconosciuto",
                                   detail: "La scansione non ha trovato indirizzi Starlink."))
            } else {
                let meshCount = nodes.filter { $0.kind == .mesh }.count
                out.append(Finding(severity: .ok, area: .mesh, title: "Router e \(meshCount) mesh online",
                                   detail: nodes.map { "\($0.kind == .router ? "Router" : "Mesh") \($0.ip)" }.joined(separator: " · ")))
            }
        }

        // Fire Stick
        if let f = s.fireStick {
            let rssi = f.rssi ?? -127
            if rssi < -72 {
                out.append(Finding(severity: .bad, area: .fireStick, title: "Fire Stick con segnale debole (\(rssi) dBm)",
                                   detail: "Probabilmente è agganciato a un nodo lontano. Collegamento a \(f.linkMbps ?? 0) Mbps, \(f.band.rawValue).",
                                   suggestion: "Usa «Cerca segnale migliore»: riavvia il Wi‑Fi della chiavetta finché trova un nodo vicino."))
            } else if rssi < -67 {
                out.append(Finding(severity: .warn, area: .fireStick, title: "Segnale del Fire Stick appena sufficiente (\(rssi) dBm)",
                                   detail: "\(f.band.rawValue), collegamento a \(f.linkMbps ?? 0) Mbps.",
                                   suggestion: "Prova «Cerca segnale migliore»."))
            } else {
                out.append(Finding(severity: .ok, area: .fireStick, title: "Fire Stick ben collegato (\(rssi) dBm)",
                                   detail: "\(f.band.rawValue), collegamento a \(f.linkMbps ?? 0) Mbps."))
            }
            if let p = f.ping, !p.isUnreachable {
                if p.loss >= 3 {
                    out.append(Finding(severity: .bad, area: .fireStick, title: "Il Fire Stick perde pacchetti (\(fmt(p.loss))%)",
                                       detail: "Ping verso internet dalla chiavetta: \(fmt(p.avg)) ms in media, picchi a \(fmt(p.max)) ms.",
                                       suggestion: "Se il Mac non ne perde, il problema è il Wi‑Fi della chiavetta: cambia nodo."))
                } else if p.avg > 100 {
                    out.append(Finding(severity: .warn, area: .fireStick, title: "Latenza alta sul Fire Stick (\(fmt(p.avg)) ms)",
                                       detail: "Può causare blocchi nelle dirette."))
                }
            }
            if let d = f.downMbps {
                out.append(Finding(severity: d < 8 ? .bad : d < 25 ? .warn : .ok, area: .fireStick,
                                   title: "Velocità reale del Fire Stick: \(fmt(d)) Mbps",
                                   detail: "Scaricamento misurato direttamente dalla chiavetta."))
            }
        }

        // NAS
        if let ok = s.plexOK {
            out.append(ok
                ? Finding(severity: .ok, area: .nas, title: "Plex risponde in rete locale", detail: "Il server è raggiungibile.")
                : Finding(severity: .bad, area: .nas, title: "Plex non risponde", detail: "Il NAS è acceso ma Plex non risponde sulla porta 32400.",
                          suggestion: "Riavvia Plex dal Centro pacchetti del Synology."))
        }
        return out.sorted { $0.severity > $1.severity }
    }

    static func verdict(_ findings: [Finding]) -> Verdict {
        guard let worst = findings.first else {
            return Verdict(severity: .info, headline: "Nessuna misura ancora", detail: "Premi «Misura ora» per cominciare.")
        }
        let bad = findings.filter { $0.severity == .bad }
        if bad.isEmpty, worst.severity < .warn {
            return Verdict(severity: .ok, headline: "Tutto a posto", detail: "Nessun problema rilevato nelle misure fatte.")
        }
        let areas = Set(bad.map(\.area))
        if areas == [.starlink] || (areas.isEmpty && findings.filter({ $0.severity == .warn }).allSatisfy { $0.area == .starlink }) {
            return Verdict(severity: worst.severity, headline: "Il problema è Starlink, non la rete di casa",
                           detail: worst.title + ". La rete dentro casa funziona.")
        }
        if let a = bad.first?.area ?? findings.first(where: { $0.severity == .warn })?.area {
            return Verdict(severity: worst.severity, headline: "Il problema è: \(a.rawValue)", detail: worst.title + ".")
        }
        return Verdict(severity: worst.severity, headline: worst.title, detail: worst.detail)
    }

    static func fmt(_ v: Double) -> String { v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "") }
}
