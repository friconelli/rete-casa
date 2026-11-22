import Foundation

// MARK: - Misure

struct PingStats: Equatable {
    var min: Double
    var avg: Double
    var max: Double
    var loss: Double   // percentuale 0...100
    var sent: Int

    static let unreachable = PingStats(min: 0, avg: 0, max: 0, loss: 100, sent: 0)
    var isUnreachable: Bool { loss >= 100 }
}

enum Band: String {
    case ghz24 = "2,4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"
    case unknown = "—"

    static func fromFrequency(_ mhz: Int) -> Band {
        switch mhz {
        case 2400..<2500: return .ghz24
        case 4900..<5900: return .ghz5
        case 5900..<7200: return .ghz6
        default: return .unknown
        }
    }
}

struct WiFiInfo: Equatable {
    var band: Band
    var channel: Int
    var widthMHz: Int
    var rssi: Int
    var noise: Int
    var linkMbps: Int
    var phy: String
}

struct SpeedResult: Equatable {
    var downMbps: Double
    var upMbps: Double
    var idleLatencyMs: Double
    var date: Date
}

struct FireStickStatus: Equatable {
    var ip: String
    var model: String
    var rssi: Int?
    var linkMbps: Int?
    var frequencyMHz: Int?
    var ping: PingStats?
    var foregroundApp: String?
    var downMbps: Double?

    var band: Band { frequencyMHz.map(Band.fromFrequency) ?? .unknown }
}

// MARK: - Dispositivi in rete

enum DeviceKind: String {
    case router, mesh, nas, fireTV, thisMac, other

    var label: String {
        switch self {
        case .router: return "Router Starlink"
        case .mesh: return "Mesh Starlink"
        case .nas: return "NAS / Plex"
        case .fireTV: return "Fire TV"
        case .thisMac: return "Questo Mac"
        case .other: return "Altro dispositivo"
        }
    }

    var symbol: String {
        switch self {
        case .router: return "wifi.router.fill"
        case .mesh: return "dot.radiowaves.left.and.right"
        case .nas: return "externaldrive.connected.to.line.below.fill"
        case .fireTV: return "tv.fill"
        case .thisMac: return "laptopcomputer"
        case .other: return "questionmark.circle"
        }
    }
}

struct LANDevice: Identifiable, Equatable {
    var ip: String
    var mac: String
    var kind: DeviceKind
    var openPorts: [Int]
    var latencyMs: Double?
    var id: String { mac.isEmpty ? ip : mac + ip }

    var isStarlinkNode: Bool { kind == .router || kind == .mesh }
}

// MARK: - Diagnosi

enum Severity: Int, Comparable {
    case ok = 0, info, warn, bad
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

/// Dove sta il problema.
enum Area: String {
    case starlink = "Starlink"
    case macWiFi = "Wi‑Fi del Mac"
    case mesh = "Mesh"
    case fireStick = "Fire Stick"
    case nas = "NAS / Plex"
    case general = "Generale"
}

/// Cosa può fare l'app per risolvere un problema.
enum FindingAction: String {
    case reconnectMac, fireStickSwitch, recoverFireStick, rescan

    var label: String {
        switch self {
        case .reconnectMac: return "Cerca connessione migliore"
        case .fireStickSwitch: return "Cerca segnale migliore"
        case .recoverFireStick: return "Riconnetti Fire Stick"
        case .rescan: return "Rifai l'analisi"
        }
    }
    var symbol: String {
        switch self {
        case .reconnectMac: return "arrow.triangle.2.circlepath"
        case .fireStickSwitch: return "tv"
        case .recoverFireStick: return "link"
        case .rescan: return "arrow.clockwise"
        }
    }
    /// Interrompe una riproduzione in corso: chiede conferma.
    var needsConfirm: Bool { self == .fireStickSwitch }
}

struct Finding: Identifiable, Equatable {
    var id = UUID()
    var severity: Severity
    var area: Area
    var title: String
    var detail: String
    var suggestion: String? = nil
    var action: FindingAction? = nil
}

/// Router o mesh Starlink, anche quando non risponde più.
struct NodeStatus: Identifiable, Equatable {
    var mac: String
    var name: String
    var ip: String
    var isRouter: Bool
    var online: Bool
    var latencyMs: Double?
    var id: String { mac }
}

/// Un passaggio dell'analisi completa.
struct CheckStep: Identifiable, Equatable {
    enum State: Equatable { case waiting, running, done(Severity), skipped }
    var id: String
    var title: String
    var state: State = .waiting
    var detail: String = ""
}

// MARK: - Monitor

struct MonitorPoint: Identifiable {
    let id = UUID()
    var date: Date
    var routerMs: Double?
    var internetMs: Double?
    var internetLoss: Double
    var fireStickMs: Double?
}
