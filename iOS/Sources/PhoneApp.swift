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
                    if p == .active, state.importTransfer() {
                        Task { await state.sync(); await state.syncFriends() }
                    } else if p == .active, !state.needsLogin, !state.syncing { Task { await state.sync() } }
                    if p == .active { Task { await PhoneUpdate.shared.check() } }
                    if p == .background { state.scheduleRefresh() }
                }
                .onOpenURL { state.handle($0) }
                .task {
                    // Test hooks: render the widgets and print Siri's answers from the cached schedule.
                    let env = ProcessInfo.processInfo.environment
                    if let dir = env["VIGGO_RENDER_ICONS"] { IconRenderer.run(to: dir) }
                    await PhoneUpdate.shared.check(force: env["VIGGO_PRETEND_VERSION"] != nil)
                    if env["VIGGO_WIDGET_SHOTS"] != nil || env["VIGGO_SAY"] != nil {
                        try? await Task.sleep(for: .seconds(2))
                        state.pushWidget()
                    }
                }
        }
        .backgroundTask(.appRefresh(AppState.refreshTask)) {
            await AppState.shared.backgroundRefresh()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var tab = ProcessInfo.processInfo.environment["VIGGO_TAB"].flatMap(Int.init) ?? 0
    @State private var splash = true
    @State private var guide = false
    @State private var intro = Intro.pick()

    var body: some View {
        ZStack {
            main
                .scaleEffect(splash ? 0.94 : 1)
                .opacity(splash ? 0 : 1)
            if splash {
                LaunchScreen(intro: intro)
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .scale(scale: 1.12).combined(with: .opacity)))
                    .zIndex(1)
            }
        }
        .modifier(LoginCardOverlay())
        .overlay(alignment: .bottomTrailing) {
            // Logins the app runs by itself show here, small and in the corner above the tabs,
            // instead of the sign-in card.
            QuietLoginBadges().padding(.trailing, 14).padding(.bottom, 66)
        }
        .animation(.viggo, value: state.needsLogin)
        .task { await leaveSplash() }
        .task {
            guard ProcessInfo.processInfo.environment["VIGGO_QUIET_DEMO"] != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            await state.quietDemo()
        }
        .sheet(isPresented: $guide, onDismiss: { UserDefaults.standard.set(true, forKey: GuideSheet.seenKey) }) { GuideSheet() }
        .onChange(of: state.needsLogin) { if !splash { offerGuide() } }
        .sheet(isPresented: Binding(get: { state.showSearch && !splash }, set: { state.showSearch = $0 })) { SearchScreen() }
        .sheet(item: $state.shownLesson) { e in
            NavigationStack {
                LessonDetailView(e: e)
                        .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Færdig") { state.shownLesson = nil } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear { Haptic.soft() }
        }
    }

    /// Keep the launch screen up until the first sync is done (at least long enough for the
    /// icon animation, at most 15 s), then zoom through it into the app.
    private func leaveSplash() async {
        if LaunchScreen.hold { return }
        let start = Date()
        while state.lastSync == nil, !state.needsLogin, state.syncAttempts == 0,
              Date().timeIntervalSince(start) < 15 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let left = 1.9 - Date().timeIntervalSince(start)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        Haptic.soft()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { splash = false }
        try? await Task.sleep(for: .milliseconds(700))
        offerGuide()
    }

    /// The introduction, once, after the first login.
    private func offerGuide() {
        guard !state.needsLogin, GuideSheet.forced || !UserDefaults.standard.bool(forKey: GuideSheet.seenKey) else { return }
        guide = true
    }

    @ViewBuilder private var main: some View {
        Group {
            if state.needsLogin && state.events.isEmpty {
                LoginScreen()
            } else {
                // Tapping the tab you are already on sends .viggoTabAgain (Uge jumps back to today).
                TabView(selection: Binding(get: { tab }, set: { new in
                    if new == tab { NotificationCenter.default.post(name: .viggoTabAgain, object: new) }
                    tab = new
                })) {
                    Tab("I dag", systemImage: "sun.max.fill", value: 0) { TodayScreen() }
                    Tab("Uge", systemImage: "calendar", value: 1) { WeekScreen() }
                    Tab("Beskeder", systemImage: "bubble.left.and.bubble.right.fill", value: 2) { MessagesScreen() }
                        .badge(state.unreadCount)
                    Tab("Venner", systemImage: "person.2.fill", value: 3) { FriendsScreen() }
                    Tab("Indstillinger", systemImage: "gearshape.fill", value: 4) { SettingsScreen() }
                }
                .onChange(of: tab) { Haptic.select() }
                .onChange(of: state.openThread) { if state.openThread != nil { tab = 2 } }
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
