import SwiftUI

/// Ugle, the Viggo+ owl, on its own: the launch screen sprite, blinking and nodding.
struct OwlView: View {
    var size: CGFloat = 96
    var accent: Color = IconStyle.current.top
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let k = sz.width / 16
                let blink = t.truncatingRemainder(dividingBy: 3.4) > 3.25
                let nod = sin(t * 84 / 60 * .pi * 2) > 0.6 ? k : 0
                let colors: [Character: Color] = [
                    "B": IconStyle.hex(0x8B6A4F), "L": IconStyle.hex(0xE9D6B5), "E": .white,
                    "P": IconStyle.hex(0x1B1B26), "K": IconStyle.hex(0xF2A33A), "F": IconStyle.hex(0xF2A33A),
                    "H": accent, "D": IconStyle.hex(0x2A2A38), "X": accent,
                ]
                for (r, line) in (blink ? PixelScene.owlBlink : PixelScene.owlOpen).enumerated() {
                    for (c, ch) in line.enumerated() {
                        guard let col = colors[ch] else { continue }
                        let dy = r < 8 ? nod : 0
                        ctx.fill(Path(CGRect(x: CGFloat(c) * k, y: CGFloat(r) * k + dy, width: k, height: k)), with: .color(col))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A short introduction, shown once after the first login and again from Indstillinger.
struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = Int(ProcessInfo.processInfo.environment["VIGGO_GUIDE_PAGE"] ?? "") ?? 0

    struct Page { let icon: String; let title: String; let text: String; var steps: [String] = [] }

    private let pages: [Page] = [
        Page(icon: "hand.wave.fill", title: "Hej, jeg er Ugle",
             text: "Jeg passer på dit skema. I dag viser timen der er i gang, Uge hele ugen, og under Beskeder og Venner har du resten af Viggo."),
        Page(icon: "square.grid.2x2.fill", title: "Widgets",
             text: "Se næste time og lektierne uden at åbne appen.",
             steps: ["Hold fingeren på hjemmeskærmen", "Tryk Rediger og så Tilføj widget", "Vælg Viggo+"]),
        Page(icon: "clock.badge.fill", title: "Skoledagen på låseskærmen",
             text: "Få timen og nedtællingen på låseskærmen hver morgen, uden at åbne Viggo+.",
             steps: ["Åbn Genveje og gå til Automatisering", "Vælg Tidspunkt, fx 7.45 på hverdage, og Kør med det samme", "Tilføj \"Vis skoledagen\" fra Viggo+"]),
        Page(icon: "switch.2", title: "Knap i Kontrolcenter",
             text: "Start skoledagen med ét tryk, når du vil.",
             steps: ["Træk ned fra øverste højre hjørne", "Tryk + og Tilføj en kontrol", "Vælg \"Vis skoledagen\" under Viggo+"]),
        Page(icon: "arrow.triangle.2.circlepath", title: "Mac'en holder mig i live",
             text: "Viggo+ på din Mac fornyer appen af sig selv inden de 7 dage løber ud, når iPhonen er på samme wifi. Du skal ikke gøre noget."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in pageView(pages[i], first: i == 0).tag(i) }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                if page > 0 { Button("Tilbage") { withAnimation(.viggo) { page -= 1 } } }
                Spacer()
                Button(page == pages.count - 1 ? "Kom i gang" : "Næste") {
                    Haptic.tap()
                    if page == pages.count - 1 { dismiss() } else { withAnimation(.viggo) { page += 1 } }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        }
        .interactiveDismissDisabled(false)
    }

    private func pageView(_ p: Page, first: Bool) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                if first {
                    OwlView(size: 128)
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: p.icon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 84)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(IconStyle.current.top.gradient))
                        OwlView(size: 44).offset(x: 22, y: 10)
                    }
                    .padding(.trailing, 22)
                }
                Text(p.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                Text(p.text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !p.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(p.steps.indices, id: \.self) { i in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(i + 1)").font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white).frame(width: 24, height: 24)
                                    .background(Circle().fill(IconStyle.current.top))
                                Text(p.steps[i]).font(.subheadline)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
                }
                if p.icon == "clock.badge.fill", let url = URL(string: "shortcuts://") {
                    Link(destination: url) { Label("Åbn Genveje", systemImage: "square.2.layers.3d") }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 28).padding(.top, 48).padding(.bottom, 56)
        }
    }
}

extension GuideSheet {
    static let seenKey = "guideSeen1"
    /// Test hook: VIGGO_SHOW_GUIDE=1 shows it at launch even when it was seen, VIGGO_GUIDE_PAGE=2 opens that page.
    static var forced: Bool { ProcessInfo.processInfo.environment["VIGGO_SHOW_GUIDE"] != nil }
}
