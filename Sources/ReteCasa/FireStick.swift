import Foundation

enum ConnectResult: Equatable {
    case ok
    case adbMissing
    case refused        // Debug ADB spento sul Fire Stick
    case unauthorized   // manca il "Consenti sempre" sulla TV
    case failed(String)
}

struct SwitchAttempt: Identifiable, Equatable {
    let id = UUID()
    var number: Int
    var rssi: Int?
    var linkMbps: Int?
    var frequencyMHz: Int?
    var accepted: Bool
}

/// Controllo del Fire Stick via ADB (debug di rete). Sola lettura, tranne il riavvio del Wi‑Fi.
enum FireStickService {
    static var adbPath: String? {
        ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func adb(_ ip: String, _ args: [String], timeout: TimeInterval = 20) async -> ShellResult {
        guard let path = adbPath else { return ShellResult(out: "", err: "adb non installato", code: -1) }
        return await Shell.run(path, ["-s", "\(ip):5555"] + args, timeout: timeout)
    }

    static func connect(_ ip: String) async -> ConnectResult {
        guard let path = adbPath else { return .adbMissing }
        let c = await Shell.run(path, ["connect", "\(ip):5555"], timeout: 15)
        let text = (c.out + c.err).lowercased()
        if text.contains("refused") || text.contains("failed to connect") || text.contains("timed out") { return .refused }
        let t = await adb(ip, ["shell", "echo ok"], timeout: 15)
        if t.out.contains("ok") { return .ok }
        let all = (t.out + t.err).lowercased()
        if all.contains("unauthorized") { return .unauthorized }
        if all.contains("offline") {
            // Succede subito dopo la richiesta di autorizzazione: ritenta una volta.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let again = await adb(ip, ["shell", "echo ok"], timeout: 15)
            return again.out.contains("ok") ? .ok : .failed("Il Fire Stick risulta offline.")
        }
        return .failed((t.out + t.err).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func status(_ ip: String, withPing: Bool = true) async -> FireStickStatus? {
        let wifi = await adb(ip, ["shell", "cmd wifi status"])
        guard wifi.ok, let info = wifi.out.components(separatedBy: "\n").first(where: { $0.contains("WifiInfo:") }) else { return nil }
        let model = await adb(ip, ["shell", "getprop ro.product.model"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        let front = await adb(ip, ["shell", "dumpsys activity activities | grep -m1 ResumedActivity"]).out
        var ping: PingStats?
        if withPing {
            let p = await adb(ip, ["shell", "ping -c 10 -i 0.3 -W 2 1.1.1.1"], timeout: 30)
            ping = PingService.parse(p.out + p.err, sent: 10)
        }
        return FireStickStatus(
            ip: ip,
            model: model,
            rssi: Int(info.firstMatch(#"RSSI:\s*(-?\d+)"#) ?? ""),
            linkMbps: Int(info.firstMatch(#"Link speed:\s*(\d+)Mbps"#) ?? ""),
            frequencyMHz: Int(info.firstMatch(#"Frequency:\s*(\d+)"#) ?? ""),
            ping: ping,
            foregroundApp: front.firstMatch(#"u0\s+([\w.]+)/"#),
            downMbps: nil
        )
    }

    /// Ping leggero verso internet fatto dalla chiavetta (per il monitor).
    static func pingFromDevice(_ ip: String, count: Int = 3) async -> PingStats? {
        let p = await adb(ip, ["shell", "ping -c \(count) -i 0.3 -W 2 1.1.1.1"], timeout: 15)
        guard p.out.contains("packet loss") else { return nil }
        return PingService.parse(p.out + p.err, sent: count)
    }

    /// Scarica 25 MB da Cloudflare direttamente dal Fire Stick e misura i Mbps reali.
    static func speedTest(_ ip: String) async -> Double? {
        let script = """
        F=/data/local/tmp/dl.bin; rm -f $F; ( (printf "GET /__down?bytes=25000000 HTTP/1.0\\r\\nHost: speed.cloudflare.com\\r\\n\\r\\n"; sleep 60) | toybox nc -w 10 speed.cloudflare.com 80 > $F & ); S=$(cut -d" " -f1 /proc/uptime); i=0; while [ $i -lt 250 ]; do sz=$(toybox stat -c %s $F 2>/dev/null); [ "${sz:-0}" -ge 25000000 ] && break; sleep 0.2; i=$((i+1)); done; E=$(cut -d" " -f1 /proc/uptime); echo "RES ${sz:-0} $S $E"; rm -f $F; pkill -f "toybox nc" 2>/dev/null
        """
        let r = await adb(ip, ["shell", script], timeout: 90)
        guard let line = r.out.components(separatedBy: "\n").first(where: { $0.hasPrefix("RES ") }) else { return nil }
        let p = line.split(separator: " ").dropFirst().compactMap { Double($0) }
        guard p.count == 3, p[2] > p[1], p[0] > 100_000 else { return nil }
        return p[0] * 8 / (p[2] - p[1]) / 1_000_000
    }

    /// Spegne e riaccende il Wi‑Fi del Fire Stick finché si aggancia a un segnale abbastanza forte.
    /// Non si può scegliere il nodo mesh: è la TV a decidere, quindi si riprova.
    static func smartSwitch(
        _ ip: String,
        minRSSI: Int,
        maxAttempts: Int,
        progress: @escaping @Sendable (String) -> Void
    ) async -> [SwitchAttempt] {
        var attempts: [SwitchAttempt] = []
        let toggle = "nohup sh -c \"cmd wifi set-wifi-enabled disabled; sleep 4; cmd wifi set-wifi-enabled enabled\" >/dev/null 2>&1 &"
        for n in 1...maxAttempts {
            if Task.isCancelled { break }
            progress("Tentativo \(n) di \(maxAttempts): riavvio il Wi‑Fi del Fire Stick…")
            _ = await adb(ip, ["shell", toggle], timeout: 15)
            try? await Task.sleep(nanoseconds: 25_000_000_000)

            var back = false
            for _ in 0..<12 {
                if await connect(ip) == .ok { back = true; break }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            guard back else {
                progress("Il Fire Stick non è tornato raggiungibile.")
                break
            }
            let st = await status(ip, withPing: false)
            let good = (st?.rssi ?? -127) >= minRSSI
            attempts.append(SwitchAttempt(number: n, rssi: st?.rssi, linkMbps: st?.linkMbps,
                                          frequencyMHz: st?.frequencyMHz, accepted: good))
            if good {
                progress("Agganciato con segnale \(st?.rssi ?? 0) dBm.")
                break
            }
            progress("Segnale \(st?.rssi ?? 0) dBm: troppo debole, riprovo.")
        }
        return attempts
    }
}
