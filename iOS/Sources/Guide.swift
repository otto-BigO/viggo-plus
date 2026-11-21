import SwiftUI
import UserNotifications

/// A short introduction, shown once after the first login and again from Indstillinger.
struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = Int(ProcessInfo.processInfo.environment["VIGGO_GUIDE_PAGE"] ?? "") ?? 0
    @ObservedObject private var p = Prefs.shared
    /// The notification step's choices. A first-time user starts from the useful, quiet ones, so
    /// Fortsæt is always one tap; the chatty morning and evening brief starts off.
    @State private var changes = true
    @State private var messages = true
    @State private var homework = true
    @State private var briefs = false
    @State private var status: UNAuthorizationStatus?
    private let notifyPage = 1

    struct Page { let icon: String; let title: String; let text: String; var steps: [String] = [] }

    private let pages: [Page] = [
        Page(icon: "hand.wave.fill", title: "Velkommen til Viggo+",
             text: "I dag viser timen der er i gang, Uge hele ugen, og under Beskeder og Venner har du resten af Viggo."),
        Page(icon: "bell.badge.fill", title: "Få besked, når det betyder noget",
             text: "Vælg hvad du vil have besked om. Det kan altid ændres under Indstillinger."),
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
                if page > 0 { Button("Tilbage") { withAnimation(.viggo) { page -= 1 } }.foregroundStyle(Fomo.text2) }
                Spacer()
                if page == notifyPage, status == .notDetermined {
                    Button("Spring over") { Haptic.tap(); withAnimation(.viggo) { page += 1 } }
                        .foregroundStyle(Fomo.text2).padding(.trailing, 8)
                }
                Button(page == pages.count - 1 ? "Kom i gang" : "Fortsæt") {
                    Haptic.tap()
                    if page == notifyPage { Task { await applyNotify() } }
                    if page == pages.count - 1 { dismiss() } else { withAnimation(.viggo) { page += 1 } }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
            }
            .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        }
        .background(Fomo.bg)
        .tint(Fomo.accent)
        .interactiveDismissDisabled(false)
        .task {
            status = await NotifyAsk.status()
            // Someone who has already chosen sees their own choices, not the suggestions.
            if p.askedNotifications || status != .notDetermined {
                changes = p.notifyChanges; messages = p.notifyMessages
                homework = p.homeworkReminder; briefs = p.briefs
            }
        }
    }

    /// Saves the choices and, the first time and only if something is on, asks iOS for permission.
    private func applyNotify() async {
        p.notifyChanges = changes; p.notifyMessages = messages
        p.homeworkReminder = homework; p.briefs = briefs
        if status == .notDetermined, changes || messages || homework || briefs {
            await NotifyAsk.request()
            status = await NotifyAsk.status()
        }
        AppState.shared.scheduleAhead()
    }

    private var notifyChoices: some View {
        VStack(spacing: 0) {
            choice("Flyttede eller aflyste timer", "calendar.badge.exclamationmark", $changes)
            Divider().padding(.leading, 44)
            choice("Nye beskeder", "envelope.fill", $messages)
            Divider().padding(.leading, 44)
            choice("Lektier om aftenen", "book.fill", $homework)
            Divider().padding(.leading, 44)
            choice("Morgen- og aftenbrief", "sun.horizon.fill", $briefs)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .surface(16)
    }

    private func choice(_ title: String, _ icon: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            Label {
                Text(title).font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: icon).foregroundStyle(Fomo.text2)
            }
        }
        .tint(Fomo.green)
        .padding(.vertical, 8)
        .sensoryFeedback(trigger: on.wrappedValue) { _, _ in Prefs.shared.haptics ? .selection : nil }
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
                Text(p.text).font(.body).foregroundStyle(Fomo.text2).multilineTextAlignment(.center)
                if p.icon == "bell.badge.fill" {
                    notifyChoices
                    if status == .denied {
                        Text("Notifikationer er slået fra for Viggo+ i iPhonens Indstillinger.")
                            .font(.footnote).foregroundStyle(Fomo.text2).multilineTextAlignment(.center)
                    }
                }
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
                    .surface(16)
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
