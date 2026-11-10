import SwiftUI

/// Viggo+ boots like an old computer: green text types itself out line by line on a dark,
/// slightly flickering screen with scanlines, then a big block-letter banner and a cursor.
struct TerminalIntro: View {
    private let style = IconStyle.current
    private let ink = IconStyle.hex(0x7DFFA0)
    private let bg = IconStyle.hex(0x07100A)

    private var lines: [(text: String, status: String)] {
        let host = Config.baseURL.host ?? "viggo.dk"
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return [
            ("VIGGO+ \(v)  (iPhone)", ""),
            ("hukommelse ", "ok"),
            ("\(host) ", "ok"),
            ("henter skema ", "ok"),
            ("henter lektier ", "ok"),
            ("henter beskeder ", "ok"),
        ]
    }

    /// 5 x 5 block letters for the banner.
    private static let letters: [Character: [String]] = [
        "V": ["#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "I": ["###", ".#.", ".#.", ".#.", "###"],
        "G": [".####", "#....", "#..##", "#...#", ".###."],
        "O": [".###.", "#...#", "#...#", "#...#", ".###."],
        "+": [".....", "..#..", ".###.", "..#..", "....."],
    ]

    var body: some View {
        GeometryReader { geo in
            IntroClock { t in
                let fs = min(15, geo.size.width / 26)
                ZStack {
                    bg
                    VStack(alignment: .leading, spacing: fs * 0.45) {
                        ForEach(lines.indices, id: \.self) { i in line(i, t: t) }
                        banner(t: t, width: geo.size.width - 48)
                            .padding(.vertical, fs)
                        prompt(t: t)
                    }
                    .font(.system(size: fs, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink)
                    .shadow(color: ink.opacity(0.55), radius: 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, geo.size.height * 0.16)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(0.94 + 0.06 * sin(t * 53) * sin(t * 7.3))     // the tube flickers a little
                    scanlines
                }
                .opacity(min(1, t / 0.15))
            }
        }
        .ignoresSafeArea()
    }

    /// Each line starts typing 0.2 s after the one before and ends with a dotted "ok".
    private func line(_ i: Int, t: Double) -> some View {
        let (text, status) = lines[i]
        let begin = 0.15 + Double(i) * 0.2
        let typed = Int(max(0, (t - begin) * 90))
        let shown = String(text.prefix(typed))
        let done = typed >= text.count
        let dots = done && !status.isEmpty ? String(repeating: ".", count: max(1, min(Int((t - begin - Double(text.count) / 90) * 120), 26 - text.count))) : ""
        let ok = done && !status.isEmpty && t > begin + Double(text.count) / 90 + 0.12
        return (Text(i == 0 ? shown : "> " + shown) + Text(dots).foregroundStyle(ink.opacity(0.45))
                + Text(ok ? " " + status : "").foregroundStyle(.white))
            .lineLimit(1)
            .opacity(t >= begin ? 1 : 0)
    }

    private func banner(t: Double, width: CGFloat) -> some View {
        let begin = 0.15 + Double(lines.count) * 0.2 + 0.1
        let word = Array("VIGGO+")
        let cols = word.map { Self.letters[$0]![0].count }.reduce(0, +) + word.count - 1
        let fs = width / CGFloat(cols) / 0.62
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5, id: \.self) { r in
                // Rows wipe in from the top, quickly.
                let on = t > begin + Double(r) * 0.05
                let main = word.dropLast().map { String(Self.letters[$0]![r].map { $0 == "#" ? "█" : " " }) }.joined(separator: " ")
                let plus = String(Self.letters["+"]![r].map { $0 == "#" ? "█" : " " })
                (Text(main + " ") + Text(plus).foregroundStyle(style.top.mix(with: .white, by: 0.25)))
                    .opacity(on ? 1 : 0)
            }
        }
        .font(.system(size: fs, weight: .regular, design: .monospaced))
        .lineSpacing(0)
        .fixedSize()
    }

    private func prompt(t: Double) -> some View {
        let begin = 0.15 + Double(lines.count) * 0.2 + 0.45
        let step = min(LaunchScreen.steps.count - 1, max(0, Int((t - begin) / 1.1)))
        let last = step == LaunchScreen.steps.count - 1
        let cursor = Int(t * 2.2) % 2 == 0
        return (Text("> ") + Text(last ? "klar. " : LaunchScreen.steps[step].lowercased() + "... ").foregroundStyle(last ? .white : ink.opacity(0.6))
                + Text(cursor ? "█" : " "))
            .opacity(t > begin ? 1 : 0)
    }

    private var scanlines: some View {
        Canvas { ctx, size in
            var p = Path()
            for y in stride(from: 0, to: size.height, by: 3) { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)) }
            ctx.fill(p, with: .color(.black.opacity(0.22)))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.55)]),
                                           center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: size.width * 0.35, endRadius: size.height * 0.75))
        }
        .allowsHitTesting(false)
    }
}
