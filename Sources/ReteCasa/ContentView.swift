import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, diagnosis, devices, fireStick, mac, monitor, activity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Panoramica"
        case .diagnosis: return "Diagnosi"
        case .devices: return "Dispositivi"
        case .fireStick: return "Fire Stick"
        case .mac: return "Wi‑Fi del Mac"
        case .monitor: return "Monitor"
        case .activity: return "Attività"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .diagnosis: return "stethoscope"
        case .devices: return "network"
        case .fireStick: return "tv.fill"
        case .mac: return "wifi"
        case .monitor: return "waveform.path.ecg"
        case .activity: return "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: Updater
    @Binding var showUpdateSheet: Bool
    @State private var selection: Page? = Page.initial

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                Text("v\(updater.currentVersion)").font(.caption2).foregroundStyle(.tertiary).padding(8)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selection ?? .overview {
                    case .overview: OverviewView(goTo: { selection = $0 })
                    case .diagnosis: DiagnosisView()
                    case .devices: DevicesView()
                    case .fireStick: FireStickView()
                    case .mac: MacWiFiView()
                    case .monitor: MonitorView()
                    case .activity: ActivityView()
                    }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem {
                if updater.isUpdateAvailable {
                    Button { showUpdateSheet = true } label: { Label("Aggiornamento disponibile", systemImage: "arrow.down.circle.fill") }
                        .help("Nuova versione disponibile")
                }
            }
            ToolbarItem {
                Button { Task { await model.measureAll() } } label: {
                    Label("Misura ora", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy("measure") || model.isBusy("scan"))
                .help("Misura Wi‑Fi, router, internet e dispositivi")
            }
        }
        .task { await model.measureAll() }
    }
}

// MARK: - Panoramica

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var goTo: (Page) -> Void

    var body: some View {
        hero
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            wifiTile
            routerTile
            internetTile
            speedTile
            fireStickTile
            nodesTile
        }
        let top = Array(model.findings.filter { $0.severity >= .warn }.prefix(3))
        if !top.isEmpty {
            HStack { SectionTitle(text: "Da guardare", symbol: "exclamationmark.bubble"); Spacer()
                Button("Tutta la diagnosi") { goTo(.diagnosis) }.glassButton() }
            ForEach(top) { FindingRow(finding: $0) }
        }
    }

    private var hero: some View {
        let v = model.verdict
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: Theme.symbol(v.severity))
                .font(.system(size: 40)).foregroundStyle(v.severity == .ok ? Theme.accent : Theme.color(v.severity))
            VStack(alignment: .leading, spacing: 4) {
                Text(v.headline).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.warm)
                Text(v.detail).font(.callout).foregroundStyle(Theme.warm.opacity(0.75))
                if let t = model.lastUpdated {
                    Text("Aggiornato alle \(t.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Theme.warm.opacity(0.5))
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Button { Task { await model.measureAll() } } label: {
                    if model.isBusy("measure") || model.isBusy("scan") { ProgressView().controlSize(.small) } else { Text("Misura ora") }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { Task { await model.speedTest() } } label: {
                    if model.isBusy("speed") { ProgressView().controlSize(.small) } else { Text("Test velocità") }
                }
                .buttonStyle(HeroButtonStyle()).disabled(model.isBusy("speed"))
                .help("Occupa tutta la linea per circa 20 secondi: non usarlo durante uno streaming.")
            }
        }
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var wifiTile: some View {
        let w = model.wifi
        let sev: Severity = w == nil ? .info : (w!.rssi >= -67 ? .ok : w!.rssi >= -75 ? .warn : .bad)
        return MetricTile(title: "Wi‑Fi del Mac", value: w.map { "\($0.rssi)" } ?? "—", unit: "dBm",
                          caption: w.map { "\($0.band.rawValue) · canale \($0.channel) · \($0.linkMbps) Mbps" } ?? "Non collegato",
                          severity: sev, symbol: "wifi")
    }

    private var routerTile: some View {
        let r = model.router
        let sev: Severity = r == nil ? .info : (r!.isUnreachable ? .bad : (r!.loss > 2 || r!.avg > 80) ? .warn : .ok)
        return MetricTile(title: "Router di casa", value: r.map { $0.isUnreachable ? "—" : Diagnosis.fmt($0.avg) } ?? "—", unit: "ms",
                          caption: r.map { "\(Diagnosis.fmt($0.loss))% pacchetti persi" } ?? "Non misurato",
                          severity: sev, symbol: "wifi.router")
    }

    private var internetTile: some View {
        let n = model.internet
        let sev: Severity = n == nil ? .info : (n!.isUnreachable ? .bad : n!.loss >= 3 ? .bad : n!.avg > 120 ? .warn : .ok)
        return MetricTile(title: "Internet", value: n.map { $0.isUnreachable ? "—" : Diagnosis.fmt($0.avg) } ?? "—", unit: "ms",
                          caption: n.map { "\(Diagnosis.fmt($0.loss))% persi · picco \(Diagnosis.fmt($0.max)) ms" } ?? "Non misurato",
                          severity: sev, symbol: "globe")
    }

    private var speedTile: some View {
        let s = model.speed
        let sev: Severity = s == nil ? .info : (s!.downMbps < 8 ? .bad : s!.downMbps < 25 ? .warn : .ok)
        return MetricTile(title: "Velocità", value: s.map { Diagnosis.fmt($0.downMbps) } ?? "—", unit: "Mbps",
                          caption: s.map { "su \(Diagnosis.fmt($0.upMbps)) Mbps · \($0.date.formatted(date: .omitted, time: .shortened))" } ?? "Premi «Test velocità»",
                          severity: sev, symbol: "speedometer")
    }

    private var fireStickTile: some View {
        let f = model.fireStick
        let r = f?.rssi
        let sev: Severity = r == nil ? .info : (r! >= -67 ? .ok : r! >= -72 ? .warn : .bad)
        return MetricTile(title: "Fire Stick", value: r.map { "\($0)" } ?? "—", unit: "dBm",
                          caption: f.map { "\($0.band.rawValue) · \($0.linkMbps ?? 0) Mbps" } ?? "Non collegato (vedi Fire Stick)",
                          severity: sev, symbol: "tv")
    }

    private var nodesTile: some View {
        let nodes = model.devices.filter(\.isStarlinkNode)
        return MetricTile(title: "Starlink in casa", value: model.devices.isEmpty ? "—" : "\(nodes.count)", unit: nodes.count == 1 ? "dispositivo" : "dispositivi",
                          caption: model.devices.isEmpty ? "Non ancora cercati" : "\(model.devices.count) dispositivi in rete",
                          severity: .info, symbol: "dot.radiowaves.left.and.right")
    }
}

