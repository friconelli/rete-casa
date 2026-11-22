import Foundation

/// `ReteCasa --selftest [--fs 192.168.1.x] [--speed]` stampa le misure da terminale e chiude.
/// Serve a controllare i parser sulla rete reale senza aprire la finestra.
enum SelfTest {
    static func run(args: [String]) async {
        func out(_ s: String) { print(s); fflush(stdout) }
        out("== Wi‑Fi del Mac")
        if let w = await WiFiService.read() {
            out("   \(w.band.rawValue) canale \(w.channel) (\(w.widthMHz) MHz), \(w.rssi) dBm, rumore \(w.noise), link \(w.linkMbps) Mbps, \(w.phy)")
        } else { out("   non rilevato") }
        let gw = await WiFiService.gateway()
        out("== Gateway \(gw ?? "?"), IP locale \(await WiFiService.localIP() ?? "?"), interfaccia \(await WiFiService.interface())")
        if let gw { let r = await PingService.ping(gw, count: 8); out("   router: \(r.avg) ms medi, max \(r.max), persi \(r.loss)%") }
        let n = await PingService.ping("1.1.1.1", count: 8)
        out("   internet: \(n.avg) ms medi, max \(n.max), persi \(n.loss)%")
        out("== Dispositivi")
        let devices = await LANService.scan()
        for d in devices { out("   \(d.kind.label.padding(toLength: 18, withPad: " ", startingAt: 0)) \(d.ip.padding(toLength: 15, withPad: " ", startingAt: 0)) \(d.mac)  porte \(d.openPorts)") }
        if let nas = devices.first(where: { $0.kind == .nas }) { out("   Plex su \(nas.ip): \(await LANService.plexReachable(nas.ip))") }
        if let i = args.firstIndex(of: "--fs"), i + 1 < args.count {
            let ip = args[i + 1]
            out("== Fire Stick \(ip) (adb: \(FireStickService.adbPath ?? "assente"))")
            let c = await FireStickService.connect(ip)
            out("   connessione: \(c)")
            if c == .ok, let s = await FireStickService.status(ip) {
                out("   \(s.model): \(s.rssi ?? 0) dBm, \(s.linkMbps ?? 0) Mbps, \(s.band.rawValue), app \(s.foregroundApp ?? "?")")
                if let p = s.ping { out("   ping: \(p.avg) ms, persi \(p.loss)%") }
            }
        }
        if args.contains("--speed"), let r = await SpeedService.run() {
            out("== Velocità: \(r.downMbps) Mbps giù, \(r.upMbps) su, latenza \(r.idleLatencyMs) ms")
        }
        out("== fine")
    }
}

import AppKit

extension Page {
    /// `--page diagnosis` apre direttamente quella pagina (serve per le istantanee).
    static var initial: Page {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--page"), i + 1 < a.count, let p = Page(rawValue: a[i + 1]) { return p }
        return .overview
    }
}

enum WindowSnapshot {
    /// `ReteCasa --snapshot out.png [--wait 25] [--page diagnosis]`: salva la finestra in PNG e chiude.
    static func schedule(args: [String]) {
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        var wait = 25.0
        if let w = args.firstIndex(of: "--wait"), w + 1 < args.count, let v = Double(args[w + 1]) { wait = v }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
}
