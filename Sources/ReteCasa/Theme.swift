import SwiftUI

/// Palette presa dall'icona: blu notte, turchese del segnale, bianco caldo.
enum Theme {
    static let accent = Color(red: 0.10, green: 0.83, blue: 0.75)        // #1AD4C0
    static let accentDeep = Color(red: 0.00, green: 0.55, blue: 0.52)    // leggibile su fondo chiaro
    static let night = Color(red: 0.043, green: 0.106, blue: 0.180)      // #0B1B2E
    static let nightLight = Color(red: 0.07, green: 0.19, blue: 0.29)    // #12304A
    static let warm = Color(red: 0.957, green: 0.945, blue: 0.918)       // #F4F1EA

    static let heroGradient = LinearGradient(colors: [nightLight, night], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentGradient = LinearGradient(colors: [accent, Color(red: 0.12, green: 0.55, blue: 0.85)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardRadius: CGFloat = 16

    static func color(_ s: Severity) -> Color {
        switch s {
        case .ok: return .green
        case .info: return .blue
        case .warn: return .orange
        case .bad: return .red
        }
    }

    static func symbol(_ s: Severity) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var tint: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.07 : 0.40), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

struct Pill: View {
    let text: String
    var symbol: String? = nil
    var color: Color = Theme.accentDeep

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Riquadro con un valore grande: usato per segnale, ping, velocità.
struct MetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var caption: String = ""
    var severity: Severity = .info
    var symbol: String

    var body: some View {
        Card(padding: 14, tint: severity == .info ? nil : Theme.color(severity)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(severity == .info ? Theme.accentDeep : Theme.color(severity))
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value == "—" ? "n/d" : value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    if !unit.isEmpty { Text(unit).font(.callout).foregroundStyle(.secondary) }
                }
                Text(caption.isEmpty ? " " : caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Theme.accentDeep) }
            Text(text).font(.title3.weight(.semibold))
        }
    }
}

/// Pulsante principale (turchese pieno) e secondario.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(Theme.night)
            .background(Theme.accentGradient.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    var message: String = ""
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(Theme.accentGradient)
            Text(title).font(.headline)
            if !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

extension View {
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

/// Pulsante secondario per i fondi scuri (la «hero» in alto).
struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(Theme.warm)
            .background(Theme.warm.opacity(configuration.isPressed ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warm.opacity(0.25)))
    }
}