// MARK: - Diagnosi

struct FindingRow: View {
    let finding: Finding
    var body: some View {
        Card(tint: finding.severity >= .warn ? Theme.color(finding.severity) : nil) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Theme.symbol(finding.severity)).font(.title3).foregroundStyle(Theme.color(finding.severity))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(finding.title).font(.headline)
                        Pill(text: finding.area.rawValue, color: .secondary)
                    }
                    Text(finding.detail).font(.callout).foregroundStyle(.secondary)
                    if let s = finding.suggestion {
                        Label(s, systemImage: "lightbulb").font(.callout).foregroundStyle(Theme.accentDeep).padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct DiagnosisView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            SectionTitle(text: "Diagnosi", symbol: "stethoscope")
            Spacer()
            Button { copyReport() } label: { Label("Copia report", systemImage: "doc.on.doc") }.glassButton()
        }
        Text("Le regole confrontano i ping verso il router e verso internet per capire se il problema è dentro casa o è Starlink.")
            .font(.callout).foregroundStyle(.secondary)
        if model.findings.isEmpty {
            EmptyHint(symbol: "stethoscope", title: "Nessuna misura", message: "Premi «Misura ora» in alto per avviare i controlli.")
        } else {
            ForEach(model.findings) { FindingRow(finding: $0) }
        }
    }

    private func copyReport() {
        let v = model.verdict
        var text = "Rete Casa — \(Date().formatted(date: .abbreviated, time: .shortened))\n\(v.headline)\n\(v.detail)\n\n"
        for f in model.findings {
            text += "[\(f.area.rawValue)] \(f.title)\n  \(f.detail)\n"
            if let s = f.suggestion { text += "  → \(s)\n" }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.note("Report copiato negli appunti.")
    }
}
