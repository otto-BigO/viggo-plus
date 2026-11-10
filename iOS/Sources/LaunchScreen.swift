import SwiftUI

/// Shown at launch until the first sync is done. A lo-fi pixel landscape at the real time of
/// day (dawn, day, dusk or night) with Ugle, the Viggo+ owl, on a fence post with headphones on,
/// nodding to the beat while notes drift up. Everything is computed from position and time
/// (no image files), so it fits any screen.
struct LaunchScreen: View {
    let style = IconStyle.current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var showText = false
    @State private var step = 0

    /// Test hooks: `VIGGO_SPLASH_T=2.5` freezes the animation at that second and keeps it on
    /// screen, `VIGGO_SPLASH_HOUR=21` picks the time of day.
    static let frozen = ProcessInfo.processInfo.environment["VIGGO_SPLASH_T"].flatMap(Double.init)
    static let hour: Double = ProcessInfo.processInfo.environment["VIGGO_SPLASH_HOUR"].flatMap(Double.init) ?? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }()

    private let steps = ["Henter skema", "Henter lektier", "Henter beskeder", "Næsten klar"]

    var body: some View {
        GeometryReader { geo in
            let scene = PixelScene(size: geo.size, hour: Self.hour, accent: style.top)
            ZStack {
                scene.palette.skyTop
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                    let t = Self.frozen ?? (reduceMotion ? 3 : tl.date.timeIntervalSince(start))
                    Canvas { ctx, _ in scene.draw(in: ctx, t: t) }
                }
                VStack(spacing: 14) {
                    Text("Viggo+")
                        .font(.system(size: 34, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 2, y: 2)
                    NowPlaying(step: steps[step], index: step, accent: scene.palette.accent, live: !reduceMotion)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 10)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.2)
            }
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    private func run() async {
        start = Date()
        if reduceMotion || (Self.frozen ?? 0) > 0.9 {
            showText = true
        } else {
            try? await Task.sleep(for: .milliseconds(550))
            Haptic.soft()                        // the owl lands on the post
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showText = true }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1100))
            guard step < steps.count - 1 else { break }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 }
        }
    }
}

/// The "now playing" card under the title, like the overlay on a radio stream.
private struct NowPlaying: View {
    let step: String
    let index: Int
    let accent: Color
    let live: Bool

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !live)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let h = live ? 4 + 10 * abs(sin(t * (3.1 + Double(i) * 1.3) + Double(i))) : 8
                        Rectangle().fill(accent).frame(width: 3, height: h)
                    }
                }
                .frame(width: 18, height: 14, alignment: .bottom)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("VIGGO+ FM · \(index + 1)/4")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                ZStack(alignment: .leading) {
                    Text(step)
                        .id(step)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 150, height: 16, alignment: .leading)
                .clipped()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - The scene

/// Colours for one moment of the day.
struct SkyPalette {
    var skyTop, skyBottom, sun, far, mid, near, ground, grass, window: Color
    var accent: Color
    var stars: Double          // 0 to 1
    var lights: Double         // how lit the school windows and fireflies are
    var sunHeight: Double      // 0 at the horizon, 1 high up; the moon at night

