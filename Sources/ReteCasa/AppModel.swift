import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // Misure
    @Published var wifi: WiFiInfo?
    @Published var router: PingStats?
    @Published var internet: PingStats?
    @Published var speed: SpeedResult?
    @Published var devices: [LANDevice] = []
    @Published var fireStick: FireStickStatus?
    @Published var plexOK: Bool?
    @Published private(set) var findings: [Finding] = []
    @Published var lastUpdated: Date?

    // Attività in corso
    @Published var busy: Set<String> = []
    @Published var log: [String] = []

    // Fire Stick
    @Published var fireStickIP: String { didSet { defaults.set(fireStickIP, forKey: "fireStickIP") } }
    @Published var connectResult: ConnectResult?
    @Published var switchAttempts: [SwitchAttempt] = []
    @Published var switchMessage = ""
    @Published var minRSSI: Int { didSet { defaults.set(minRSSI, forKey: "minRSSI") } }

    // Mac
    @Published var savedNetworks: [String] = []
    @Published var macMessage = ""

    // Monitor
    @Published var monitor: [MonitorPoint] = []
    @Published var monitoring = false
    private var monitorTask: Task<Void, Never>?
    private var switchTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard
    private var knownNodes: Set<String> {
        get { Set(defaults.stringArray(forKey: "knownNodes") ?? []) }
        set { defaults.set(Array(newValue), forKey: "knownNodes") }
    }
    private(set) var bestDown: Double {
        get { defaults.double(forKey: "bestDown") }
        set { defaults.set(newValue, forKey: "bestDown") }
    }

    init() {
        fireStickIP = UserDefaults.standard.string(forKey: "fireStickIP") ?? ""
        let saved = UserDefaults.standard.integer(forKey: "minRSSI")
        minRSSI = saved == 0 ? -66 : saved
    }

    var verdict: Verdict { Diagnosis.verdict(findings) }
    func isBusy(_ key: String) -> Bool { busy.contains(key) }
    var adbInstalled: Bool { FireStickService.adbPath != nil }

    private func pingOptional(_ host: String?, count: Int) async -> PingStats? {
        guard let host else { return nil }
        return await PingService.ping(host, count: count)
    }

    func note(_ text: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date()))  \(text)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private func recompute() {
        findings = Diagnosis.analyze(Snapshot(
            wifi: wifi, router: router, internet: internet, speed: speed,
            bestDownMbps: bestDown > 0 ? bestDown : nil, devices: devices, knownNodeMACs: knownNodes,
            fireStick: fireStick, plexOK: plexOK))
        lastUpdated = Date()
    }

    // MARK: - Misure

    /// Wi‑Fi del Mac + ping verso router e internet. Leggero: non satura la linea.
    func measureNow() async {
        guard !isBusy("measure") else { return }
        busy.insert("measure"); defer { busy.remove("measure") }
        note("Misuro Wi‑Fi, router e internet…")
        async let w = WiFiService.read()
        async let gw = WiFiService.gateway()
        async let net = PingService.ping("1.1.1.1", count: 12)
        let gateway = await gw
        async let rt = pingOptional(gateway, count: 12)
        wifi = await w
        internet = await net
        router = await rt
        recompute()
        note("Fatto.")
    }

    /// Test di velocità: occupa tutta la banda per circa 20 secondi.
    func speedTest() async {
        guard !isBusy("speed") else { return }
        busy.insert("speed"); defer { busy.remove("speed") }
        note("Test di velocità in corso (occupa la linea ~20 s)…")
        if let r = await SpeedService.run() {
            speed = r
            if r.downMbps > bestDown { bestDown = r.downMbps }
            note(String(format: "Velocità: %.1f Mbps giù, %.1f su.", r.downMbps, r.upMbps))
        } else {
            note("Il test di velocità non è riuscito.")
        }
        recompute()
    }

    func scanDevices() async {
        guard !isBusy("scan") else { return }
        busy.insert("scan"); defer { busy.remove("scan") }
        note("Cerco i dispositivi sulla rete…")
        let found = await LANService.scan()
        devices = found
        knownNodes = knownNodes.union(found.filter(\.isStarlinkNode).map(\.mac))
        if fireStickIP.isEmpty, let ftv = found.first(where: { $0.kind == .fireTV }) { fireStickIP = ftv.ip }
        if let nas = found.first(where: { $0.kind == .nas }) { plexOK = await LANService.plexReachable(nas.ip) } else { plexOK = nil }
        recompute()
        note("Trovati \(found.count) dispositivi.")
    }

    func forgetKnownNodes() {
        knownNodes = Set(devices.filter(\.isStarlinkNode).map(\.mac))
        recompute()
        note("Nodi Starlink noti azzerati: da ora conto solo quelli visibili.")
    }

    /// Misura tutto quello che è sicuro fare senza saturare la rete.
    func measureAll() async {
        await measureNow()
        await scanDevices()
        if !fireStickIP.isEmpty && adbInstalled { await refreshFireStick() }
    }

    // MARK: - Fire Stick

    func refreshFireStick() async {
        guard !fireStickIP.isEmpty, !isBusy("firestick") else { return }
        busy.insert("firestick"); defer { busy.remove("firestick") }
        note("Mi collego al Fire Stick (\(fireStickIP))…")
        let result = await FireStickService.connect(fireStickIP)
        connectResult = result
        guard result == .ok else { note("Fire Stick non raggiungibile via ADB."); return }
        fireStick = await FireStickService.status(fireStickIP)
        recompute()
        note("Fire Stick letto.")
    }

    func fireStickSpeedTest() async {
        guard !fireStickIP.isEmpty, !isBusy("fsspeed") else { return }
        busy.insert("fsspeed"); defer { busy.remove("fsspeed") }
        note("Misuro la velocità reale del Fire Stick (occupa la linea ~15 s)…")
        if await FireStickService.connect(fireStickIP) != .ok { note("Fire Stick non raggiungibile."); return }
        let d = await FireStickService.speedTest(fireStickIP)
        var current = fireStick
        if current == nil { current = await FireStickService.status(fireStickIP, withPing: false) }
        if var s = current {
            s.downMbps = d
            fireStick = s
        }
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
            if await FireStickService.connect(ip) == .ok { fireStick = await FireStickService.status(ip) }
            recompute()
            busy.remove("switch")
            switchTask = nil
        }
    }

    func cancelSwitch() { switchTask?.cancel() }

    // MARK: - Mac

    func reconnectMac() async {
        guard !isBusy("mac") else { return }
        busy.insert("mac")
        macMessage = "Riavvio il Wi‑Fi del Mac…"
        note(macMessage)
        let ok = await WiFiService.reconnect()
        macMessage = ok ? "Wi‑Fi tornato. Il Mac ha rifatto la scelta di nodo e banda." : "Il Wi‑Fi non è tornato entro 20 secondi."
        note(macMessage)
        busy.remove("mac")
        await measureNow()
    }

    func loadSavedNetworks() async { savedNetworks = await WiFiService.savedNetworks() }

    func join(_ name: String) async {
        busy.insert("mac")
        let r = await WiFiService.join(name)
        macMessage = r.message
        note(r.message)
        busy.remove("mac")
        await measureNow()
    }

    // MARK: - Monitor in tempo reale

    func toggleMonitor() {
        if monitoring {
            monitorTask?.cancel(); monitorTask = nil; monitoring = false
            note("Monitor fermato.")
            return
        }
        monitoring = true
        note("Monitor avviato (ping leggeri ogni 5 s, non occupano la linea).")
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
