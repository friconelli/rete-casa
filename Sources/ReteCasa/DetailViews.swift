import SwiftUI
import Charts

// MARK: - Dispositivi

struct DevicesView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmForget = false

    var body: some View {
        HStack {
            SectionTitle(text: "Router e mesh Starlink", symbol: "dot.radiowaves.left.and.right")
            Spacer()
            Button { Task { await model.scanDevices() } } label: {
                if model.isBusy("scan") { ProgressView().controlSize(.small) } else { Label("Cerca", systemImage: "magnifyingglass") }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(model.anyBusy)
        }
        Text("Dai un nome a ogni nodo (per esempio «Mesh salone») guardando nell'app Starlink quale indirizzo ha. Un nodo spento resta in elenco come «non risponde».")
            .font(.callout).foregroundStyle(.secondary)

        if model.nodes.isEmpty {
            EmptyHint(symbol: "network", title: "Nessun nodo ancora", message: "Premi «Cerca»: ci vogliono circa dieci secondi. macOS può chiedere il permesso per la rete locale.")
        } else {
            ForEach(model.nodes) { n in
                Card(tint: n.online ? nil : .red) {
                    HStack(spacing: 14) {
                        Image(systemName: n.isRouter ? "wifi.router.fill" : "dot.radiowaves.left.and.right").font(.title2).frame(width: 36)
                            .foregroundStyle(n.online ? Theme.accentDeep : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Nome", text: Binding(get: { model.nodeNames[n.mac] ?? n.name },
                                                            set: { model.nodeNames[n.mac] = $0 }))
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                            Text("\(n.ip)  ·  \(n.mac)").font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if n.online {
                            Pill(text: n.latencyMs.map { "Online · \(Diagnosis.fmt($0)) ms" } ?? "Online", symbol: "checkmark", color: .green)
                        } else {
                            Pill(text: "Non risponde", symbol: "xmark", color: .red)
                            Button("Dimentica") { model.forgetNode(n.mac) }.glassButton()
                                .help("Se hai tolto questo nodo per sempre, non verrà più segnalato.")
                        }
                    }
                }
            }
        }

        SectionTitle(text: "Altri dispositivi", symbol: "laptopcomputer.and.iphone").padding(.top, 8)
        Text("Telefoni e TV usano indirizzi casuali, quindi molti compaiono come «Altro dispositivo». Se la chiavetta non viene riconosciuta, scegli tu quale è.")
            .font(.callout).foregroundStyle(.secondary)
        let others = model.devices.filter { !$0.isStarlinkNode }
        if others.isEmpty {
            EmptyHint(symbol: "network", title: "Nessuna scansione", message: "Premi «Cerca» in alto.")
        }
        ForEach(others) { d in
            Card {
                HStack(spacing: 14) {
                    Image(systemName: d.kind.symbol).font(.title2).frame(width: 36).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(d.kind.label).font(.headline)
                            if d.ip == model.fireStickIP { Pill(text: "Fire Stick scelto", symbol: "checkmark", color: .green) }
                        }
                        Text("\(d.ip)  ·  \(d.mac.isEmpty ? "questo Mac" : d.mac)").font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(d.openPorts, id: \.self) { Pill(text: ":\($0)", color: .secondary) }
                    if (d.kind == .fireTV || d.kind == .other), d.ip != model.fireStickIP {
                        Button("Usa come Fire Stick") { model.fireStickIP = d.ip }.glassButton()
                    }
                }
            }
        }

        HStack {
            Spacer()
            Button("Azzera l'elenco dei nodi") { confirmForget = true }.glassButton()
        }
        .confirmationDialog("Azzerare l'elenco dei nodi Starlink?", isPresented: $confirmForget) {
            Button("Azzera", role: .destructive) { model.forgetKnownNodes() }
        } message: { Text("Perdi i nomi dati ai nodi, e un nodo spento non verrà più segnalato.") }
    }
}