    static func at(hour h: Double, accent: Color) -> SkyPalette {
        let hex = IconStyle.hex
        let night = SkyPalette(skyTop: hex(0x0D1030), skyBottom: hex(0x2B2A5C), sun: hex(0xF4EFD8),
                               far: hex(0x262650), mid: hex(0x1B1C40), near: hex(0x121331), ground: hex(0x0C0D24),
                               grass: hex(0x1F2A52), window: hex(0xFFD27A), accent: accent, stars: 1, lights: 1, sunHeight: 0.7)
        let dawn = SkyPalette(skyTop: hex(0x5B6FB8), skyBottom: hex(0xFFB38A), sun: hex(0xFFE3A3),
                              far: hex(0x9A86B8), mid: hex(0x6D6A9E), near: hex(0x47507A), ground: hex(0x2F3858),
                              grass: hex(0x5D7A6E), window: hex(0xFFD27A), accent: accent, stars: 0.15, lights: 0.4, sunHeight: 0.15)
        let day = SkyPalette(skyTop: hex(0x5FA8E8), skyBottom: hex(0xBFE3F5), sun: hex(0xFFF4C2),
                             far: hex(0x8FC0B5), mid: hex(0x5FA27F), near: hex(0x3E8159), ground: hex(0x2C6343),
                             grass: hex(0x7CC46C), window: hex(0xD8EEF7), accent: accent, stars: 0, lights: 0, sunHeight: 0.8)
        let dusk = SkyPalette(skyTop: hex(0x3B3478), skyBottom: hex(0xFF8A6B), sun: hex(0xFFC56E),
                              far: hex(0x8A5A8C), mid: hex(0x5E3F6E), near: hex(0x3A2B52), ground: hex(0x261C3A),
                              grass: hex(0x6B4E6E), window: hex(0xFFD27A), accent: accent, stars: 0.25, lights: 0.8, sunHeight: 0.12)
        // Blend between the four around the clock so 7.30 and 18.30 look in between.
        let keys: [(Double, SkyPalette)] = [(0, night), (5, night), (7, dawn), (9.5, day), (16.5, day), (19, dusk), (21.5, night), (24, night)]
        for i in 0..<keys.count - 1 where h >= keys[i].0 && h <= keys[i + 1].0 {
            let f = (h - keys[i].0) / (keys[i + 1].0 - keys[i].0)
            return keys[i].1.mix(keys[i + 1].1, f)
        }
        return day
    }

    func mix(_ o: SkyPalette, _ f: Double) -> SkyPalette {
        func m(_ a: Color, _ b: Color) -> Color { a.mix(with: b, by: f) }
        func n(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return SkyPalette(skyTop: m(skyTop, o.skyTop), skyBottom: m(skyBottom, o.skyBottom), sun: m(sun, o.sun),
                          far: m(far, o.far), mid: m(mid, o.mid), near: m(near, o.near), ground: m(ground, o.ground),
                          grass: m(grass, o.grass), window: m(window, o.window), accent: accent,
                          stars: n(stars, o.stars), lights: n(lights, o.lights), sunHeight: n(sunHeight, o.sunHeight))
    }
}

/// The landscape, drawn on a coarse pixel grid. Coordinates are in pixels (cells), y down.
struct PixelScene {
    let size: CGSize
    let px: CGFloat            // points per pixel
    let cols: Int, rows: Int
    let palette: SkyPalette
    let isNight: Bool

    init(size: CGSize, hour: Double, accent: Color) {
        self.size = size
        px = max(3, (size.width / 96).rounded())
        cols = Int((size.width / px).rounded(.up))
        rows = Int((size.height / px).rounded(.up))
        palette = SkyPalette.at(hour: hour, accent: accent)
        isNight = hour < 6.5 || hour > 20
    }

    private var horizon: Double { Double(rows) * 0.66 }

