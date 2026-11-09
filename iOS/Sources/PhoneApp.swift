import SwiftUI

@main
struct ViggoPlusPhoneApp: App {
    @StateObject private var state = AppState.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onChange(of: phase) { _, p in
                    // Back from the background: fetch again so "I dag" is fresh.
                    if p == .active, !state.needsLogin, !state.syncing { Task { await state.sync() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.needsLogin && state.events.isEmpty {
                LoginScreen()
            } else {
                TabView {
                    Tab("I dag", systemImage: "sun.max.fill") { TodayScreen() }
                    Tab("Uge", systemImage: "calendar") { WeekScreen() }
                    Tab("Venner", systemImage: "person.2.fill") { FriendsScreen() }
                    Tab("Indstillinger", systemImage: "gearshape.fill") { SettingsScreen() }
                }
            }
        }
        .modifier(LoginCardOverlay())
        .animation(.viggo, value: state.needsLogin)
        .sheet(item: $state.shownLesson) { e in
            NavigationStack {
                LessonDetailView(e: e)
                        .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Færdig") { state.shownLesson = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// The "I dag" screen: the same day view as the Mac panel, in a scroll view.
struct TodayScreen: View {
    @EnvironmentObject var state: AppState

    private var greeting: String {
        state.profile.map { "Hej \($0.name.components(separatedBy: " ").first ?? $0.name)" } ?? "I dag"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if state.needsLogin {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Text("Du er logget ud af Viggo").font(Sz.f(13))
                            Spacer()
                            Button("Log ind") { state.loginWithBrowser() }.buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                    if !state.status.isEmpty {
                        Text(state.status).font(Sz.f(12)).foregroundStyle(.orange)
                    }
                    DayPanel(name: nil, events: state.events, homework: state.homework, now: state.tick)
                    if let s = state.lastSync {
                        Text("Synket \(DateUtil.hm(s))").font(.footnote).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await state.sync() }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { state.openViggo() } label: { Label("Åbn Viggo", systemImage: "safari") }
                        Button(role: .destructive) { state.logout() } label: { Label("Log ud", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: {
                        if let p = state.profile { Avatar(url: p.image, size: 30, name: p.name) }
                        else { Image(systemName: "person.crop.circle") }
                    }
                }
            }
        }
    }
}

/// First launch: log in with SkoleIT (Viggo+ logs in by itself after that) or through Viggo's own page.
struct LoginScreen: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "graduationcap.fill").font(.system(size: 44)).foregroundStyle(.tint)
                        Text("Viggo+").font(.largeTitle.bold())
                        Text("Dit skema, lektier og hvad der sker nu.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }
                Section {
                    SkoleITFields(button: "Log ind") { u, p in
                        Task { await state.saveAutoLogin(username: u, password: p) }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("SkoleIT")
                } footer: {
                    Text("Viggo+ gemmer login på telefonen og logger selv ind igen, når Viggo smider dig ud.")
                }
                Section {
                    Button("Log ind via Viggo i stedet") { state.loginWithBrowser() }
                }
                if !state.loginMessage.isEmpty {
                    Text(state.loginMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
