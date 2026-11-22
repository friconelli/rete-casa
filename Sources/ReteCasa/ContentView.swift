import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case status, devices, fireStick, mac, monitor, activity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Stato"
        case .devices: return "Dispositivi"
        case .fireStick: return "Fire Stick"
        case .mac: return "Wi‑Fi del Mac"
        case .monitor: return "Monitor"
        case .activity: return "Registro"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "heart.text.square"
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
                    switch selection ?? .status {
                    case .status: StatusView()
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
                Button { selection = .status; Task { await model.runFullCheck() } } label: {
                    Label("Analisi completa", systemImage: "stethoscope")
                }
                .disabled(model.isBusy("check"))
                .help("Controlla Wi‑Fi, router, internet, mesh, Fire Stick e Plex")
            }
        }
        .task { await model.runFullCheck() }
    }
}

// MARK: - Stato

struct StatusView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        hero

        if !model.steps.isEmpty { StepsCard() }

        let problems = model.findings.filter { $0.severity >= .warn }
        if !problems.isEmpty {
            SectionTitle(text: "Cosa non va", symbol: "exclamationmark.bubble")
            ForEach(problems) { FindingRow(finding: $0) }
        }

        SectionTitle(text: "La tua rete", symbol: "house")
        NetworkMapView()

        SectionTitle(text: "Misure", symbol: "gauge.with.dots.needle.67percent")
        MeasuresGrid()

        let fine = model.findings.filter { $0.severity < .warn }
        if !fine.isEmpty {
            DisclosureGroup {
                VStack(spacing: 10) { ForEach(fine) { FindingRow(finding: $0) } }.padding(.top, 8)
            } label: {
                Label("Va tutto bene qui (\(fine.count))", systemImage: "checkmark.circle").font(.headline)
            }
        }
    }

    private var hero: some View {
        let v = model.verdict
        let running = model.isBusy("check")
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: Theme.symbol(v.severity))
                .font(.system(size: 42)).foregroundStyle(v.severity == .ok ? Theme.accent : Theme.color(v.severity))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.findings.isEmpty ? "Controlliamo la rete" : v.headline)
                    .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.warm)
                Text(model.findings.isEmpty ? "Premi «Analisi completa»: controlla Wi‑Fi, router, internet, mesh, Fire Stick e Plex." : v.detail)
                    .font(.callout).foregroundStyle(Theme.warm.opacity(0.75))
                if let t = model.lastUpdated {
                    Text("Ultima analisi alle \(t.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Theme.warm.opacity(0.5))
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Button { Task { await model.runFullCheck() } } label: {
                    HStack(spacing: 6) {
                        if running { ProgressView().controlSize(.small) } else { Image(systemName: "stethoscope") }
                        Text(running ? "Analisi in corso…" : "Analisi completa")
                    }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(running)
                Toggle("Includi test di velocità", isOn: $model.includeSpeed)
                    .toggleStyle(.checkbox).font(.caption).foregroundStyle(Theme.warm.opacity(0.8))
                    .help("Aggiunge circa 20 secondi e occupa tutta la linea: non usarlo durante uno streaming.")
            }
        }
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Elenco dei passaggi dell'analisi, con lo stato di ognuno.
struct StepsCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.steps) { step in
                    HStack(spacing: 10) {
                        icon(step.state).frame(width: 22)
                        Text(step.title).font(.callout.weight(.semibold))
                        Spacer()
                        Text(step.detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder private func icon(_ s: CheckStep.State) -> some View {
        switch s {
        case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .done(let sev): Image(systemName: Theme.symbol(sev)).foregroundStyle(Theme.color(sev))
        }
    }
}

// MARK: - Problema con azione

struct FindingRow: View {
    @EnvironmentObject var model: AppModel
    let finding: Finding
    @State private var confirm = false

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
                    if let a = finding.action {
                        HStack(spacing: 10) {
                            Button {
                                if a.needsConfirm { confirm = true } else { model.perform(a) }
                            } label: { Label(a.label, systemImage: a.symbol) }
                            .buttonStyle(PrimaryButtonStyle()).disabled(model.anyBusy)
                            if let p = progress(a) { ProgressView().controlSize(.small); Text(p).font(.callout).foregroundStyle(.secondary) }
                        }
                        .padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .confirmationDialog("Riavviare il Wi‑Fi del Fire Stick?", isPresented: $confirm) {
            Button("Riavvia e cerca", role: .destructive) { if let a = finding.action { model.perform(a) } }
        } message: { Text("Se stai guardando qualcosa, l'immagine si ferma per circa un minuto a tentativo.") }
    }

    private func progress(_ a: FindingAction) -> String? {
        switch a {
        case .fireStickSwitch: return model.isBusy("switch") ? model.switchMessage : nil
        case .recoverFireStick: return model.isBusy("recover") ? model.recoveryMessage : nil
        case .reconnectMac: return model.isBusy("mac") ? model.macMessage : nil
        case .rescan: return model.isBusy("check") ? "Analisi in corso…" : nil
        }
    }
}

// MARK: - Mappa di casa

struct MapChip: View {
    let symbol: String
    let title: String
    let caption: String
    var severity: Severity = .info

    var body: some View {
        Card(padding: 12, tint: severity >= .warn ? Theme.color(severity) : nil) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title3).frame(width: 34, height: 34)
                    .background((severity == .info ? Color.secondary : Theme.color(severity)).opacity(0.15), in: Circle())
                    .foregroundStyle(severity == .info ? Color.secondary : Theme.color(severity))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct NetworkMapView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Da Internet ai mesh").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                internetChip
                ForEach(model.nodes) { n in
                    MapChip(symbol: n.isRouter ? "wifi.router.fill" : "dot.radiowaves.left.and.right",
                            title: n.name,
                            caption: n.online ? "\(n.ip)\(n.latencyMs.map { " · \(Diagnosis.fmt($0)) ms" } ?? "")" : "Non risponde (ultimo: \(n.ip))",
                            severity: n.online ? ((n.latencyMs ?? 0) > 100 ? .warn : .ok) : .bad)
                }
            }
            if model.nodes.isEmpty {
                Text("I mesh compaiono dopo la prima analisi e restano in elenco anche se si spengono.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Dispositivi").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                fireStickChip
                nasChip
                macChip
            }
        }
    }

    private var internetChip: some View {
        let n = model.internet
        let sev: Severity = n == nil ? .info : (n!.isUnreachable || n!.loss >= 3) ? .bad : n!.avg > 120 ? .warn : .ok
        return MapChip(symbol: "globe", title: "Internet (Starlink)",
                       caption: n.map { $0.isUnreachable ? "Non raggiungibile" : "\(Diagnosis.fmt($0.avg)) ms · \(Diagnosis.fmt($0.loss))% persi" } ?? "Non misurato",
                       severity: sev)
    }

    private var fireStickChip: MapChip {
        if model.fireStickProblem != nil {
            return MapChip(symbol: "tv.fill", title: "Fire Stick", caption: "Non raggiungibile", severity: .bad)
        }
        if let f = model.fireStick, let r = f.rssi {
            return MapChip(symbol: "tv.fill", title: "Fire Stick", caption: "\(r) dBm · \(f.band.rawValue)",
                           severity: r >= -67 ? .ok : r >= -72 ? .warn : .bad)
        }
        return MapChip(symbol: "tv.fill", title: "Fire Stick", caption: model.fireStickIP.isEmpty ? "Non configurato" : "Non letto")
    }

    private var nasChip: some View {
        let nas = model.devices.first { $0.kind == .nas }
        return MapChip(symbol: "externaldrive.connected.to.line.below.fill", title: "Synology / Plex",
                       caption: nas == nil ? "Non trovato" : (model.plexOK == true ? "\(nas!.ip) · Plex risponde" : "\(nas!.ip) · Plex non risponde"),
                       severity: nas == nil ? .info : (model.plexOK == true ? .ok : .bad))
    }

    private var macChip: some View {
        let w = model.wifi
        return MapChip(symbol: "laptopcomputer", title: "Questo Mac",
                       caption: w.map { "\($0.rssi) dBm · \($0.band.rawValue)" } ?? "Non collegato",
                       severity: w == nil ? .bad : (w!.rssi >= -67 ? .ok : w!.rssi >= -75 ? .warn : .bad))
    }
}

