import SwiftUI
import UIKit

/// About a thousand dots swirl in from all over the screen and settle into the word "Viggo+",
/// in the app icon's colours. Then a shimmer runs through them while Viggo answers.
struct StardustIntro: View {
    private let style = IconStyle.current

    var body: some View {
        GeometryReader { geo in
            let field = DustField.make(size: geo.size)
            ZStack {
                IconStyle.hex(0x07080F)
                IntroClock { t in
                    Canvas { ctx, _ in field.draw(in: ctx, t: t, from: style.top, to: style.bottom) }
                        .id(ObjectIdentifier(field))
                }
                IntroClock(fps: 10) { t in
                    StepTicker(color: .white.opacity(0.7))
                        .opacity(min(1, max(0, (t - 1.2) / 0.4)))
                }
                .position(x: geo.size.width / 2, y: field.textBottom + 44)
            }
        }
        .ignoresSafeArea()
    }
}

/// Where every dot starts and ends. Worked out once per screen size.
final class DustField {
    struct Dot { let target: CGPoint; let start: CGPoint; let delay: Double; let size: CGFloat; let u: CGFloat; let plus: Bool; let spin: Double }
    let size: CGSize
    private(set) var dots: [Dot] = []
    private(set) var textBottom: CGFloat = 0
    private static var cache: DustField?

    static func make(size: CGSize) -> DustField {
        if let c = cache, c.size == size { return c }
        let f = DustField(size: size)
        cache = f
        return f
    }

    private init(size: CGSize) {
        self.size = size
        let w = max(size.width, 1), h = max(size.height, 1)
        // Draw the word small, then turn every lit spot into a dot.
        let font = UIFont.systemFont(ofSize: w * 0.2, weight: .black).withDesign(.rounded)
        let main = NSAttributedString(string: "Viggo", attributes: [.font: font])
        let plus = NSAttributedString(string: "+", attributes: [.font: font])
        let mw = main.size().width, tw = mw + plus.size().width, th = main.size().height
        let step: CGFloat = 3.2
        let gw = Int(tw / step) + 1, gh = Int(th / step) + 1
        var pixels = [UInt8](repeating: 0, count: gw * gh)
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: gw,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            UIGraphicsPushContext(ctx)
            ctx.translateBy(x: 0, y: CGFloat(gh)); ctx.scaleBy(x: 1 / step, y: -1 / step)
            let all = NSMutableAttributedString(attributedString: main); all.append(plus)
            all.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: all.length))
            all.draw(at: .zero)
            UIGraphicsPopContext()
        }
        let ox = (w - tw) / 2, oy = h * 0.4 - th / 2
        textBottom = oy + th
        for gy in 0..<gh {
            for gx in 0..<gw where pixels[gy * gw + gx] > 120 {
                let x = CGFloat(gx) * step, y = CGFloat(gy) * step
                let target = CGPoint(x: ox + x + (hash(gx, gy, 1) - 0.5) * 1.2, y: oy + y + (hash(gx, gy, 2) - 0.5) * 1.2)
                // Start somewhere on a wide ring around the middle, so they swirl in.
                let a = hash(gx, gy, 3) * .pi * 2, r = max(w, h) * (0.45 + hash(gx, gy, 4) * 0.5)
                let start = CGPoint(x: w / 2 + cos(a) * r, y: h * 0.4 + sin(a) * r)
                dots.append(Dot(target: target, start: start, delay: Double(hash(gx, gy, 5)) * 0.55 + Double(x / tw) * 0.25,
                                size: 1.7 + hash(gx, gy, 6) * 1.3, u: x / tw, plus: x > mw - step, spin: Double(hash(gx, gy, 7) - 0.5) * 2.4))
            }
        }
    }

    func draw(in ctx: GraphicsContext, t: Double, from a: Color, to b: Color) {
        let buckets = 6
        var paths = [Path](repeating: Path(), count: buckets + 1)
        let wave = t - 1.5
        for d in dots {
            let p = min(1, max(0, (t - d.delay) / 1.1))
            let e = 1 - pow(1 - p, 3)
            // Curve in along a spiral: the angle unwinds as it lands.
            let dx = d.start.x - d.target.x, dy = d.start.y - d.target.y
            let turn = (1 - e) * d.spin
            let k = 1 - e
            let x = d.target.x + (dx * cos(turn) - dy * sin(turn)) * k
            let y = d.target.y + (dx * sin(turn) + dy * cos(turn)) * k
            var s = d.size * (0.6 + 0.4 * e)
            if wave > 0 {                                         // a shimmer sweeping left to right, again and again
                let front = (wave.truncatingRemainder(dividingBy: 2.4) / 1.2) - 0.25
                let dist = abs(Double(d.u) - front)
                if dist < 0.08 { s *= 1 + CGFloat(1 - dist / 0.08) * 0.9 }
            }
            let bucket = d.plus ? buckets : min(buckets - 1, Int(d.u * CGFloat(buckets)))
            paths[bucket].addEllipse(in: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
        }
        let fade = min(1, t / 0.3)
        for k in 0..<buckets {
            ctx.fill(paths[k], with: .color(a.mix(with: b, by: Double(k) / Double(buckets - 1)).mix(with: .white, by: 0.4).opacity(fade)))
        }
        ctx.fill(paths[buckets], with: .color(.white.opacity(fade)))
    }

    private func hash(_ a: Int, _ b: Int, _ c: Int) -> CGFloat {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791)
        h ^= h >> 33; h &*= 0xff51_afd7_ed55_8ccd; h ^= h >> 33
        return CGFloat(h % 10_000) / 10_000
    }
}

private extension UIFont {
    func withDesign(_ d: UIFontDescriptor.SystemDesign) -> UIFont {
        fontDescriptor.withDesign(d).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
