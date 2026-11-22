import Foundation

// MARK: - Ping

enum PingService {
    /// Ping dal Mac. Intervallo minimo 0,2 s senza privilegi di root.
    static func ping(_ host: String, count: Int = 10, interval: Double = 0.25) async -> PingStats {
        let timeout = Double(count) * (interval + 1.5) + 5
        let r = await Shell.run("/sbin/ping", ["-c", "\(count)", "-i", "\(interval)", "-q", host], timeout: timeout)
        return parse(r.out + "\n" + r.err, sent: count)
    }

    /// Legge sia l'output BSD (macOS) sia quello Linux (Android): "x% packet loss" e "= min/avg/max/".
    static func parse(_ text: String, sent: Int) -> PingStats {
        let loss = Double(text.firstMatch(#"([\d.]+)% packet loss"#) ?? "") ?? 100
        guard let regex = try? NSRegularExpression(pattern: #"=\s*([\d.]+)/([\d.]+)/([\d.]+)/"#),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges == 4
        else { return PingStats(min: 0, avg: 0, max: 0, loss: loss, sent: sent) }
        func g(_ i: Int) -> Double {
            Range(m.range(at: i), in: text).flatMap { Double(text[$0]) } ?? 0
        }
        return PingStats(min: g(1), avg: g(2), max: g(3), loss: loss, sent: sent)
    }
}

// MARK: - Wi‑Fi del Mac

enum WiFiService {
    /// Nome dell'interfaccia Wi‑Fi (di solito en0).
    static func interface() async -> String {
        let r = await Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 10)
        let lines = r.out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Hardware Port: Wi-Fi") {
            if i + 1 < lines.count, let dev = lines[i + 1].firstMatch(#"Device:\s*(\S+)"#) { return dev }
        }
        return "en0"
    }

    static func read() async -> WiFiInfo? {
        let r = await Shell.run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-json"], timeout: 25)
        guard let data = r.out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let top = (root["SPAirPortDataType"] as? [[String: Any]])?.first,
              let ifaces = top["spairport_airport_interfaces"] as? [[String: Any]] else { return nil }
        for iface in ifaces {
            guard let cur = iface["spairport_current_network_information"] as? [String: Any],
                  let channelText = cur["spairport_network_channel"] as? String else { continue }
            let channel = Int(channelText.firstMatch(#"^(\d+)"#) ?? "") ?? 0
            let band: Band = channelText.contains("2GHz") ? .ghz24 : channelText.contains("5GHz") ? .ghz5
                : channelText.contains("6GHz") ? .ghz6 : .unknown
            let width = Int(channelText.firstMatch(#",\s*(\d+)MHz"#) ?? "") ?? 20
            let sn = cur["spairport_signal_noise"] as? String ?? ""
            let rssi = Int(sn.firstMatch(#"(-?\d+)\s*dBm\s*/"#) ?? "") ?? 0
            let noise = Int(sn.firstMatch(#"/\s*(-?\d+)\s*dBm"#) ?? "") ?? 0
            let rate = (cur["spairport_network_rate"] as? Int) ?? Int(cur["spairport_network_rate"] as? Double ?? 0)
            let phy = (cur["spairport_network_phymode"] as? String) ?? ""
            return WiFiInfo(band: band, channel: channel, widthMHz: width, rssi: rssi, noise: noise, linkMbps: rate, phy: phy)
        }
        return nil
    }

    /// Spegne e riaccende il Wi‑Fi: il Mac rifà la scelta del nodo e della banda.
    static func reconnect() async -> Bool {
        let dev = await interface()
        _ = await Shell.run("/usr/sbin/networksetup", ["-setairportpower", dev, "off"], timeout: 15)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let on = await Shell.run("/usr/sbin/networksetup", ["-setairportpower", dev, "on"], timeout: 15)
        guard on.ok else { return false }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let g = await gateway(), !(await PingService.ping(g, count: 1, interval: 1)).isUnreachable {
                return true
            }
        }
        return false
    }

    static func savedNetworks() async -> [String] {
        let dev = await interface()
        let r = await Shell.run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", dev], timeout: 10)
        return r.out.components(separatedBy: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Prova a collegarsi a una rete salvata. macOS può rifiutare (errore -3900) se non ha il permesso.
    static func join(_ name: String) async -> (ok: Bool, message: String) {
        let dev = await interface()
        let r = await Shell.run("/usr/sbin/networksetup", ["-setairportnetwork", dev, name], timeout: 30)
        let text = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("Failed") || text.contains("Error") {
            return (false, "macOS non ha permesso il cambio dal programma. Scegli la rete dal menu Wi‑Fi in alto.")
        }
        return (true, "Collegato a \(name).")
    }

    static func gateway() async -> String? {
        let r = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 10)
        return r.out.firstMatch(#"gateway:\s*(\S+)"#)
    }

    static func localIP() async -> String? {
        let r = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 10)
        guard let iface = r.out.firstMatch(#"interface:\s*(\S+)"#) else { return nil }
        let ip = await Shell.run("/usr/sbin/ipconfig", ["getifaddr", iface], timeout: 10)
        let s = ip.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

// MARK: - Velocità internet

enum SpeedService {
    /// Test di Apple (`networkQuality`). Satura la linea per ~20 s: non va usato durante uno streaming.
    static func run() async -> SpeedResult? {
        let r = await Shell.run("/usr/bin/networkQuality", ["-c", "-s"], timeout: 90)
        guard let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dl = json["dl_throughput"] as? Double else { return nil }
        let ul = json["ul_throughput"] as? Double ?? 0
        let rtt = json["base_rtt"] as? Double ?? 0
        return SpeedResult(downMbps: dl / 1_000_000, upMbps: ul / 1_000_000, idleLatencyMs: rtt, date: Date())
    }
}

// MARK: - Dispositivi sulla rete locale

enum LANService {
    static let probePorts = [32400, 5000, 5555, 60000, 55443]

    static func normalizeMAC(_ mac: String) -> String {
        mac.split(separator: ":").map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":").lowercased()
    }

    static func scan() async -> [LANDevice] {
        guard let selfIP = await WiFiService.localIP() else { return [] }
        let gw = await WiFiService.gateway()
        let prefix = selfIP.split(separator: ".").dropLast().joined(separator: ".")

        // 1) ping a tappeto per popolare la tabella ARP, 2) lettura ARP.
        let sweep = "for i in $(seq 1 254); do ping -c1 -W 400 -t1 \(prefix).$i >/dev/null 2>&1 & done; wait; arp -an"
        let arp = await Shell.sh(sweep, timeout: 40)

        var found: [(ip: String, mac: String)] = []
        for line in arp.out.components(separatedBy: "\n") {
            guard let ip = line.firstMatch(#"\((\d+\.\d+\.\d+\.\d+)\)"#),
                  let mac = line.firstMatch(#" at ([0-9a-fA-F:]+) on"#),
                  ip.hasPrefix(prefix + "."), !ip.hasSuffix(".255"), !mac.lowercased().hasPrefix("ff:ff") else { continue }
            if found.contains(where: { $0.ip == ip }) { continue }
            found.append((ip, normalizeMAC(mac)))
        }
        if !found.contains(where: { $0.ip == selfIP }) { found.append((selfIP, "")) }

        // 3) porte caratteristiche (Plex, DSM, Fire TV), in parallelo.
        let ips = found.map(\.ip).joined(separator: " ")
        let ports = probePorts.map(String.init).joined(separator: " ")
        let probe = "for ip in \(ips); do (for p in \(ports); do nc -z -G1 $ip $p 2>/dev/null && echo \"$ip $p\"; done) & done; wait"
        let pr = await Shell.sh(probe, timeout: 40)
        var open: [String: [Int]] = [:]
        for line in pr.out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 2, let p = Int(parts[1]) { open[String(parts[0]), default: []].append(p) }
        }

        return found.map { item in
            let p = (open[item.ip] ?? []).sorted()
            let kind: DeviceKind
            if item.ip == selfIP { kind = .thisMac }
            else if item.mac.hasPrefix("74:24:9f") { kind = item.ip == gw ? .router : .mesh }
            else if p.contains(32400) { kind = .nas }
            else if p.contains(5555) || p.contains(60000) || p.contains(55443) { kind = .fireTV }
            else { kind = .other }
            return LANDevice(ip: item.ip, mac: item.mac, kind: kind, openPorts: p, latencyMs: nil)
        }
        .sorted { a, b in
            let order: [DeviceKind] = [.router, .mesh, .nas, .fireTV, .thisMac, .other]
            let ia = order.firstIndex(of: a.kind) ?? 9, ib = order.firstIndex(of: b.kind) ?? 9
            return ia != ib ? ia < ib : a.ip.localizedStandardCompare(b.ip) == .orderedAscending
        }
    }

    /// Controlla che Plex risponda sul NAS.
    static func plexReachable(_ ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip):32400/identity") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
