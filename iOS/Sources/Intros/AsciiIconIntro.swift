import SwiftUI
import UIKit

/// The 0.7.0 intro: the Viggo+ icon builds itself out of ASCII
/// characters: the square fills in from the middle, the V decodes along its stroke, the "+"
/// pops in, and rings ripple out while Viggo answers. Every character is computed from a
/// formula of position and time (no drawn frames), so it scales to any screen.
struct AsciiIconIntro: View {
    let style = IconStyle.current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var showText = false
    @State private var cursor = false
    @State private var step = 0

    private static var frozen: Double? { LaunchScreen.frozen }

    private let steps = LaunchScreen.steps

    var body: some View {
        GeometryReader { geo in
            let field = AsciiIcon(style: style, size: geo.size)
            ZStack {
                Color(.systemBackground)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || Self.frozen != nil)) { tl in
                    let t = Self.frozen ?? (reduceMotion ? 3.5 : tl.date.timeIntervalSince(start))
                    Canvas { ctx, _ in field.draw(in: ctx, t: t) }
                }
                VStack(spacing: 10) {
                    Text("Viggo+")
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    HStack(spacing: 0) {
                        Text("> ").foregroundStyle(field.ink[0])
                        ZStack(alignment: .leading) {
                            Text(steps[step])
                                .id(step)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .move(edge: .top).combined(with: .opacity)))
                        }
                        .frame(height: 18)
                        .clipped()
                        Text("_").foregroundStyle(field.ink[0]).opacity(cursor ? 1 : 0)
                    }
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 12)
                .position(x: geo.size.width / 2, y: field.center.y + field.side * 0.5 + 78)
            }
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    private func run() async {
        start = Date()
        if reduceMotion || (Self.frozen ?? 0) > 1.1 {
            showText = true
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            Haptic.soft()
            try? await Task.sleep(for: .milliseconds(650))
            Haptic.firm()                       // the "+" lands
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showText = true }
        }
        withAnimation(.easeInOut(duration: 0.5).repeatForever()) { cursor = true }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1100))
            guard step < steps.count - 1 else { break }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 }
        }
    }
}

/// The ASCII field. Coordinates inside are in icon units: (0, 0) is the icon's centre and the
/// icon is 1 wide, y pointing down, matching `IconArt`.
struct AsciiIcon {
    let style: IconStyle
    let size: CGSize
    let cw: CGFloat            // cell width (one monospaced character)
    let ch: CGFloat = 10       // cell height
    let cols: Int, rows: Int
    let x0: CGFloat
    let center: CGPoint
    let side: CGFloat          // icon size in points
    let ink: [Color]           // brand colours top to bottom, readable on the system background
    let accent: Color          // the "+" badge

    static let fontSize: CGFloat = 9
    static let font = Font.system(size: fontSize, weight: .bold, design: .monospaced)

    init(style: IconStyle, size: CGSize) {
        self.style = style
        self.size = size
        let ui = UIFont.monospacedSystemFont(ofSize: Self.fontSize, weight: .bold)
        cw = ("M" as NSString).size(withAttributes: [.font: ui]).width
        cols = Int(size.width / cw)
        rows = Int(size.height / ch) + 1
        x0 = (size.width - CGFloat(cols) * cw) / 2
        side = min(size.width * 0.66, 280)
        center = CGPoint(x: size.width / 2, y: size.height * 0.4)
        // White glyphs vanish on a light background, so use the icon's own background colours instead.
        if style.glyph == [.white] { ink = [style.top, style.bottom] }
        else if style.id == "AppIcon-Midnat" { ink = style.badge }
        else { ink = style.glyph.count > 1 ? style.glyph : style.glyph + style.glyph }
        accent = style.badge == [.white] ? style.plus : style.badge[0]
    }

    // The V, same geometry as VShape inside IconArt.
    private static let p1 = SIMD2<Double>(-0.2064, -0.0896)
    private static let p2 = SIMD2<Double>(-0.05, 0.238)
    private static let p3 = SIMD2<Double>(0.1064, -0.0896)
    private static let vHalf = 0.065
    private static let badgeC = SIMD2<Double>(0.27, -0.26)
    private static let badgeR = 0.125

    private static let fillRamp: [Character] = Array(" .:-=+")
    private static let scramble: [Character] = Array("!/\\<>[]{}?*=+#%&$")
    private static let faintRamp: [Character] = Array(".'`,")
    private static let rippleRamp: [Character] = Array(".:-=+")