// MARK: - Fire Stick

struct FireStickView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmSwitch = false

    var body: some View {
        SectionTitle(text: "Fire Stick", symbol: "tv.fill")

        if !model.adbInstalled {
            Card(tint: .orange) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Serve ADB (lo strumento di debug di Android)", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text("Installalo una volta sola dal Terminale:").foregroundStyle(.secondary)
                    Text("brew install --cask android-platform-tools").font(.callout.monospaced()).textSelection(.enabled)
                        .padding(8).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }

        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Indirizzo").font(.callout.weight(.semibold))
                    TextField("192.168.1.x", text: $model.fireStickIP).textFieldStyle(.roundedBorder).frame(width: 170)
                    Button { Task { await model.refreshFireStick() } } label: {
                        if model.isBusy("firestick") { ProgressView().controlSize(.small) } else { Text("Collega e leggi") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.fireStickIP.isEmpty || !model.adbInstalled || model.anyBusy)
                    Spacer()
                }
                if let p = model.fireStickProblem {
                    Label(p, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
            }
        }

        if model.fireStickProblem != nil || model.fireStick == nil {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("La chiavetta non risponde?").font(.headline)
                    Text("Accendi la TV e premi un tasto del telecomando per svegliarla. L'app cerca di nuovo la chiavetta sulla rete (anche se ha cambiato indirizzo) e riprova a collegarsi fino a 6 volte.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button { model.perform(.recoverFireStick) } label: {
                            if model.isBusy("recover") { ProgressView().controlSize(.small) } else { Label("Riconnetti Fire Stick", systemImage: "link") }
                        }
                        .buttonStyle(PrimaryButtonStyle()).disabled(model.anyBusy || !model.adbInstalled)
                        if !model.recoveryMessage.isEmpty { Text(model.recoveryMessage).font(.callout).foregroundStyle(Theme.accentDeep) }
                    }
                    Text("Se compare «Consentire il debug?» sulla TV: spunta «Consenti sempre» e premi OK. Per attivare il debug: Impostazioni → La mia Fire TV → Opzioni sviluppatore → Debug ADB.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        if let f = model.fireStick {
            let rssi = f.rssi ?? -127
            let sev: Severity = rssi >= -67 ? .ok : rssi >= -72 ? .warn : .bad
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                MetricTile(title: "Segnale", value: f.rssi.map(String.init) ?? "—", unit: "dBm", caption: "\(f.band.rawValue) · \(f.model)", severity: sev, symbol: "wifi")
                MetricTile(title: "Collegamento", value: f.linkMbps.map(String.init) ?? "—", unit: "Mbps", caption: "Velocità negoziata col nodo", severity: .info, symbol: "arrow.left.arrow.right")
                MetricTile(title: "Ping internet", value: f.ping.map { $0.isUnreachable ? "—" : Diagnosis.fmt($0.avg) } ?? "—", unit: "ms",
                           caption: f.ping.map { "\(Diagnosis.fmt($0.loss))% persi · picco \(Diagnosis.fmt($0.max)) ms" } ?? "",
                           severity: (f.ping?.loss ?? 0) >= 3 ? .bad : .info, symbol: "globe")
                MetricTile(title: "Velocità reale", value: f.downMbps.map { Diagnosis.fmt($0) } ?? "—", unit: "Mbps",
                           caption: f.foregroundApp.map { "In primo piano: \($0)" } ?? "Premi «Misura velocità reale»",
                           severity: f.downMbps.map { $0 < 8 ? .bad : $0 < 25 ? .warn : .ok } ?? .info, symbol: "speedometer")
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cerca segnale migliore").font(.headline)
                    Text("Non si può scegliere il nodo mesh: è la TV a decidere. Questo riavvia il Wi‑Fi della chiavetta (fino a 5 volte) finché si aggancia a un segnale almeno pari alla soglia. La riproduzione si interrompe per circa un minuto a tentativo.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Text("Soglia: \(model.minRSSI) dBm").font(.callout.monospacedDigit())
                        Stepper("", value: $model.minRSSI, in: -75...(-55)).labelsHidden()
                        Spacer()
                        if model.isBusy("switch") {
                            Button("Interrompi") { model.cancelSwitch() }.glassButton()
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Cerca segnale migliore") { confirmSwitch = true }
                                .buttonStyle(PrimaryButtonStyle()).disabled(!model.adbInstalled || model.anyBusy)
                        }
                    }
                    if !model.switchMessage.isEmpty { Text(model.switchMessage).font(.callout).foregroundStyle(Theme.accentDeep) }
                    ForEach(model.switchAttempts) { a in
                        HStack(spacing: 8) {
                            Image(systemName: a.accepted ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(a.accepted ? .green : .secondary)
                            Text("Tentativo \(a.number): \(a.rssi.map { "\($0) dBm" } ?? "—") · \(a.frequencyMHz.map { Band.fromFrequency($0).rawValue } ?? "—") · \(a.linkMbps ?? 0) Mbps")
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
            .confirmationDialog("Riavviare il Wi‑Fi del Fire Stick?", isPresented: $confirmSwitch) {
                Button("Riavvia e cerca", role: .destructive) { model.fireStickSmartSwitch() }
            } message: { Text("Se stai guardando qualcosa, l'immagine si ferma per circa un minuto a tentativo.") }

            HStack {
                Button { Task { await model.fireStickSpeedTest() } } label: {
                    if model.isBusy("fsspeed") { ProgressView().controlSize(.small) } else { Label("Misura velocità reale", systemImage: "speedometer") }
                }
                .glassButton().disabled(model.anyBusy)
                .help("Scarica 25 MB direttamente dalla chiavetta: occupa la linea ~15 s.")
                Button { Task { await model.refreshFireStick() } } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
                    .glassButton().disabled(model.anyBusy)
            }
        }
    }
}

// MARK: - Wi‑Fi del Mac

struct MacWiFiView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            SectionTitle(text: "Wi‑Fi del Mac", symbol: "wifi")
            Spacer()
        }

        if let w = model.wifi {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                MetricTile(title: "Banda", value: w.band.rawValue, caption: "Canale \(w.channel) · \(w.widthMHz) MHz", severity: w.band == .ghz24 ? .warn : .ok, symbol: "antenna.radiowaves.left.and.right")
                MetricTile(title: "Segnale", value: "\(w.rssi)", unit: "dBm", caption: "Rumore \(w.noise) dBm", severity: w.rssi >= -67 ? .ok : w.rssi >= -75 ? .warn : .bad, symbol: "wifi")
                MetricTile(title: "Collegamento", value: "\(w.linkMbps)", unit: "Mbps", caption: w.phy, severity: .info, symbol: "arrow.left.arrow.right")
            }
        } else {
            EmptyHint(symbol: "wifi.slash", title: "Wi‑Fi non rilevato", message: "Il Mac non risulta collegato a una rete Wi‑Fi. Fai un'analisi completa dalla pagina Stato.")
        }

        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cerca connessione migliore").font(.headline)
                Text("Spegne e riaccende il Wi‑Fi del Mac (fino a 4 volte) finché si aggancia ai 5 GHz o a un segnale forte. Ogni volta il Mac rifà la scelta del nodo mesh; per qualche secondo resti senza internet.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button { Task { await model.macSmartReconnect() } } label: {
                        if model.isBusy("mac") { ProgressView().controlSize(.small) } else { Label("Cerca connessione migliore", systemImage: "arrow.triangle.2.circlepath") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.anyBusy)
                    Button { Task { await model.reconnectMac() } } label: { Text("Riconnetti una volta") }
                        .glassButton().disabled(model.anyBusy)
                }
                if !model.macMessage.isEmpty { Text(model.macMessage).font(.callout).foregroundStyle(Theme.accentDeep) }
                ForEach(Array(model.macAttempts.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }

        HStack {
            SectionTitle(text: "Reti salvate")
            Spacer()
            Button("Carica elenco") { Task { await model.loadSavedNetworks() } }.glassButton()
        }
        Text("Il cambio rete dal programma può essere rifiutato da macOS: in quel caso scegli la rete dal menu Wi‑Fi in alto.")
            .font(.caption).foregroundStyle(.secondary)
        ForEach(model.savedNetworks, id: \.self) { name in
            Card(padding: 10) {
                HStack {
                    Image(systemName: "wifi").foregroundStyle(.secondary)
                    Text(name)
                    Spacer()
                    Button("Collegati") { Task { await model.join(name) } }.glassButton().disabled(model.anyBusy)
                }
            }
        }
    }
}

