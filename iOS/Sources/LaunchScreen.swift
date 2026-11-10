import SwiftUI
import UIKit

/// Shown at launch until the first sync is done. A monochrome ASCII landscape in the style of
/// a lo-fi radio stream: by day black characters on cream (clouds, a dark band of hills, tall
/// grass in the wind), at night grey on black (a huge hatched ring, mountains, a forest).
/// Every character is computed from position and time, and the scene decodes in at the start.
struct LaunchScreen: View {
    let style = IconStyle.current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var showText = false
    @State private var step = 0

    /// Test hooks: `VIGGO_SPLASH_T=2.5` freezes the animation at that second and keeps it on
    /// screen, `VIGGO_SPLASH_HOUR=22` picks the time of day.
    static let frozen = ProcessInfo.processInfo.environment["VIGGO_SPLASH_T"].flatMap(Double.init)
    /// `VIGGO_SPLASH_HOLD=1` keeps it on screen while it animates normally.
    static let hold = frozen != nil || ProcessInfo.processInfo.environment["VIGGO_SPLASH_HOLD"] != nil
    static let hour: Double = ProcessInfo.processInfo.environment["VIGGO_SPLASH_HOUR"].flatMap(Double.init) ?? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }()
    static var night: Bool { hour < 7 || hour >= 19 }

    private let steps = ["Henter skema", "Henter lektier", "Henter beskeder", "Næsten klar"]

    var body: some View {
        GeometryReader { geo in
            let scene = AsciiScene.make(size: geo.size, night: Self.night)
            ZStack {
                scene.bg
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || Self.frozen != nil)) { tl in
                    let t = Self.frozen ?? (reduceMotion ? 3 : tl.date.timeIntervalSince(start))
                    Canvas { ctx, _ in scene.draw(in: ctx, t: t) }
                        .id(ObjectIdentifier(scene))           // redraw when the size (and so the scene) changes
                }
                title(scene)
                    .opacity(showText ? 1 : 0)
                    .scaleEffect(showText ? 1 : 0.96)
                    .position(scene.titleCenter)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            // Outside the GeometryReader, so it keeps clear of the status bar.
            let night = Self.night
            NowPlaying(step: steps[step], index: step, ink: night ? AsciiScene.ink(night) : AsciiScene.bg(night),
                       plate: night ? Color.white.opacity(0.08) : AsciiScene.ink(night).opacity(0.88), accent: style.top)
                .opacity(showText ? 1 : 0)
                .padding(.top, 8)
                .padding(.trailing, 14)
        }
        .task { await run() }
    }

    private func title(_ scene: AsciiScene) -> some View {
        (Text("Viggo").foregroundStyle(scene.night ? .white : scene.ink) + Text("+").foregroundStyle(style.top))
            .font(.system(size: 34, weight: .heavy, design: .monospaced))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(scene.night ? Color.clear : scene.bg)        // a clearing in the clouds by day
    }

    private func run() async {
        start = Date()
        if reduceMotion || (Self.frozen ?? 0) > 0.9 {
            showText = true
        } else {
            try? await Task.sleep(for: .milliseconds(750))
            Haptic.soft()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showText = true }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1100))
            guard step < steps.count - 1 else { break }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 }
        }
    }
}