    func draw(in ctx: GraphicsContext, t: Double) {
        let fillR = ease(clamp(t / 0.7)) * 0.8                     // square fills from the middle out
        let drawT = clamp((t - 0.35) / 0.6)                        // how far along the V is drawn
        let bt = t - 1.0
        let badgeS = bt <= 0 ? 0 : 1 - exp(-7 * bt) * cos(13 * bt) // springy pop with a little overshoot
        let tick = Int(t * 14)                                     // how often scrambled glyphs change
        let noise = clamp(t / 0.8) * 0.03
        let sweepAge = t - 1.4
        let sweep = sweepAge > 0 ? (sweepAge.truncatingRemainder(dividingBy: 2.6) / 1.1) * 2.6 - 1.3 : -9
        let L = Double(side)

        for r in 0..<rows {
            let py = (Double(r) + 0.5) * Double(ch)
            let v = (py - Double(center.y)) / L
            var fill = [Character](repeating: " ", count: cols)
            var strong = fill, badge = fill, badgeDisc = fill, ripple = fill, faint = fill
            var used = (fill: false, strong: false, badge: false, disc: false, ripple: false, faint: false)

            for c in 0..<cols {
                let px = Double(x0) + (Double(c) + 0.5) * Double(cw)
                let u = (px - Double(center.x)) / L
                let p = SIMD2(u, v)
                let rnd = hash(c, r, tick)

                // "+" badge, with a thin gap around it like the icon's shadow.
                if badgeS > 0 {
                    let d = p - Self.badgeC
                    let rb = (d * d).sum().squareRoot()
                    let R = Self.badgeR * badgeS
                    if rb < R {
                        let arm = 0.09 * badgeS, thick = 0.03 * badgeS
                        let plus = (abs(d.x) < arm && abs(d.y) < thick) || (abs(d.y) < arm && abs(d.x) < thick)
                        // Solid "+" on a light disc, so it reads as a plus and not a ring.
                        if plus { badge[c] = "@"; used.badge = true }
                        else { badgeDisc[c] = rb > R * 0.82 ? "=" : ":"; used.disc = true }
                        continue
                    }
                    if rb < R + 0.035 { continue }
                }

                // The V: decoded glyphs behind the drawing front, scrambled glyphs right at it.
                let (dv, s) = vDistance(p)
                if dv < Self.vHalf, t > 0.35 {
                    if s <= drawT {
                        strong[c] = dv < Self.vHalf * 0.55 ? "@" : "#"; used.strong = true
                        continue
                    } else if s <= drawT + 0.14 {
                        strong[c] = Self.scramble[Int(rnd * Double(Self.scramble.count))]; used.strong = true
                        continue
                    }
                }

                // The rounded square, filled with a slowly flowing plasma.
                let box = roundBox(p)
                let dist = (p * p).sum().squareRoot()
                if box < 0, dist < fillR {
                    if fillR - dist < 0.06, fillR < 0.79 {
                        fill[c] = Self.scramble[Int(rnd * Double(Self.scramble.count))]; used.fill = true
                        continue
                    }
                    if abs((u + v) - sweep) < 0.05 {           // light sweeping across the icon
                        strong[c] = "+"; used.strong = true
                        continue
                    }
                    let rim = box > -0.035
                    let pl = (sin(u * 9 + t * 1.3) + sin(v * 7 - t * 1.1) + sin((u + v) * 6 + t * 0.7) + 3) / 6
                    let i = rim ? 5 : 1 + Int(pl * 3.99)
                    fill[c] = Self.fillRamp[min(i, Self.fillRamp.count - 1)]; used.fill = true
                    continue
                }

                // Outside: rings that follow the icon's shape, plus a light dust of characters.
                if bt > 0, box > 0 {
                    var best = 0.0
                    for k in 0..<2 {
                        let age = bt.truncatingRemainder(dividingBy: 1.6) + Double(k) * 1.6
                        guard age <= bt else { continue }
                        let rad = age * 0.42
                        let x = (box - rad) / 0.035
                        best = max(best, exp(-x * x) * max(0, 1 - age / 3.2))
                    }
                    if best > 0.3 {
                        let i = Int(best * Double(Self.rippleRamp.count - 1) + 0.5)
                        ripple[c] = Self.rippleRamp[min(i, Self.rippleRamp.count - 1)]; used.ripple = true
                        continue
                    }
                }
                if rnd < noise * max(0.25, 1.4 - dist) {
                    faint[c] = Self.faintRamp[Int(hash(r, c, 7) * Double(Self.faintRamp.count))]; used.faint = true
                }
            }

            // One Text per colour per row keeps it to a few hundred draws a frame.
            let frac = clamp(v + 0.5)
            let rowInk = ink[0].mix(with: ink[1], by: frac)
            let strongInk = ink[0].mix(with: ink[1], by: 0.4 + 0.6 * frac)   // a bit deeper, so the V stands out
            let y = CGFloat(r) * ch
            func put(_ chars: [Character], _ color: Color) {
                ctx.draw(Text(String(chars)).font(Self.font).foregroundStyle(color),
                         at: CGPoint(x: x0, y: y), anchor: .topLeading)
            }
            if used.faint { put(faint, Color.secondary.opacity(0.45)) }
            if used.ripple { put(ripple, ink[0].opacity(0.55)) }
            if used.fill { put(fill, rowInk.opacity(0.3)) }
            if used.strong { put(strong, strongInk) }
            if used.disc { put(badgeDisc, accent.opacity(0.5)) }
            if used.badge { put(badge, accent) }
        }
    }

    // MARK: shapes

    /// Distance to the V's centre line and how far along it (0 to 1) the nearest point is.
    private func vDistance(_ p: SIMD2<Double>) -> (Double, Double) {
        let (d1, h1) = segment(p, Self.p1, Self.p2)
        let (d2, h2) = segment(p, Self.p2, Self.p3)
        return d1 < d2 ? (d1, h1 * 0.5) : (d2, 0.5 + h2 * 0.5)
    }

    private func segment(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> (Double, Double) {
        let pa = p - a, ba = b - a
        let h = min(max((pa * ba).sum() / (ba * ba).sum(), 0), 1)
        let d = pa - ba * h
        return ((d * d).sum().squareRoot(), h)
    }

    /// Signed distance to the icon's rounded square (negative inside).
    private func roundBox(_ p: SIMD2<Double>) -> Double {
        let r = 0.225, half = 0.5
        let qx = abs(p.x) - (half - r), qy = abs(p.y) - (half - r)
        let ox = max(qx, 0), oy = max(qy, 0)
        return (ox * ox + oy * oy).squareRoot() + min(max(qx, qy), 0) - r
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private func ease(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    private func hash(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791)
        h ^= h >> 33; h &*= 0xff51_afd7_ed55_8ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