// MARK: - Monitor

struct MonitorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            SectionTitle(text: "Monitor in tempo reale", symbol: "waveform.path.ecg")
            Spacer()
            Button { model.toggleMonitor() } label: {
                Label(model.monitoring ? "Ferma" : "Avvia", systemImage: model.monitoring ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        Text("Ping leggeri ogni pochi secondi verso router, internet e Fire Stick (se collegato). Non occupano la linea: si può tenere acceso durante una partita per vedere quando e dove si blocca.")
            .font(.callout).foregroundStyle(.secondary)

        if model.monitor.isEmpty {
            EmptyHint(symbol: "waveform.path.ecg", title: "Nessun dato", message: "Premi «Avvia».")
        } else {
            Card {
                Chart {
                    ForEach(model.monitor) { p in
                        if let v = p.routerMs {
                            LineMark(x: .value("Ora", p.date), y: .value("ms", v), series: .value("Serie", "Router"))
                                .foregroundStyle(by: .value("Serie", "Router"))
                        }
                        if let v = p.internetMs {
                            LineMark(x: .value("Ora", p.date), y: .value("ms", v), series: .value("Serie", "Internet"))
                                .foregroundStyle(by: .value("Serie", "Internet"))
                        }
                        if let v = p.fireStickMs {
                            LineMark(x: .value("Ora", p.date), y: .value("ms", v), series: .value("Serie", "Fire Stick"))
                                .foregroundStyle(by: .value("Serie", "Fire Stick"))
                        }
                        if p.internetLoss >= 25 {
                            PointMark(x: .value("Ora", p.date), y: .value("ms", 0)).foregroundStyle(.red).symbolSize(60)
                        }
                    }
                }
                .chartForegroundStyleScale(["Router": Color.green, "Internet": Theme.accentDeep, "Fire Stick": Color.orange])
                .chartYAxisLabel("ms")
                .frame(height: 280)
            }
            if let last = model.monitor.last {
                let lossCount = model.monitor.filter { $0.internetLoss >= 25 }.count
                HStack(spacing: 14) {
                    MetricTile(title: "Router", value: last.routerMs.map { Diagnosis.fmt($0) } ?? "—", unit: "ms", severity: .info, symbol: "wifi.router")
                    MetricTile(title: "Internet", value: last.internetMs.map { Diagnosis.fmt($0) } ?? "—", unit: "ms",
                               caption: "\(Diagnosis.fmt(last.internetLoss))% persi", severity: last.internetLoss >= 25 ? .bad : .info, symbol: "globe")
                    MetricTile(title: "Cadute", value: "\(lossCount)", caption: "Campioni con molti pacchetti persi (punti rossi)", severity: lossCount > 3 ? .warn : .info, symbol: "exclamationmark.triangle")
                }
            }
        }
    }
}

// MARK: - Registro

struct ActivityView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SectionTitle(text: "Registro", symbol: "list.bullet.rectangle")
        if model.log.isEmpty {
            EmptyHint(symbol: "list.bullet.rectangle", title: "Ancora niente", message: "Qui compare tutto quello che l'app fa.")
        } else {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.log.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
    }
}