// MARK: - Misure

struct MeasuresGrid: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            let w = model.wifi
            MetricTile(title: "Segnale Wi‑Fi del Mac", value: w.map { "\($0.rssi)" } ?? "—", unit: "dBm",
                       caption: w.map { "\($0.band.rawValue) · canale \($0.channel) · \($0.linkMbps) Mbps" } ?? "Non collegato",
                       severity: w == nil ? .info : (w!.rssi >= -67 ? .ok : w!.rssi >= -75 ? .warn : .bad), symbol: "wifi")

            let r = model.router
            MetricTile(title: "Risposta del router", value: r.map { $0.isUnreachable ? "—" : Diagnosis.fmt($0.avg) } ?? "—", unit: "ms",
                       caption: r.map { "\(Diagnosis.fmt($0.loss))% persi · misura il Wi‑Fi di casa" } ?? "Non misurato",
                       severity: r == nil ? .info : (r!.isUnreachable ? .bad : (r!.loss > 2 || r!.avg > 80) ? .warn : .ok), symbol: "wifi.router")

            let n = model.internet
            MetricTile(title: "Risposta di internet", value: n.map { $0.isUnreachable ? "—" : Diagnosis.fmt($0.avg) } ?? "—", unit: "ms",
                       caption: n.map { "\(Diagnosis.fmt($0.loss))% persi · misura Starlink" } ?? "Non misurato",
                       severity: n == nil ? .info : (n!.isUnreachable ? .bad : n!.loss >= 3 ? .bad : n!.avg > 120 ? .warn : .ok), symbol: "globe")

            let s = model.speed
            MetricTile(title: "Velocità", value: s.map { Diagnosis.fmt($0.downMbps) } ?? "—", unit: "Mbps",
                       caption: s.map { "in upload \(Diagnosis.fmt($0.upMbps)) Mbps" } ?? "Spunta «Includi test di velocità»",
                       severity: s == nil ? .info : (s!.downMbps < 8 ? .bad : s!.downMbps < 25 ? .warn : .ok), symbol: "speedometer")

            let f = model.fireStick
            MetricTile(title: "Segnale Fire Stick", value: f?.rssi.map(String.init) ?? "—", unit: "dBm",
                       caption: f.map { "\($0.band.rawValue) · \($0.linkMbps ?? 0) Mbps" } ?? "Non collegato",
                       severity: f?.rssi == nil ? .info : (f!.rssi! >= -67 ? .ok : f!.rssi! >= -72 ? .warn : .bad), symbol: "tv")
        }
    }
}