    func draw(in ctx: GraphicsContext, t: Double) {
        let p = palette
        func rect(_ x: Double, _ y: Double, _ w: Double = 1, _ h: Double = 1, _ c: Color) {
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px, height: CGFloat(h) * px)), with: .color(c))
        }

        // Sky: hard colour bands with a checker dither between them, the classic lo-fi look.
        let bands = 12
        let skyRows = horizon
        for b in 0..<bands {
            let y0 = skyRows * Double(b) / Double(bands), y1 = skyRows * Double(b + 1) / Double(bands)
            let c = p.skyTop.mix(with: p.skyBottom, by: Double(b) / Double(bands - 1))
            rect(0, y0.rounded(.down), Double(cols), (y1 - y0).rounded(.up) + 1, c)
            if b < bands - 1 {                       // dither the seam with the next band
                let next = p.skyTop.mix(with: p.skyBottom, by: Double(b + 1) / Double(bands - 1))
                let y = y1.rounded(.down) - 1
                for x in stride(from: Int(y) % 2, to: cols, by: 2) { rect(Double(x), y, 1, 1, next) }
            }
        }

        // Stars, twinkling.
        if p.stars > 0.05 {
            for i in 0..<70 {
                let x = Double(Int(hash(i, 1) * Double(cols)))
                let y = Double(Int(hash(i, 2) * skyRows * 0.8))
                let tw = 0.5 + 0.5 * sin(t * (1 + hash(i, 3) * 2.5) + Double(i))
                let a = p.stars * (0.35 + 0.65 * tw)
                rect(x, y, 1, 1, Color.white.opacity(a))
                if hash(i, 4) > 0.93, tw > 0.7 {      // a few bright ones get a little cross
                    for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)] { rect(x + dx, y + dy, 1, 1, Color.white.opacity(a * 0.5)) }
                }
            }
        }

        // Sun or moon, with a soft halo of rings.
        let sx = Double(cols) * 0.76, sy = skyRows * (0.92 - 0.5 * p.sunHeight)
        let sr = isNight ? 5.0 : 7.0
        for (k, a) in [(2.6, 0.08), (1.8, 0.14)] { disc(ctx, sx, sy, sr * k, p.sun.opacity(a)) }
        disc(ctx, sx, sy, sr, p.sun)
        if isNight { disc(ctx, sx + 2.5, sy - 1.5, sr * 0.85, p.skyTop.mix(with: p.skyBottom, by: 0.15)) }   // crescent

        // Clouds drifting right.
        for i in 0..<4 {
            let w = 14 + hash(i, 9) * 16
            let speed = 0.6 + hash(i, 8) * 0.9
            let span = Double(cols) + w * 2
            let x = (hash(i, 7) * span + t * speed).truncatingRemainder(dividingBy: span) - w
            let y = skyRows * (0.12 + 0.45 * hash(i, 6))
            cloud(ctx, x, y, w, isNight ? Color.white.opacity(0.12) : Color.white.opacity(0.85 - Double(i) * 0.1))
        }

        // Three layers of hills, slowly scrolling at different speeds (parallax).
        hills(ctx, base: horizon - 10, amp: 7, freq: 0.045, speed: 0.4, t: t, seed: 1, color: p.far)
        school(ctx, x: Double(cols) * 0.1, ground: hillY(Double(cols) * 0.1 + 9, base: horizon - 5, amp: 5, freq: 0.07, shift: 0, seed: 2), t: t)
        hills(ctx, base: horizon - 5, amp: 5, freq: 0.07, speed: 0, t: t, seed: 2, color: p.mid)
        hills(ctx, base: horizon + 3, amp: 3, freq: 0.11, speed: 1.4, t: t, seed: 3, color: p.near)

        // Foreground: ground, grass blades waving, a fence and the owl on its post.
        let gy = Double(rows) * 0.8
        rect(0, gy, Double(cols), Double(rows) - gy + 1, p.ground)
        for x in 0..<cols {
            let sway = sin(t * 1.6 + Double(x) * 0.35) * 0.8
            let h = 1 + Double(Int(hash(x, 11) * 3))
            rect(Double(x) + (h > 2 ? sway.rounded() : 0), gy - h, 1, h, p.grass)
        }
        fence(ctx, gy: gy)

        // Fireflies at dusk and night.
        if p.lights > 0.3 {
            for i in 0..<9 {
                let x = Double(cols) * hash(i, 21) + sin(t * 0.7 + Double(i)) * 6
                let y = gy - 4 - hash(i, 22) * 16 + cos(t * 0.9 + Double(i) * 2) * 3
                let on = 0.5 + 0.5 * sin(t * 2.3 + Double(i) * 1.7)
                rect(x.rounded(), y.rounded(), 1, 1, p.window.opacity(p.lights * on))
            }
        }

        groundDetail(ctx, gy: gy)
        owl(ctx, x: (Double(cols) / 2 - 16).rounded(), postTop: gy - 36, t: t)

        // Scanlines and a vignette for the stream look.
        for y in stride(from: 0, to: rows, by: 2) {
            ctx.fill(Path(CGRect(x: 0, y: CGFloat(y) * px + px * 0.75, width: size.width, height: px * 0.25)), with: .color(.black.opacity(0.04)))
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.35)]),
                                       center: CGPoint(x: size.width / 2, y: size.height * 0.45),
                                       startRadius: size.width * 0.45, endRadius: size.height * 0.75))
        // Fade in from black at the start.
        if t < 0.6 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(1 - t / 0.6))) }
    }

    // MARK: pieces

    private func disc(_ ctx: GraphicsContext, _ cx: Double, _ cy: Double, _ r: Double, _ c: Color) {
        var path = Path()
        for y in Int(cy - r)...Int(cy + r) {
            let dy = Double(y) + 0.5 - cy
            let half = (r * r - dy * dy)
            guard half > 0 else { continue }
            let w = half.squareRoot()
            let x0 = (cx - w).rounded(), x1 = (cx + w).rounded()
            path.addRect(CGRect(x: CGFloat(x0) * px, y: CGFloat(y) * px, width: CGFloat(x1 - x0) * px, height: px))
        }
        ctx.fill(path, with: .color(c))
    }

    private func cloud(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ c: Color) {
        var path = Path()
        let puffs = [(0.0, 0.0, 0.5), (0.3, -0.25, 0.45), (0.6, -0.1, 0.4), (0.85, 0.05, 0.3)]
        for (fx, fy, fr) in puffs {
            let r = w * fr * 0.5, cx = x + w * fx, cy = y + w * fy * 0.5
            for yy in Int(cy - r)...Int(cy) {           // flat bottoms, like pixel clouds
                let dy = Double(yy) + 0.5 - cy
                let hw = (r * r - dy * dy)
                guard hw > 0 else { continue }
                let s = hw.squareRoot()
                path.addRect(CGRect(x: CGFloat((cx - s).rounded()) * px, y: CGFloat(yy) * px,
                                    width: CGFloat((2 * s).rounded()) * px, height: px))
            }
        }
        ctx.fill(path, with: .color(c))
    }

    private func hillY(_ x: Double, base: Double, amp: Double, freq: Double, shift: Double, seed: Int) -> Double {
        let s = Double(seed)
        let u = x + shift
        return base - amp * (sin(u * freq + s) * 0.6 + sin(u * freq * 2.3 + s * 3) * 0.3 + sin(u * freq * 5.1 + s * 7) * 0.1)
    }

    private func hills(_ ctx: GraphicsContext, base: Double, amp: Double, freq: Double, speed: Double, t: Double, seed: Int, color: Color) {
        var path = Path()
        for x in 0..<cols {
            let y = hillY(Double(x), base: base, amp: amp, freq: freq, shift: t * speed, seed: seed).rounded()
            path.addRect(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: size.height - CGFloat(y) * px))
        }
        ctx.fill(path, with: .color(color))
    }

    /// A small school on the middle hill: lit windows when it is dark, a flag that waves.
    private func school(_ ctx: GraphicsContext, x: Double, ground: Double, t: Double) {
        let p = palette
        let body = p.mid.mix(with: .black, by: 0.25)
        func r(_ a: Double, _ b: Double, _ w: Double, _ h: Double, _ c: Color) {
            ctx.fill(Path(CGRect(x: CGFloat(a) * px, y: CGFloat(b) * px, width: CGFloat(w) * px, height: CGFloat(h) * px)), with: .color(c))
        }
        let top = ground.rounded() - 8
        r(x, top, 19, 10, body)                                  // main block
        for i in 0..<4 { r(x + 1 + Double(i) * 2, top - 1 - Double(i), 17 - Double(i) * 4, 1, body) }   // roof
        r(x + 15, top - 9, 1, 6, body)                           // flagpole
        for i in 0..<3 {                                          // flag
            let dy = (sin(t * 4 + Double(i)) * 0.6).rounded()
            r(x + 16 + Double(i), top - 9 + dy, 1, 2, p.accent)
        }
        let lit = p.window.opacity(0.25 + 0.75 * p.lights)
        for row in 0..<2 { for col in 0..<5 where !(row == 1 && col == 2) { r(x + 2 + Double(col) * 3.5, top + 2 + Double(row) * 4, 2, 2, lit) } }
        r(x + 8.5, top + 6, 2, 4, body.mix(with: .black, by: 0.4))     // door
    }

    private func fence(_ ctx: GraphicsContext, gy: Double) {
        let wood = palette.ground.mix(with: IconStyle.hex(0x8A5A3C), by: 0.55)
        let dark = wood.mix(with: .black, by: 0.3)
        var path = Path(), shade = Path()
        func add(_ p: inout Path, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            p.addRect(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px, height: CGFloat(h) * px))
        }
        for x in stride(from: 2, to: cols, by: 10) {
            add(&path, Double(x), gy - 7, 2, 9)
            add(&shade, Double(x + 1), gy - 7, 1, 9)
        }
        add(&path, 0, gy - 6, Double(cols), 1)
        add(&path, 0, gy - 3, Double(cols), 1)
        ctx.fill(path, with: .color(wood))
        ctx.fill(shade, with: .color(dark))
    }

    /// Dithered rows, a path and some flowers, so the ground in front is not one flat colour.
    private func groundDetail(_ ctx: GraphicsContext, gy: Double) {
        let p = palette
        var dark = Path(), flowers = Path(), path = Path()
        func add(_ q: inout Path, _ x: Double, _ y: Double, _ w: Double = 1, _ h: Double = 1) {
            q.addRect(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px, height: CGFloat(h) * px))
        }
        let start = Int(gy) + 3
        for y in start..<rows {
            let depth = Double(y - start) / Double(max(1, rows - start))
            for x in 0..<cols where hash(x, y) < 0.08 + depth * 0.5 && (x + y) % 2 == 0 { add(&dark, Double(x), Double(y)) }
        }
        // A path from the post down to the bottom edge, widening towards you.
        let mid = Double(cols) / 2
        for y in Int(gy) + 2..<rows {
            let f = Double(y) - gy
            let w = 4 + f * 0.6
            add(&path, (mid - w / 2 + sin(f * 0.12) * 3).rounded(), Double(y), w.rounded(), 1)
        }
        for i in 0..<14 {
            let x = (hash(i, 31) * Double(cols)).rounded()
            if abs(x - mid) < 10 { continue }
            add(&flowers, x, gy + 3 + (hash(i, 32) * (Double(rows) - gy - 6)).rounded())
        }
        ctx.fill(dark, with: .color(.black.opacity(0.18)))
        ctx.fill(path, with: .color(p.ground.mix(with: IconStyle.hex(0xC9A97A), by: p.lights > 0.5 ? 0.18 : 0.35)))
        ctx.fill(flowers, with: .color(p.accent.mix(with: .white, by: 0.3).opacity(0.5 + 0.5 * (1 - p.lights))))
    }

    // MARK: Ugle, the Viggo+ owl

    /// 16 x 16 sprite. B body, L light belly, E eye white, P pupil, K beak, F feet,
    /// H headphones (accent colour), D band, X "+" on the belly.
    static let owlOpen = [
        "....DDDDDDDD....",
        "..DD.B....B.DD..",
        ".D..BBB..BBB..D.",
        ".D.BBBBBBBBBB.D.",
        "HHBBEEEBBEEEBBHH",
        "HHBEEPEBBEPEEBHH",
        "HHBEEEEKKEEEEBHH",
        ".D.BBBBKKBBBB.D.",
        "...BBLLLLLLBB...",
        "..BBLLLXXLLLBB..",
        "..BBLLXXXXLLBB..",
        "..BBLLLXXLLLBB..",
        "...BBLLLLLLBB...",
        "....BBBBBBBB....",
        ".....FF..FF.....",
        "................",
    ]
    static let owlBlink: [String] = {
        var s = owlOpen
        s[4] = "HHBBBBBBBBBBBBHH"
        s[5] = "HHBEEEEBBEEEEBHH"
        return s
    }()

    private func owl(_ ctx: GraphicsContext, x: Double, postTop: Double, t: Double) {
        let p = palette
        let wood = p.ground.mix(with: IconStyle.hex(0x8A5A3C), by: 0.55)
        // The post the owl sits on, a bit taller than the fence.
        let k = 2.0                                   // the owl is drawn at double pixel size
        ctx.fill(Path(CGRect(x: CGFloat(x + 11) * px, y: CGFloat(postTop + 28) * px, width: 10 * px, height: 40 * px)), with: .color(wood))
        ctx.fill(Path(CGRect(x: CGFloat(x + 18) * px, y: CGFloat(postTop + 28) * px, width: 3 * px, height: 40 * px)), with: .color(wood.mix(with: .black, by: 0.3)))
        ctx.fill(Path(CGRect(x: CGFloat(x + 9) * px, y: CGFloat(postTop + 27) * px, width: 14 * px, height: 2 * px)), with: .color(wood.mix(with: .white, by: 0.15)))

        // Drops in from above, then nods to an 84 bpm beat.
        let land = 0.55
        let drop = t < land ? -pow(1 - t / land, 2) * 80 : 0
        let beat = t * 84 / 60
        let nod = t > land ? (sin(beat * .pi * 2) > 0.6 ? k : 0) : 0
        let blink = (t.truncatingRemainder(dividingBy: 3.4) > 3.25) || (t > 1.1 && t < 1.22)
        let sprite = blink ? Self.owlBlink : Self.owlOpen

        let body = IconStyle.hex(0x8B6A4F).mix(with: p.near, by: isNight ? 0.25 : 0)
        let colors: [Character: Color] = [
            "B": body, "L": IconStyle.hex(0xE9D6B5).mix(with: p.near, by: isNight ? 0.2 : 0),
            "E": .white, "P": IconStyle.hex(0x1B1B26), "K": IconStyle.hex(0xF2A33A),
            "F": IconStyle.hex(0xF2A33A), "H": p.accent, "D": IconStyle.hex(0x2A2A38), "X": p.accent,
        ]
        let oy = postTop + drop
        for (r, line) in sprite.enumerated() {
            // The head (top 8 rows) nods, the body stays put.
            let dy = r < 8 ? nod : 0
            for (c, ch) in line.enumerated() {
                guard let col = colors[ch] else { continue }
                ctx.fill(Path(CGRect(x: CGFloat(x + Double(c) * k) * px, y: CGFloat(oy + Double(r) * k + dy) * px, width: px * k, height: px * k)),
                         with: .color(col))
            }
        }

        // Music notes drifting up from the headphones.
        guard t > land else { return }
        let note = [".XX", ".X.", "XX."]           // a tiny pixel quaver
        for i in 0..<3 {
            let age = (t - land + Double(i) * 1.1).truncatingRemainder(dividingBy: 3.3)
            let nx = x + 34 + age * 3 + sin(age * 3 + Double(i)) * 1.5
            let ny = oy + 6 - age * 9
            let a = max(0, 1 - age / 3.3)
            for (r, line) in note.enumerated() {
                for (c, ch) in line.enumerated() where ch == "X" {
                    ctx.fill(Path(CGRect(x: CGFloat((nx + Double(c) * k).rounded()) * px, y: CGFloat((ny + Double(r) * k).rounded()) * px,
                                         width: px * k, height: px * k)), with: .color(Color.white.opacity(0.85 * a)))
                }
            }
        }
    }

    private func hash(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663)
        h ^= h >> 33; h &*= 0xff51_afd7_ed55_8ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
