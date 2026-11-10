import SwiftUI

/// A short introduction, shown once after the first login and again from Indstillinger.
struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = Int(ProcessInfo.processInfo.environment["VIGGO_GUIDE_PAGE"] ?? "") ?? 0

    struct Page { let icon: String; let title: String; let text: String; var steps: [String] = [] }

    private let pages: [Page] = [
        Page(icon: "hand.wave.fill", title: "Velkommen til Viggo+",
             text: "I dag viser timen der er i gang, Uge hele ugen, og under Beskeder og Venner har du resten af Viggo."),
        Page(icon: "square.grid.2x2.fill", title: "Widgets",
             text: "Se næste time og lektierne uden at åbne appen.",
             steps: ["Hold fingeren på hjemmeskærmen", "Tryk Rediger og så Tilføj widget", "Vælg Viggo+"]),
        Page(icon: "clock.badge.fill", title: "Skoledagen på låseskærmen",
             text: "Få timen og nedtællingen på låseskærmen hver morgen, uden at åbne Viggo+.",
             steps: ["Åbn Genveje og gå til Automatisering", "Vælg Tidspunkt, fx 7.45 på hverdage, og Kør med det samme", "Tilføj \"Vis skoledagen\" fra Viggo+"]),
        Page(icon: "switch.2", title: "Knap i Kontrolcenter",
             text: "Start skoledagen med ét tryk, når du vil.",
             steps: ["Træk ned fra øverste højre hjørne", "Tryk + og Tilføj en kontrol", "Vælg \"Vis skoledagen\" under Viggo+"]),
        Page(icon: "arrow.triangle.2.circlepath", title: "Mac'en holder appen i live",
             text: "Viggo+ på din Mac fornyer appen af sig selv inden de 7 dage løber ud, når iPhonen er på samme wifi. Du skal ikke gøre noget."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in pageView(pages[i]).tag(i) }
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

    private func pageView(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: p.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(IconStyle.current.top.gradient))
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