/// The "now playing" label in the corner, like on the stream.
private struct NowPlaying: View {
    let step: String
    let index: Int
    let ink: Color
    let plate: Color
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("♫").foregroundStyle(accent)
            ZStack(alignment: .leading) {
                Text("\(step)  Viggo+ FM \(index + 1)/4")
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
            .frame(height: 14)
            .clipped()
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(ink.opacity(0.85))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(plate, in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - The scene

/// The landscape as a grid of characters. Everything that doesn't move is worked out once;
/// each frame only adds what moves (wind in the grass, drifting clouds, hatching, stars) and
/// draws the whole screen as four blocks of text, one per ink strength.
final class AsciiScene {
    let size: CGSize
    let night: Bool
    let bg: Color
    let ink: Color
    let cw: CGFloat
    let ch: CGFloat
    let cols: Int, rows: Int
    let x0: CGFloat

    static let fontSize: CGFloat = 9
    static let font = Font.system(size: fontSize, weight: .bold, design: .monospaced)

    /// Static cells: the character and ink level (0 to 3), or level -1 for empty.
    private var base: [Character]
    private var baseLevel: [Int8]
    /// What kind of moving thing a cell can hold: 0 nothing, 1 and 5 hatching, 2 star, 3 cloud sky, 4 grass.
    private var kind: [UInt8]
    private var appear: [Float]
    /// Day: a cloud field three screens wide that scrolls past, and the grass per column.
    private var cloudField: [Int8] = []
    private var cloudCols = 0
    private var grassTop: [Int] = []
    private var grassSeed: [Double] = []
    private var atlas: [[CGImage]] = []
    private var glyphIndex: [Character: Int] = [:]
    private var buffer: CGContext?
    private let scale: CGFloat = 2          // bitmap pixels per point: sharp enough and half the work of 3x

    private static var cache: AsciiScene?
    static func bg(_ night: Bool) -> Color { night ? IconStyle.hex(0x121212) : IconStyle.hex(0xEAE7DC) }
    static func ink(_ night: Bool) -> Color { night ? IconStyle.hex(0xD8D8D2) : IconStyle.hex(0x1A1A1A) }

    static func make(size: CGSize, night: Bool) -> AsciiScene {
        if let c = cache, c.night == night, c.size == size { return c }
        let s = AsciiScene(size: size, night: night)
        cache = s
        return s
    }

    private init(size: CGSize, night: Bool) {
        self.size = size
        self.night = night
        bg = Self.bg(night)
        ink = Self.ink(night)
        let ui = UIFont.monospacedSystemFont(ofSize: Self.fontSize, weight: .bold)
        cw = ("M" as NSString).size(withAttributes: [.font: ui]).width
        ch = ui.lineHeight
        let size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        cols = max(1, Int(size.width / cw) + 1)
        rows = max(1, Int(size.height / ch) + 1)
        x0 = (size.width - CGFloat(cols) * cw) / 2
        let n = cols * rows
        base = Array(repeating: " ", count: n)
        baseLevel = Array(repeating: -1, count: n)
        kind = Array(repeating: 0, count: n)
        appear = Array(repeating: 0, count: n)
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let y = (Double(r) + 0.5) * Double(ch)
                // Decode in: each cell appears at its own moment, bottom first.
                appear[i] = Float(0.1 + hash(c, r, 1) * 0.45 + (1 - y / Double(size.height)) * 0.25)
            }
        }
        if night { buildNight() } else { buildDay() }
        buildAtlas()
    }

    /// Where the title goes: in the dark middle of the ring at night, in the sky by day.
    var titleCenter: CGPoint { CGPoint(x: size.width / 2, y: size.height * (night ? 0.38 : 0.3)) }

    private var levels: [Color] { [ink.opacity(0.2), ink.opacity(0.42), ink.opacity(0.68), ink] }

    private static let scramble: [Character] = Array("!/\\<>[]{}?*=+#%&$")
    private static let rock: [Character] = Array(".,:;-=+*")
    private static let dense: [Character] = Array(":=+*#%@")
    private static let cloud: [Character] = Array(".:-=+*#")
    private static let blade: [Character] = Array("'|!l")

    // MARK: drawing

    func draw(in ctx: GraphicsContext, t: Double) {
        let tick = Int(t * 6)
        let shift = Int(t * 3)
        let cloudShift = Int(t * 1.5)
        let wind = (0..<cols).map { c -> Double in
            let u = Double(c) / Double(cols)
            return sin(t * 1.1 + u * 5) * 0.5 + sin(t * 2.3 + u * 13) * 0.25
        }
        guard let buf = buffer else { return }
        buf.clear(CGRect(x: 0, y: 0, width: buf.width, height: buf.height))
        let gw = cw * scale, gh = ch * scale, top = CGFloat(buf.height)

        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                var char: Character = " "
                var level = -1
                if Double(appear[i]) <= t {
                    (char, level) = (base[i], Int(baseLevel[i]))
                    switch kind[i] {
                    case 1, 5:                                       // hatching that slides along the ring
                        if (c + r * 2 + shift) % 5 == 0 { char = "/"; level = kind[i] == 5 ? 0 : 1 }
                    case 2:                                          // a twinkling star
                        let on = sin(t * (1.5 + hash(c, r, 5) * 4) + Double(c)) > 0
                        char = on ? "+" : "."; level = on ? 2 : 1
                    case 3:                                          // drifting clouds
                        let cc = ((c - cloudShift) % cloudCols + cloudCols) % cloudCols
                        let v = Int(cloudField[r * cloudCols + cc])
                        if v >= 0 { char = Self.cloud[v]; level = v > 4 ? 3 : v > 2 ? 2 : 1 }
                    case 4:                                          // grass bending in the wind
                        let top = grassTop[c]
                        let up = Double(r - top) / Double(max(1, rows - top))
                        let bend = wind[c] * (1 - up) * 2.2
                        let src = min(cols - 1, max(0, Int((Double(c) - bend).rounded())))
                        let n = grassSeed[src]
                        if n < 0.25 + up * 0.8 {
                            char = up < 0.08 ? "'" : (bend > 0.6 ? "/" : bend < -0.6 ? "\\" : Self.blade[1 + Int(n * 2.99)])
                            level = up < 0.2 ? 2 : 3
                        }
                    default: break
                    }
                    if level >= 0 {
                        if t < Double(appear[i]) + 0.12 {
                            char = Self.scramble[Int(hash(c, r, tick) * Double(Self.scramble.count))]
                            level = min(3, level + 1)
                        } else if hash(c, r, tick + 7) < 0.02 {           // the slow ASCII shimmer
                            char = Self.scramble[Int(hash(r, c, tick) * Double(Self.scramble.count))]
                        }
                    }
                }
                if level >= 0, char != " ", let g = glyphIndex[char] {
                    buf.draw(atlas[g][level], in: CGRect(x: CGFloat(c) * gw, y: top - CGFloat(r + 1) * gh, width: gw, height: gh))
                }
            }
        }
        guard let img = buf.makeImage() else { return }
        ctx.draw(Image(decorative: img, scale: scale),
                 in: CGRect(x: x0, y: 0, width: CGFloat(cols) * cw, height: CGFloat(rows) * ch))
    }

    // MARK: glyphs

    /// Every character the scene uses, drawn once in each ink strength. Each frame is then put
    /// together as one bitmap from these, which is far cheaper than laying out text every frame.
    private func buildAtlas() {
        let chars = Array(Set(Self.scramble + Self.rock + Self.dense + Self.cloud + Self.blade + Array("/\\.'~-+|")))
        let ui = UIFont.monospacedSystemFont(ofSize: Self.fontSize, weight: .bold)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cw, height: ch), format: format)
        for (i, c) in chars.enumerated() {
            glyphIndex[c] = i
            atlas.append(levels.map { color in
                renderer.image { _ in
                    (String(c) as NSString).draw(at: .zero, withAttributes: [.font: ui, .foregroundColor: UIColor(color)])
                }.cgImage!
            })
        }
        buffer = CGContext(data: nil, width: Int(CGFloat(cols) * cw * scale), height: Int(CGFloat(rows) * ch * scale),
                           bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        buffer?.interpolationQuality = .none
    }

    // MARK: night: a ring over mountains and a forest

    private func buildNight() {
        let W = Double(size.width), H = Double(size.height)
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let x = Double(x0) + (Double(c) + 0.5) * Double(cw), y = (Double(r) + 0.5) * Double(ch)
                let u = x / W
                func set(_ g: Character, _ l: Int) { base[i] = g; baseLevel[i] = Int8(l) }

                // The forest in front: jagged spikes, dark.
                let forest = H * 0.8 - H * 0.07 * ridged(u * 9 + 3) - H * 0.03 * abs(sin(u * 70))
                if y > forest {
                    let n = fbm(u * 30, y / H * 40)
                    let depth = (y - forest) / (H - forest)
                    if n >= 0.35 + depth * 0.2 { set(Self.dense[min(Self.dense.count - 1, Int(n * 6))], depth < 0.15 ? 1 : 0) }
                    continue
                }
                // Two layers of mountains, lit from one side.
                var inMountain = false
                for (b, amp, freq, seed, lvl) in [(0.7, 0.12, 7.0, 11.0, 1), (0.64, 0.17, 4.5, 4.0, 2)] {
                    let ridge = H * b - H * amp * ridged(u * freq + seed)
                    guard y > ridge else { continue }
                    inMountain = true
                    let slope = ridged((u + 0.004) * freq + seed) - ridged((u - 0.004) * freq + seed)
                    let fromTop = (y - ridge) / (H * 0.2)
                    let n = fbm(u * 40 + seed, y / H * 50)
                    let light = (slope > 0 ? 0.8 : 0.3) * max(0, 1 - fromTop * 0.8) + n * 0.3 - 0.1
                    if light >= 0.12, hash(c, r, 4) <= 0.35 + light {
                        let g: Character = slope > 0 && fromTop < 0.25 && n > 0.5
                            ? "/" : Self.rock[min(Self.rock.count - 1, Int(light * Double(Self.rock.count)))]
                        set(g, slope > 0 && fromTop < 0.3 ? lvl : max(0, lvl - 1))
                    }
                    break
                }
                if inMountain { continue }
                // The ring: a dark middle, a dense inner band and an outer band of hatching.
                let cx = W / 2, cy = H * 0.38, R = W * 0.62
                let d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                if d < R * 0.5 { continue }
                if d < R {
                    let k = (d - R * 0.5) / (R * 0.5)
                    if k < 0.32 {
                        let n = fbm(Double(c) * 0.3, Double(r) * 0.3)
                        if n > 0.38 { set(Self.dense[Int(n * 3.99)], k < 0.08 ? 2 : 1) }
                    } else if k >= 0.42 {
                        kind[i] = k > 0.9 ? 5 : 1                // hatching, faint at the very edge
                        if hash(c, r, 3) < 0.08 { set(".", 0) }
                    }
                    continue
                }
                if hash(c, r, 5) < 0.012 { kind[i] = 2 }
            }
        }
    }

    // MARK: day: clouds, hills and grass in the wind

    private func buildDay() {
        let W = Double(size.width), H = Double(size.height)
        grassTop = (0..<cols).map { c in
            let u = (Double(x0) + (Double(c) + 0.5) * Double(cw)) / W
            return Int(H * (0.66 + 0.12 * fbm(u * 18, 2.5)) / Double(ch))
        }
        grassSeed = (0..<cols).map { hash($0, 0, 9) }
        cloudCols = cols * 3
        cloudField = Array(repeating: -1, count: cloudCols * rows)
        for r in 0..<rows {
            let v = (Double(r) + 0.5) * Double(ch) / H
            for cc in 0..<cloudCols {
                let u = Double(cc) / Double(cols)
                // Wrap the noise so the field tiles when it scrolls around.
                let a = fbm(u * 2.6, v * 6.5), b = fbm((u - 3) * 2.6, v * 6.5)
                let f = u / 3
                let n = (a * (1 - f) + b * f) * (1 - abs(v - 0.25) * 1.4)
                if n > 0.44 { cloudField[r * cloudCols + cc] = Int8(min(Self.cloud.count - 1, Int((n - 0.44) * 26))) }
            }
        }
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let x = Double(x0) + (Double(c) + 0.5) * Double(cw), y = (Double(r) + 0.5) * Double(ch)
                let u = x / W, v = y / H
                func set(_ g: Character, _ l: Int) { base[i] = g; baseLevel[i] = Int8(l) }

                if r > grassTop[c] {
                    let up = Double(r - grassTop[c]) / Double(max(1, rows - grassTop[c]))
                    if up > 0.55 { set(Self.dense[3 + Int(hash(c, r, 2) * 3.99)], 3) } else { kind[i] = 4 }
                    continue
                }
                let hill = H * 0.52 - H * 0.04 * ridged(u * 6 + 2) - H * 0.015 * sin(u * 31)
                if y > hill, y < H * 0.6 {
                    let n = fbm(u * 50, v * 60)
                    if n > 0.3 { set(Self.dense[min(6, 2 + Int(n * 5))], 3) } else { set(".", 1) }
                    continue
                }
                if y >= H * 0.6 {
                    let n = fbm(u * 8, v * 90)
                    if n > 0.62 { set(n > 0.75 ? "~" : "-", 1) }
                    continue
                }
                if v > 0.45, hash(c, r, 6) < (v - 0.45) * 2.5 { set(".", 0) }
                kind[i] = 3
            }
        }
    }

    // MARK: noise

    private func hash(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791)
        h ^= h >> 33; h &*= 0xff51_afd7_ed55_8ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }

    private func noise(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi, 0), b = hash(xi + 1, yi, 0), c = hash(xi, yi + 1, 0), d = hash(xi + 1, yi + 1, 0)
        return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy
    }

    private func fbm(_ x: Double, _ y: Double) -> Double {
        noise(x, y) * 0.57 + noise(x * 2.1, y * 2.1) * 0.29 + noise(x * 4.3, y * 4.3) * 0.14
    }

    /// Sharp peaks: 1 on a ridge, falling off to both sides.
    private func ridged(_ x: Double) -> Double {
        let n = noise(x, 0.5) * 0.65 + noise(x * 2.3, 1.5) * 0.35
        return 1 - abs(n * 2 - 1)
    }
}
