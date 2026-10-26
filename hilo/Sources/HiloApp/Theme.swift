import SwiftUI
import HiloContract
import HiloStore

/// Dark theme tokens from prototypes/hilo/README.md.
enum Theme {
    static let window = Color(hex: "#161412")
    static let topBar = Color(hex: "#1c1a17")
    static let sidebar = Color(hex: "#12100e")
    static let card = Color(hex: "#1e1b18")
    static let softPanel = Color(hex: "#201d19")
    static let line = Color(hex: "#2a2723")
    static let lineStrong = Color(hex: "#36322d")
    static let text = Color(hex: "#efe9df")
    static let secondary = Color(hex: "#9c958a")
    static let muted = Color(hex: "#6f6a63")
    static let accent = Color(hex: "#0e7c72")
    static let link = Color(hex: "#5fd0c3")
    static let selected = Color(hex: "#173a36")
    static let selectedText = Color(hex: "#8be3d8")
    static let selectedBorder = Color(hex: "#2c6b63")
    static let doneCheck = Color(hex: "#3fbf86")
    static let needsYou = Color(hex: "#ffd27a")
    static let progress = Color(hex: "#ffb07a")

    static func chip(_ status: SessionStatus) -> (bg: Color, fg: Color, label: String) {
        switch status {
        case .working: (Color(hex: "#3a2210"), Color(hex: "#ffb07a"), "working")
        case .waiting: (Color(hex: "#3a2c0c"), Color(hex: "#ffd27a"), "needs you")
        case .done: (Color(hex: "#0f3324"), Color(hex: "#7ee2b0"), "done")
        case .error: (Color(hex: "#3a1416"), Color(hex: "#ff9a9d"), "failed")
        case .idle: (Color(hex: "#24211d"), Color(hex: "#9c958a"), "idle")
        }
    }

    static let stepColor: [StepKind: Color] = [
        .plan: Color(hex: "#7cc8ff"), .read: Color(hex: "#9c958a"), .edit: Color(hex: "#ff9a52"), .run: Color(hex: "#b98ae0"),
        .ask: Color(hex: "#ffc53d"), .ok: Color(hex: "#5ee3a8"), .deny: Color(hex: "#ff5d62"), .err: Color(hex: "#ff5d62"),
    ]

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let sectionLabel = Font.system(size: 11.5, weight: .semibold)
    static let mono = Font.system(size: 12.5, design: .monospaced)
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let h = hue.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = lightness - c / 2
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}

struct SectionLabel: View {
    let text: String
    var color = Theme.secondary

    var body: some View {
        Text(text.uppercased()).font(Theme.sectionLabel).tracking(1).foregroundStyle(color)
    }
}

struct StatusChip: View {
    let status: SessionStatus

    var body: some View {
        let c = Theme.chip(status)
        Text(c.label).font(.system(size: 11.5, weight: .bold)).lineLimit(1).fixedSize().padding(.horizontal, 9).padding(.vertical, 3)
            .background(c.bg, in: Capsule()).foregroundStyle(c.fg)
    }
}

struct ProjectDot: View {
    let project: Project?

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(Color(hex: project?.color ?? "#5a554e")).frame(width: 8, height: 8)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.card.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lineStrong))
            .foregroundStyle(Theme.text)
    }
}
