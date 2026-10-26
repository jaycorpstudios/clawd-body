import SwiftUI
import HiloContract
import HiloRuntime
import HiloStore

enum PetState { case idle, working, alert, happy, error, worried, sleep }

extension PetState {
    init(_ status: SessionStatus) {
        self = switch status {
        case .working: .working
        case .waiting: .alert
        case .done: .happy
        case .error: .error
        case .idle: .idle
        }
    }
}

/// The 32×32 pixel pet, ported from `drawPet` and `drawAcc` in prototypes/buddy-sim.html.
struct PetView: View {
    var look: PetLook = .main
    var state: PetState = .idle
    var size: CGFloat = 42

    private var hue: Double { Double(look.hue) }
    private var acc: Accessory { look.accessory }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, unit: canvasSize.width / 32, t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func look(of project: Project?) -> PetLook {
        project.map { .of(project: $0.name) } ?? PetLook(hue: 22, accessory: .none)
    }

    private func draw(_ ctx: inout GraphicsContext, unit p: CGFloat, t: Double) {
        let work = Color(hex: "#ff9a52"), wait = Color(hex: "#ffc53d"), done = Color(hex: "#5ee3a8"), err = Color(hex: "#ff5d62")
        let info = Color(hex: "#7cc8ff")
        let tt = t + hue / 37
        let body = Color(hue: hue, saturation: 0.85, lightness: 0.58)
        let light = Color(hue: hue, saturation: 0.95, lightness: 0.72)
        let dark = Color(hue: hue, saturation: 0.70, lightness: 0.36)
        let eye = Color(hex: "#1b0f0a")
        let cx = 16.0, cy = 19.0, rx = 10.0
        var ry = 8.0, ox = 0.0, oy = 0.0
        switch state {
        case .idle: oy = (sin(tt * 2) * 0.7).rounded()
        case .working: oy = -abs(sin(tt * 7)).rounded()
        case .alert: oy = -(abs(sin(tt * 6)) * 4).rounded()
        case .happy: oy = -(abs(sin(tt * 5)) * 3).rounded()
        case .sleep: ry = sin(tt * 1.3) > 0 ? 8 : 7.6
        case .error: ox = (sin(tt * 28) * (sin(tt * 2) > 0 ? 1 : 0)).rounded()
        case .worried: ox = (sin(tt * 3) * 0.7).rounded()
        }
        func px(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color, absolute: Bool = false) {
            let dx = absolute ? 0 : ox, dy = absolute ? 0 : oy
            ctx.fill(Path(CGRect(x: (x + dx) * p, y: (y + dy) * p, width: w * p, height: h * p)), with: .color(c))
        }
        func inBody(_ x: Double, _ y: Double) -> Bool {
            let dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry
            return dx * dx + dy * dy <= 1
        }
        let step: Double = state == .working ? (sin(tt * 7) > 0 ? 1 : 0) : 0
        px(cx - 7, cy + ry - 1 - step, 4, 2, dark)
        px(cx + 3, cy + ry - 1 - (state == .working ? 1 - step : 0), 4, 2, dark)
        if state == .alert || state == .happy {
            let w: Double = sin(tt * 10) > 0 ? 1 : 0
            px(cx - rx - 2, cy - 4 - w, 2, 3, dark)
            px(cx + rx, cy - 4 - (1 - w), 2, 3, dark)
        } else {
            let tap: Double = state == .working ? (sin(tt * 14) > 0 ? 1 : 0) : 0
            px(cx - rx - 1, cy + 1 + tap, 2, 2, dark)
            px(cx + rx - 1, cy + 1 + (state == .working ? 1 - tap : 0), 2, 2, dark)
        }
        for y in 0..<32 {
            for x in 0..<32 where inBody(Double(x), Double(y)) {
                let fx = Double(x), fy = Double(y)
                var c = body
                if !inBody(fx, fy - 1) || !inBody(fx - 1, fy) { c = light } else if !inBody(fx, fy + 1) || !inBody(fx + 1, fy) { c = dark }
                px(fx, fy, 1, 1, c)
            }
        }
        px(cx - 7, cy - 5, 2, 1, light)
        px(cx - 8, cy - 4, 1, 2, light)
        let top = (cy - ry).rounded(.down)
        let hat = [.wizard, .crown, .party, .headphones].contains(acc)
        let tip: Color = switch state {
        case .idle: info
        case .working: work
        case .alert, .worried: wait
        case .happy: done
        case .error: err
        case .sleep: Color(hex: "#4a4a5a")
        }
        if !hat {
            px(15, top - 3, 2, 3, dark)
            px(14, top - 6, 4, 3, tip)
        }

        let ey = cy - 2
        let blink = tt.truncatingRemainder(dividingBy: 3.7) < 0.13
        let look: Double = state == .working ? (sin(tt * 1.1) > 0 ? 1 : -1) : state == .idle ? (sin(tt * 0.4) > 0.85 ? 1 : 0) : 0
        let l = 10 + look, r = 20 + look
        let hideEyes = acc == .shades || (acc == .heart && state != .sleep && state != .error && !blink)
        switch state {
        case _ where hideEyes:
            break
        case .happy:
            for ex in [l, r - 1] { px(ex, ey + 1, 1, 1, eye); px(ex + 1, ey, 1, 1, eye); px(ex + 2, ey + 1, 1, 1, eye) }
        case .error:
            for ex in [10.0, 19.0] {
                px(ex, ey, 1, 1, eye); px(ex + 2, ey, 1, 1, eye); px(ex + 1, ey + 1, 1, 1, eye)
                px(ex, ey + 2, 1, 1, eye); px(ex + 2, ey + 2, 1, 1, eye)
            }
        case _ where state == .sleep || blink:
            px(l, ey + 2, 2, 1, eye); px(r, ey + 2, 2, 1, eye)
        case .alert:
            px(9, ey - 1, 3, 4, eye); px(20, ey - 1, 3, 4, eye)
            px(9, ey - 1, 1, 1, .white); px(20, ey - 1, 1, 1, .white)
        default:
            px(l, ey, 2, 3, eye); px(r, ey, 2, 3, eye)
            px(l, ey, 1, 1, .white.opacity(0.53)); px(r, ey, 1, 1, .white.opacity(0.53))
        }
        let my = cy + 2
        switch state {
        case .happy: px(14, my, 1, 1, eye); px(15, my + 1, 2, 1, eye); px(17, my, 1, 1, eye)
        case .alert: px(15, my, 2, 2, eye)
        case .error:
            px(13, my + 1, 1, 1, eye); px(14, my, 1, 1, eye); px(15, my + 1, 1, 1, eye)
            px(16, my, 1, 1, eye); px(17, my + 1, 1, 1, eye)
        case .worried: px(15, my + 1, 2, 1, eye); px(14, my + 2, 1, 1, eye); px(17, my + 2, 1, 1, eye)
        case .sleep: px(15, my, 2, 1, dark)
        default: px(15, my, 2, 1, eye)
        }
        accessory(px, ey: ey, t: tt)
        if state == .happy || state == .idle {
            px(7, cy + 1, 2, 1, Color(hex: "#ff7aa8")); px(23, cy + 1, 2, 1, Color(hex: "#ff7aa8"))
        }
        if state == .worried {
            let d = (tt * 2).truncatingRemainder(dividingBy: 3).rounded()
            px(24, ey - 1 + d, 1, 1, info); px(23, ey + d, 3, 2, info)
        }
        if state == .alert {
            let b: Double = sin(tt * 8) > 0 ? 0 : 1
            px(26, 2 + b, 3, 6, wait, absolute: true); px(26, 9 + b, 3, 2, wait, absolute: true)
        }
        if state == .working {
            for i in 0..<3 {
                let ph = (tt * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                px(5 + Double(i) * 10 + (i == 1 ? 2 : 0), (10 - ph * 8).rounded(), 1, 1, work.opacity(1 - ph), absolute: true)
            }
        }
        if state == .sleep {
            for i in 0..<2 {
                let ph = (tt * 0.35 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                ctx.draw(Text("z").font(.system(size: p * 4, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: "#6d6a80").opacity(1 - ph)),
                         at: CGPoint(x: (23 + ph * 4) * p, y: (11 - ph * 8) * p), anchor: .bottomLeading)
            }
        }
    }

    private func accessory(_ fill: (Double, Double, Double, Double, Color, Bool) -> Void, ey: Double, t: Double) {
        let pu = Color(hex: "#7b4fc9"), pu2 = Color(hex: "#5e3aa3"), ye = Color(hex: "#ffcc3d")
        let bk = Color(hex: "#141210"), wh = Color(hex: "#f5f1ea"), teal = Color(hex: "#2bb3a6"), tealDark = Color(hex: "#1b7f76")
        func px(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) { fill(x, y, w, h, c, false) }
        switch acc {
        case .none:
            break
        case .shades:
            px(7, ey - 1, 18, 1, bk)
            for x0 in [8.0, 18.0] {
                px(x0, ey, 6, 2, bk); px(x0 + 1, ey + 2, 5, 1, bk); px(x0 + 2, ey + 3, 3, 1, bk)
                px(x0 + 1, ey, 1, 1, wh); px(x0 + 1, ey + 1, 2, 1, wh)
            }
        case .heart:
            let c = Color(hex: "#ff4d7a")
            for x0 in [9.0, 19.0] { px(x0, ey, 1, 1, c); px(x0 + 2, ey, 1, 1, c); px(x0, ey + 1, 3, 1, c); px(x0 + 1, ey + 2, 1, 1, c) }
        case .wizard:
            px(5, 10, 22, 1, pu2); px(9, 9, 14, 1, ye)
            for (i, (a, b)) in [(10.0, 21.0), (11, 20), (12, 19), (13, 18), (14, 17), (15, 16)].enumerated() {
                px(a, 8 - Double(i), b - a + 1, 1, i % 2 == 1 ? pu : pu2)
            }
            px(16, 2, 1, 1, pu)
            let wy = state == .working ? sin(t * 7).rounded() : 0
            px(27, 9 + wy, 1, 11, bk); px(26, 7 + wy, 3, 2, ye); px(27, 6 + wy, 1, 1, ye); px(25, 7 + wy, 1, 1, ye); px(29, 7 + wy, 1, 1, ye)
        case .headphones:
            let band = Color(hex: "#2b2f36")
            px(9, 9, 14, 1, band); px(8, 10, 1, 3, band); px(23, 10, 1, 3, band)
            px(4, 14, 3, 5, teal); px(25, 14, 3, 5, teal); px(5, 15, 1, 3, tealDark); px(26, 15, 1, 3, tealDark)
        case .crown:
            px(11, 8, 10, 3, ye); px(11, 6, 1, 2, ye); px(15, 5, 2, 3, ye); px(20, 6, 1, 2, ye)
            px(13, 9, 1, 1, Color(hex: "#ff5d62")); px(18, 9, 1, 1, Color(hex: "#5ee3a8"))
        case .party:
            for i in 0..<7 {
                let half = Double((i + 1) / 2)
                px(16 - half, 4 + Double(i), 1 + half * 2, 1, i % 2 == 1 ? Color(hex: "#ff7aa8") : Color(hex: "#7cc8ff"))
            }
            px(15, 2, 2, 2, ye)
        case .band:
            px(7, 12, 18, 2, teal); px(25, 12, 2, 1, teal); px(25, 14, 2, 2, tealDark); px(27, 15, 1, 2, tealDark)
        }
    }
}
