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
                    if p == .background { state.scheduleRefresh() }
                }
                .onOpenURL { state.handle($0) }
        }
        .backgroundTask(.appRefresh(AppState.refreshTask)) {
            await AppState.shared.backgroundRefresh()
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
