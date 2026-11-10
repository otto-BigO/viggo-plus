import SwiftUI

/// The week's lessons drop into a schedule one by one with a little bounce, day by day, and
/// then a red "now" line slides in across today.
struct ScheduleIntro: View {
    private let style = IconStyle.current
    @State private var shown = LaunchScreen.frozen != nil

    private static let days = ["Man", "Tir", "Ons", "Tor", "Fre"]

    /// A made-up but believable week: (start hour from 8, length in hours, colour) per lesson.
    private struct Block { let day: Int; let start: Double; let length: Double; let color: Int; let order: Int }
    private static let blocks: [Block] = {
        let week: [[(Double, Double, Int)]] = [
            [(0, 1.5, 0), (1.75, 1.5, 1), (4, 1, 2), (5.25, 1.5, 3)],
            [(0.5, 1, 4), (1.75, 2, 0), (4.5, 1.5, 5)],
            [(0, 1.5, 2), (1.75, 1, 3), (3, 1, 1), (4.5, 2, 6)],
            [(0, 2, 5), (2.25, 1.5, 4), (4.5, 1, 0)],
            [(0, 1.5, 1), (1.75, 1.5, 6), (3.5, 1, 2)],
        ]
        var out: [Block] = []
        for (d, lessons) in week.enumerated() {
            for (k, l) in lessons.enumerated() { out.append(Block(day: d, start: l.0, length: l.1, color: l.2, order: k)) }
        }
        return out
    }()

    private var palette: [Color] {
        [style.top, .orange, .teal, .pink, .indigo, .green, style.bottom]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(.systemBackground)
                IntroClock { t in
                    Canvas { ctx, size in draw(ctx, size: size, t: t) }
                }
                VStack(spacing: 8) {
                    (Text("Viggo") + Text("+").foregroundStyle(style.top))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    StepTicker()
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 10)
                .position(x: w / 2, y: h * 0.17)
            }
        }
        .ignoresSafeArea()
        .task {
            guard !shown else { return }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = true }
        }
    }

    private func grid(_ size: CGSize) -> CGRect {
        let w = size.width - 40
        return CGRect(x: 20, y: size.height * 0.28, width: w, height: min(size.height * 0.56, w * 1.45))
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let g = grid(size)
        let label: CGFloat = 26, gutter: CGFloat = 30
        let colW = (g.width - gutter) / 5
        let hours = 7.0
        let hourH = (g.height - label) / hours
        let fade = min(1, t / 0.3)

        // Day names and hour marks.
        for (d, name) in Self.days.enumerated() {
            let x = g.minX + gutter + colW * (CGFloat(d) + 0.5)
            ctx.draw(Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary.opacity(fade)),
                     at: CGPoint(x: x, y: g.minY + label / 2))
        }
        var lines = Path()
        for k in 0...Int(hours) {
            let y = g.minY + label + hourH * CGFloat(k)
            lines.addRect(CGRect(x: g.minX + gutter, y: y, width: g.width - gutter, height: 0.5))
            if k < Int(hours) {
                ctx.draw(Text("\(8 + k)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary.opacity(fade)),
                         at: CGPoint(x: g.minX + gutter / 2 - 2, y: y + 7))
            }
        }
        ctx.fill(lines, with: .color(.secondary.opacity(0.18 * fade)))

        // The lessons drop in from above with a springy landing.
        for b in Self.blocks {
            let delay = 0.25 + Double(b.day) * 0.13 + Double(b.order) * 0.07
            let x = max(0, t - delay)
            guard t > delay else { continue }
            let landed = 1 - exp(-7 * x) * cos(11 * x)
            let rest = CGRect(x: g.minX + gutter + colW * CGFloat(b.day) + 3,
                              y: g.minY + label + hourH * CGFloat(b.start) + 2,
                              width: colW - 6, height: hourH * CGFloat(b.length) - 4)
            let r = rest.offsetBy(dx: 0, dy: -(1 - landed) * size.height * 0.35)
            let color = palette[b.color % palette.count]
            let a = min(1, x / 0.15)
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous).path(in: r)
            ctx.fill(shape, with: .color(color.opacity(0.22 * a)))
            ctx.fill(RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: r.minX, y: r.minY + 3, width: 3, height: r.height - 6)),
                     with: .color(color.opacity(a)))
            // Two short bars where the lesson's name and room would be.
            let bw = (r.width - 14)
            ctx.fill(Capsule().path(in: CGRect(x: r.minX + 8, y: r.minY + 7, width: bw * 0.8, height: 5)), with: .color(color.opacity(0.8 * a)))
            if r.height > 34 {
                ctx.fill(Capsule().path(in: CGRect(x: r.minX + 8, y: r.minY + 16, width: bw * 0.5, height: 4)), with: .color(color.opacity(0.4 * a)))
            }
        }

        // The "now" line across today, with a pulsing dot.
        let nowT = t - 1.6
        guard nowT > 0 else { return }
        let today = min(4, max(0, Calendar.current.component(.weekday, from: Date()) - 2))
        let hour = min(hours - 0.3, max(0.3, LaunchScreen.hour - 8))
        let y = g.minY + label + hourH * CGFloat(hour)
        let reach = 1 - pow(1 - min(1, nowT / 0.5), 3)
        let x0 = g.minX + gutter
        ctx.fill(Path(CGRect(x: x0, y: y - 0.75, width: (g.width - gutter) * reach, height: 1.5)), with: .color(.red.opacity(0.35)))
        let tx = x0 + colW * CGFloat(today)
        ctx.fill(Path(CGRect(x: tx, y: y - 1, width: colW * reach, height: 2)), with: .color(.red))
        let pulse = 4 + 2 * sin(nowT * 4)
        ctx.fill(Circle().path(in: CGRect(x: tx - pulse, y: y - pulse, width: pulse * 2, height: pulse * 2)), with: .color(.red))
    }
}
