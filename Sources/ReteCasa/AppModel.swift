import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // Misure
    @Published var wifi: WiFiInfo?
    @Published var router: PingStats?
    @Published var internet: PingStats?
    @Published var speed: SpeedResult?
    @Published var devices: [LANDevice] = []
    @Published var nodes: [NodeStatus] = []
    @Published var fireStick: FireStickStatus?
    @Published var fireStickProblem: String?
    @Published var plexOK: Bool?
    @Published private(set) var findings: [Finding] = []
    @Published var lastUpdated: Date?

    // Analisi completa
    @Published var steps: [CheckStep] = []
    @Published var includeSpeed = false

    // Attività in corso
    @Published var busy: Set<String> = []
    @Published var log: [String] = []

    // Fire Stick
    @Published var fireStickIP: String { didSet { defaults.set(fireStickIP, forKey: "fireStickIP") } }
    @Published var connectResult: ConnectResult?
    @Published var switchAttempts: [SwitchAttempt] = []
    @Published var switchMessage = ""
    @Published var recoveryMessage = ""
    @Published var minRSSI: Int { didSet { defaults.set(minRSSI, forKey: "minRSSI") } }

    // Mac
    @Published var savedNetworks: [String] = []
    @Published var macMessage = ""
    @Published var macAttempts: [String] = []

    // Nomi dei nodi Starlink (modificabili, es. «Mesh salone»)
    @Published var nodeNames: [String: String] { didSet { defaults.set(nodeNames, forKey: "nodeNames") } }

    // Monitor
    @Published var monitor: [MonitorPoint] = []
    @Published var monitoring = false
    private var monitorTask: Task<Void, Never>?
    private var switchTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard

    private struct KnownNode: Codable { var ip: String; var isRouter: Bool }
    private var knownNodeInfo: [String: KnownNode] {
        get {
            if let d = defaults.data(forKey: "knownNodeInfo"), let v = try? JSONDecoder().decode([String: KnownNode].self, from: d) { return v }
            // Migrazione dalla versione 1.0, che salvava solo i MAC.
            let old = defaults.stringArray(forKey: "knownNodes") ?? []
            return Dictionary(uniqueKeysWithValues: old.map { ($0, KnownNode(ip: "?", isRouter: false)) })
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "knownNodeInfo") }
    }
    private(set) var bestDown: Double {
        get { defaults.double(forKey: "bestDown") }
        set { defaults.set(newValue, forKey: "bestDown") }
    }

    init() {
        fireStickIP = UserDefaults.standard.string(forKey: "fireStickIP") ?? ""
        let saved = UserDefaults.standard.integer(forKey: "minRSSI")
        minRSSI = saved == 0 ? -66 : saved
        nodeNames = (UserDefaults.standard.dictionary(forKey: "nodeNames") as? [String: String]) ?? [:]
        rebuildNodes(current: [])
    }

    var verdict: Verdict { Diagnosis.verdict(findings) }
    func isBusy(_ key: String) -> Bool { busy.contains(key) }
    var adbInstalled: Bool { FireStickService.adbPath != nil }
    var anyBusy: Bool { !busy.isEmpty }

    func note(_ text: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date()))  \(text)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private func recompute() {
        findings = Diagnosis.analyze(Snapshot(
            wifi: wifi, router: router, internet: internet, speed: speed,
            bestDownMbps: bestDown > 0 ? bestDown : nil, devices: devices,
            knownNodeMACs: Set(knownNodeInfo.keys), fireStick: fireStick,
            fireStickProblem: fireStickProblem, nodeNames: nodeNames, plexOK: plexOK))
        lastUpdated = Date()
    }

    private func pingOptional(_ host: String?, count: Int) async -> PingStats? {
        guard let host else { return nil }
        return await PingService.ping(host, count: count)
    }

    // MARK: - Nodi Starlink

    func name(for mac: String) -> String { nodeNames[mac] ?? "Mesh" }

    /// Unisce i nodi visti ora con quelli noti dalle analisi precedenti.
    private func rebuildNodes(current: [LANDevice]) {
        var info = knownNodeInfo
        for d in current where d.isStarlinkNode {
            info[d.mac] = KnownNode(ip: d.ip, isRouter: d.kind == .router)
            if nodeNames[d.mac] == nil {
                nodeNames[d.mac] = d.kind == .router ? "Router" : "Mesh \(nodeNames.values.filter { $0.hasPrefix("Mesh") }.count + 1)"
            }
        }
        knownNodeInfo = info
        nodes = info.map { mac, k in
            let live = current.first { $0.mac == mac }
            return NodeStatus(mac: mac, name: nodeNames[mac] ?? "Mesh", ip: live?.ip ?? k.ip,
                              isRouter: k.isRouter, online: live != nil, latencyMs: nil)
        }
        .sorted { a, b in a.isRouter != b.isRouter ? a.isRouter : a.name < b.name }
    }

    private func pingNodes() async {
        let online = nodes.filter(\.online)
        await withTaskGroup(of: (String, Double?).self) { group in
            for n in online {
                group.addTask {
                    let p = await PingService.ping(n.ip, count: 4)
                    return (n.mac, p.isUnreachable ? nil : p.avg)
                }
            }
            for await (mac, ms) in group {
                if let i = nodes.firstIndex(where: { $0.mac == mac }) { nodes[i].latencyMs = ms }
            }
        }
    }

    func forgetKnownNodes() {
        knownNodeInfo = [:]
        nodeNames = [:]
        rebuildNodes(current: devices)
        recompute()
        note("Elenco dei nodi Starlink azzerato: ora conto solo quelli visibili.")
    }

    func forgetNode(_ mac: String) {
        var info = knownNodeInfo; info[mac] = nil; knownNodeInfo = info
        nodeNames[mac] = nil
        rebuildNodes(current: devices)
        recompute()
    }

    // MARK: - Analisi completa

    private func setStep(_ id: String, _ state: CheckStep.State, _ detail: String = "") {
        if let i = steps.firstIndex(where: { $0.id == id }) { steps[i].state = state; steps[i].detail = detail }
    }

    /// Fa in sequenza tutto quello che abbiamo fatto a mano: Wi‑Fi, ping, dispositivi, mesh, Fire Stick, Plex.
    func runFullCheck() async {
        guard !isBusy("check") else { return }
        busy.insert("check"); defer { busy.remove("check") }
        steps = [CheckStep(id: "wifi", title: "Wi‑Fi di questo Mac"),
                 CheckStep(id: "net", title: "Router e internet"),
                 CheckStep(id: "scan", title: "Dispositivi sulla rete"),
                 CheckStep(id: "mesh", title: "Router e mesh Starlink"),
                 CheckStep(id: "fs", title: "Fire Stick"),
                 CheckStep(id: "plex", title: "Synology e Plex")]
        if includeSpeed { steps.append(CheckStep(id: "speed", title: "Velocità di internet")) }
        note("Analisi completa avviata.")

        setStep("wifi", .running)
        wifi = await WiFiService.read()
        if let w = wifi {
            setStep("wifi", .done(w.rssi >= -67 ? .ok : w.rssi >= -75 ? .warn : .bad), "\(w.band.rawValue), \(w.rssi) dBm, \(w.linkMbps) Mbps")
        } else { setStep("wifi", .done(.bad), "Il Mac non è collegato al Wi‑Fi") }

        setStep("net", .running)
        let gw = await WiFiService.gateway()
        async let net = PingService.ping("1.1.1.1", count: 12)
        async let rt = pingOptional(gw, count: 12)
        internet = await net; router = await rt
        let loss = internet?.loss ?? 100
        setStep("net", .done(loss >= 3 ? .bad : (router?.avg ?? 0) > 80 ? .warn : .ok),
                "router \(router.map { Diagnosis.fmt($0.avg) } ?? "—") ms · internet \(internet.map { Diagnosis.fmt($0.avg) } ?? "—") ms · \(Diagnosis.fmt(loss))% persi")

        setStep("scan", .running)
        let found = await LANService.scan()
        devices = found
        if fireStickIP.isEmpty, let ftv = found.first(where: { $0.kind == .fireTV }) { fireStickIP = ftv.ip }
        setStep("scan", .done(.ok), "\(found.count) dispositivi")

        setStep("mesh", .running)
        rebuildNodes(current: found)
        await pingNodes()
        let down = nodes.filter { !$0.online }
        let up = nodes.filter(\.online)
        setStep("mesh", .done(down.isEmpty ? (up.isEmpty ? .warn : .ok) : .bad),
                down.isEmpty ? "\(up.count) online" : "\(down.map(\.name).joined(separator: ", ")) non risponde")

        if fireStickIP.isEmpty || !adbInstalled {
            setStep("fs", .skipped, fireStickIP.isEmpty ? "Non configurato" : "ADB non installato")
        } else {
            setStep("fs", .running)
            await readFireStick()
            if let f = fireStick, fireStickProblem == nil {
                setStep("fs", .done((f.rssi ?? -127) >= -67 ? .ok : (f.rssi ?? -127) >= -72 ? .warn : .bad), "\(f.rssi ?? 0) dBm, \(f.band.rawValue), \(f.linkMbps ?? 0) Mbps")
            } else { setStep("fs", .done(.bad), "Non raggiungibile") }
        }

        setStep("plex", .running)
        if let nas = found.first(where: { $0.kind == .nas }) {
            plexOK = await LANService.plexReachable(nas.ip)
            setStep("plex", .done(plexOK == true ? .ok : .bad), plexOK == true ? "Plex risponde" : "Plex non risponde")
        } else { plexOK = nil; setStep("plex", .skipped, "NAS non trovato") }

        if includeSpeed {
            setStep("speed", .running)
            if let r = await SpeedService.run() {
                speed = r
                if r.downMbps > bestDown { bestDown = r.downMbps }
                setStep("speed", .done(r.downMbps < 8 ? .bad : r.downMbps < 25 ? .warn : .ok), "\(Diagnosis.fmt(r.downMbps)) Mbps")
            } else { setStep("speed", .done(.warn), "Test non riuscito") }
        }
        recompute()
        note("Analisi completa terminata: \(verdict.headline)")
    }

    /// Solo il test di velocità (occupa la linea ~20 s).
    func speedTest() async {
        guard !isBusy("speed") else { return }
        busy.insert("speed"); defer { busy.remove("speed") }
        note("Test di velocità in corso (occupa la linea ~20 s)…")
        if let r = await SpeedService.run() {
            speed = r
            if r.downMbps > bestDown { bestDown = r.downMbps }
            note(String(format: "Velocità: %.1f Mbps giù, %.1f su.", r.downMbps, r.upMbps))
        } else { note("Il test di velocità non è riuscito.") }
        recompute()
    }

    func scanDevices() async {
        guard !isBusy("scan") else { return }
        busy.insert("scan"); defer { busy.remove("scan") }
        note("Cerco i dispositivi sulla rete…")
        let found = await LANService.scan()
        devices = found
        rebuildNodes(current: found)
        await pingNodes()
        if fireStickIP.isEmpty, let ftv = found.first(where: { $0.kind == .fireTV }) { fireStickIP = ftv.ip }
        if let nas = found.first(where: { $0.kind == .nas }) { plexOK = await LANService.plexReachable(nas.ip) } else { plexOK = nil }
        recompute()
        note("Trovati \(found.count) dispositivi.")
    }

    // MARK: - Azioni consigliate

    func perform(_ action: FindingAction) {
        switch action {
        case .reconnectMac: Task { await macSmartReconnect() }
        case .fireStickSwitch: fireStickSmartSwitch()
        case .recoverFireStick: Task { await recoverFireStick() }
        case .rescan: Task { await runFullCheck() }
        }
    }

    // MARK: - Fire Stick

    /// Legge lo stato; imposta `fireStickProblem` se non è raggiungibile.
    private func readFireStick() async {
        let result = await FireStickService.connect(fireStickIP)
        connectResult = result
        switch result {
        case .ok:
            fireStick = await FireStickService.status(fireStickIP)
            fireStickProblem = fireStick == nil ? "Si collega via ADB ma non risponde alle domande sul Wi‑Fi." : nil
        case .refused:
            fireStick = nil
            fireStickProblem = "La chiavetta rifiuta la connessione: è spenta o in sospensione, è fuori dal Wi‑Fi, oppure ha cambiato indirizzo o il Debug ADB è spento."
        case .unauthorized:
            fireStick = nil
            fireStickProblem = "Sulla TV deve comparire «Consentire il debug?»: spunta «Consenti sempre» e premi OK."
        case .adbMissing:
            fireStick = nil
            fireStickProblem = "ADB non è installato sul Mac."
        case .failed(let m):
            fireStick = nil
            fireStickProblem = m.isEmpty ? "Collegamento non riuscito." : m
        }
    }

    func refreshFireStick() async {
        guard !fireStickIP.isEmpty, !isBusy("firestick") else { return }
        busy.insert("firestick"); defer { busy.remove("firestick") }
        note("Mi collego al Fire Stick (\(fireStickIP))…")
        await readFireStick()
        recompute()
        note(fireStickProblem == nil ? "Fire Stick letto." : "Fire Stick non raggiungibile.")
    }

    /// Prova a ritrovare e ricollegare un Fire Stick che non risponde: ricerca di un nuovo indirizzo e più tentativi.
    func recoverFireStick() async {
        guard !isBusy("recover") else { return }
        busy.insert("recover"); defer { busy.remove("recover") }
        recoveryMessage = "Cerco la chiavetta sulla rete…"
        note(recoveryMessage)
        let found = await LANService.scan()
        devices = found
        rebuildNodes(current: found)
        if let ftv = found.first(where: { $0.kind == .fireTV }), ftv.ip != fireStickIP {
            note("Il Fire Stick ha cambiato indirizzo: \(fireStickIP) → \(ftv.ip)")
            fireStickIP = ftv.ip
        }
        guard !fireStickIP.isEmpty else {
            recoveryMessage = "Non trovo nessuna chiavetta sulla rete. Accendi la TV e controlla che sia collegata al Wi‑Fi."
            recompute(); return
        }
        for n in 1...6 {
            recoveryMessage = "Tentativo \(n) di 6: mi collego a \(fireStickIP)…"
            await readFireStick()
            if fireStickProblem == nil { break }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        recoveryMessage = fireStickProblem == nil
            ? "Fire Stick collegato: \(fireStick?.rssi ?? 0) dBm."
            : "Ancora non raggiungibile. Sveglia la TV con il telecomando e riprova."
        note(recoveryMessage)
        recompute()
    }

    func fireStickSpeedTest() async {
        guard !fireStickIP.isEmpty, !isBusy("fsspeed") else { return }
        busy.insert("fsspeed"); defer { busy.remove("fsspeed") }
        note("Misuro la velocità reale del Fire Stick (occupa la linea ~15 s)…")
        if await FireStickService.connect(fireStickIP) != .ok { note("Fire Stick non raggiungibile."); return }
        let d = await FireStickService.speedTest(fireStickIP)
        var current = fireStick
        if current == nil { current = await FireStickService.status(fireStickIP, withPing: false) }
        if var s = current { s.downMbps = d; fireStick = s }
        note(d.map { String(format: "Fire Stick: %.1f Mbps.", $0) } ?? "Test non riuscito.")
        recompute()
    }

    /// Cambia nodo al Fire Stick riavviandone il Wi‑Fi finché trova un segnale forte.
    func fireStickSmartSwitch() {
        guard !fireStickIP.isEmpty, switchTask == nil else { return }
        busy.insert("switch")
        switchAttempts = []
        switchMessage = "Avvio…"
        switchTask = Task {
            let ip = fireStickIP
            let attempts = await FireStickService.smartSwitch(ip, minRSSI: minRSSI, maxAttempts: 5) { [weak self] msg in
                Task { @MainActor in self?.switchMessage = msg; self?.note(msg) }
            }
            switchAttempts = attempts
            await readFireStick()
            recompute()
            busy.remove("switch")
            switchTask = nil
        }
    }

    func cancelSwitch() { switchTask?.cancel() }

    // MARK: - Mac

    func reconnectMac() async {
        guard !isBusy("mac") else { return }
        busy.insert("mac"); defer { busy.remove("mac") }
        macMessage = "Riavvio il Wi‑Fi del Mac…"
        note(macMessage)
        let ok = await WiFiService.reconnect()
        macMessage = ok ? "Wi‑Fi tornato. Il Mac ha rifatto la scelta di nodo e banda." : "Il Wi‑Fi non è tornato entro 20 secondi."
        note(macMessage)
        wifi = await WiFiService.read()
        recompute()
    }

    /// Come per il Fire Stick: riprova fino a 4 volte finché il Mac si aggancia ai 5 GHz o a un segnale forte.
    func macSmartReconnect() async {
        guard !isBusy("mac") else { return }
        busy.insert("mac"); defer { busy.remove("mac") }
        macAttempts = []
        for n in 1...4 {
            macMessage = "Tentativo \(n) di 4: riavvio il Wi‑Fi…"
            note(macMessage)
            let ok = await WiFiService.reconnect()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            wifi = await WiFiService.read()
            guard ok, let w = wifi else { macAttempts.append("Tentativo \(n): Wi‑Fi non tornato"); continue }
            let good = (w.band != .ghz24 && w.rssi >= -75) || w.rssi >= -62
            macAttempts.append("Tentativo \(n): \(w.band.rawValue), \(w.rssi) dBm, \(w.linkMbps) Mbps\(good ? " — ok" : "")")
            if good { break }
        }
        let last = macAttempts.last ?? ""
        macMessage = last.hasSuffix("ok") ? "Connessione migliorata." : "Non ho trovato di meglio: il segnale qui è questo."
        note(macMessage)
        recompute()
    }

    func loadSavedNetworks() async { savedNetworks = await WiFiService.savedNetworks() }

    func join(_ name: String) async {
        guard !isBusy("mac") else { return }
        busy.insert("mac"); defer { busy.remove("mac") }
        let r = await WiFiService.join(name)
        macMessage = r.message
        note(r.message)
        wifi = await WiFiService.read()
        recompute()
    }

    // MARK: - Monitor in tempo reale

    func toggleMonitor() {
        if monitoring {
            monitorTask?.cancel(); monitorTask = nil; monitoring = false
            note("Monitor fermato.")
            return
        }
        monitoring = true
        note("Monitor avviato (ping leggeri ogni pochi secondi, non occupano la linea).")
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.monitorTick()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func monitorTick() async {
        let gw = await WiFiService.gateway()
        async let net = PingService.ping("1.1.1.1", count: 4)
        async let rt = pingOptional(gw, count: 4)
        var fsMs: Double?
        if fireStick != nil, !fireStickIP.isEmpty, adbInstalled {
            let p = await FireStickService.pingFromDevice(fireStickIP)
            fsMs = (p?.isUnreachable ?? true) ? nil : p?.avg
        }
        let n = await net, r = await rt
        monitor.append(MonitorPoint(date: Date(),
                                    routerMs: (r?.isUnreachable ?? true) ? nil : r?.avg,
                                    internetMs: n.isUnreachable ? nil : n.avg,
                                    internetLoss: n.loss,
                                    fireStickMs: fsMs))
        if monitor.count > 120 { monitor.removeFirst(monitor.count - 120) }
    }
}
