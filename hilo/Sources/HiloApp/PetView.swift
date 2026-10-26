import SwiftUI
import HiloContract
import HiloStore

enum PetState { case idle, working, alert, happy, error, sleep }

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

/// The 32×32 pixel pet, ported from `drawPet` in prototypes/buddy-sim.html (accessories not ported yet).
struct PetView: View {
    var hue: Double = 22
    var state: PetState = .idle
    var size: CGFloat = 42

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, unit: canvasSize.width / 32, t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func hue(of project: Project?) -> Double {
        guard let hex = project?.color, let v = UInt32(hex.dropFirst(), radix: 16) else { return 22 }
        let r = Double(v >> 16 & 0xff) / 255, g = Double(v >> 8 & 0xff) / 255, b = Double(v & 0xff) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return 22 }
        let h = mx == r ? (g - b) / d : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
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
        case .alert: oy = -(abs(sin(tt * 6)) * 3).rounded()
        case .happy: oy = -(abs(sin(tt * 5)) * 3).rounded()
        case .sleep: ry = sin(tt * 1.3) > 0 ? 8 : 7.6
        case .error: ox = (sin(tt * 28) * (sin(tt * 2) > 0 ? 1 : 0)).rounded()
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
        let tip: Color = switch state {
        case .idle: info
        case .working: work
        case .alert: wait
        case .happy: done
        case .error: err
        case .sleep: Color(hex: "#4a4a5a")
        }
        px(15, top - 3, 2, 3, dark)
        px(14, top - 6, 4, 3, tip)

        let ey = cy - 2
        let blink = tt.truncatingRemainder(dividingBy: 3.7) < 0.13
        let look: Double = state == .working ? (sin(tt * 1.1) > 0 ? 1 : -1) : 0
        let l = 10 + look, r = 20 + look
        switch state {
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
        default: px(15, my, 2, 1, eye)
        }
        if state == .happy || state == .idle {
            px(7, cy + 1, 2, 1, Color(hex: "#ff7aa8")); px(23, cy + 1, 2, 1, Color(hex: "#ff7aa8"))
        }
        if state == .alert {
            let b: Double = sin(tt * 8) > 0 ? 0 : 1
            px(27, 2 + b, 3, 6, wait, absolute: true); px(27, 9 + b, 3, 2, wait, absolute: true)
        }
        if state == .working {
            for i in 0..<3 {
                let ph = (tt * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                px(4 + Double(i) * 11, (10 - ph * 8).rounded(), 1, 1, work.opacity(1 - ph), absolute: true)
            }
        }
    }
}
