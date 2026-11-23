import SwiftUI
import UserNotifications

/// Indstillinger: Udseende og haptik. The small taps and the things that draw themselves in.
struct AppearanceTab: View {
    @ObservedObject var p = Prefs.shared
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Form {
            Section {
                Toggle("Haptik", isOn: $p.haptics)
                    .onChange(of: p.haptics) { if p.haptics { Haptic.tap() } }
            } footer: {
                #if os(macOS)
                Text("Et lille tryk i en Force Touch-trackpad, når du krydser en lektie af. Kun når du selv klikker.")
                #else
                Text("Små tryk når du krydser en lektie af, fortryder noget eller logger ind.")
                #endif
            }
            .fomoRows()
            Section {
                Toggle("Animationer når noget åbner", isOn: $p.drawIn)
                    .disabled(reduce)
            } footer: {
                Text(reduce
                     ? "Slået fra, fordi Reducer bevægelse er slået til i systemets indstillinger."
                     : "Uge-overblikket og nedtællingen tegner sig selv ind, kort og stille, når du åbner dem.")
            }
            .fomoRows()
        }
        .fomoList()
        .formStyle(.grouped)
    }
}

#if os(iOS)
/// Asks for notifications at a moment it makes sense, with our own explanation first, and only
/// then shows the system's question. Never at launch, never pre-ticked spam.
@MainActor
enum NotifyAsk {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows the system's question. True when notifications are allowed afterwards.
    @discardableResult
    static func request() async -> Bool {
        Prefs.shared.askedNotifications = true
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { AppState.shared.scheduleAhead() }
        return ok
    }
}

/// Our own sheet before the system's question: what you get, and a clear way to say no.
struct NotifyAskSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onDone: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fomo.accent))
                .padding(.top, 28)
            Text("Få besked, når det betyder noget").font(.title3.weight(.bold)).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                example("calendar.badge.exclamationmark", "Fysik er aflyst i morgen", "Når en time bliver flyttet eller aflyst")
                example("envelope.fill", "Ny besked fra din lærer", "Når der kommer en ny besked")
                example("book.fill", "2 lektier til i morgen", "Om aftenen, hvis du har lektier")
            }
            .padding(14)
            .surface(16)
            Text("Du vælger selv hvad der kommer under Indstillinger, Notifikationer.")
                .font(.footnote).foregroundStyle(Fomo.text2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button {
                Task {
                    let ok = await NotifyAsk.request()
                    onDone(ok)
                    dismiss()
                }
            } label: {
                Text("Fortsæt").font(.headline).frame(maxWidth: .infinity).frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            Button("Ikke nu") {
                Prefs.shared.askedNotifications = true
                onDone(false)
                dismiss()
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(Fomo.text2)
        }
        .padding(.horizontal, 22).padding(.bottom, 16)
        .tint(Fomo.accent)
        .presentationDetents([.large])
        .presentationBackground(Fomo.bg)
    }

    private func example(_ icon: String, _ title: String, _ when: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Fomo.text2)
                .frame(width: 34, height: 34).background(Circle().fill(Fomo.surface2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(when).font(.footnote).foregroundStyle(Fomo.text2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The top of Notifikationer: says if notifications are off, and offers the one step that fixes it.
struct NotifyStatusRow: View {
    @State private var status: UNAuthorizationStatus?
    @State private var asking = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            switch status {
            case .notDetermined?:
                Section {
                    Button { asking = true } label: {
                        Label("Slå notifikationer til", systemImage: "bell.badge.fill").font(.body.weight(.semibold))
                    }
                } footer: { Text("Viggo+ har ikke fået lov til at sende notifikationer endnu.") }
                .fomoRows()
            case .denied?:
                Section {
                    Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                        Label("Åbn Indstillinger", systemImage: "gear").font(.body.weight(.semibold))
                    }
                } footer: { Text("Notifikationer er slået fra for Viggo+ i iPhonens Indstillinger. Slå dem til der, så virker valgene herunder.") }
                .fomoRows()
            default:
                EmptyView()
            }
        }
        .task(id: phase) { status = await NotifyAsk.status() }
        .sheet(isPresented: $asking) {
            NotifyAskSheet { _ in Task { status = await NotifyAsk.status() } }
        }
    }
}
#endif
