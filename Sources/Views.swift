import SwiftUI

@main
struct ViggoPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    // The menu bar item and panel are Viggo+'s own (PanelController), so the hotkey can open them.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Small pieces

extension Notification.Name {
    static let panelClosed = Notification.Name("ViggoPanelClosed")
    static let panelSearchTest = Notification.Name("ViggoPanelSearchTest")
    static let panelSearchPerson = Notification.Name("ViggoPanelSearchPerson")
}

// MARK: - Menubar panel

struct MenuView: View {
    static var width: CGFloat { 320 * (Prefs.shared.panelLarge ? 1.12 : 1) }
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject var updater = Updater.shared
    @Namespace private var ring
    /// The height of the day under the header, for sizing the scroll view around it.
    @State private var dayHeight: CGFloat = 0
    /// Everything in the card but the day: header, banners, buttons and padding.
    @State private var chrome: CGFloat = 0
    /// The day's height on screen: all of it, or what is left of the screen under the header.
    private var dayFrame: CGFloat {
        max(0, min(dayHeight, PanelController.shared.room - PanelController.pad - chrome))
    }
    /// Search in the panel: the magnifier turns the panel into a search, in the same look.
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// At least as tall as the day (so the panel keeps its size when it is tall enough), and
    /// room for a handful of results when the day is short.
    private var searchFrame: CGFloat {
        max(dayFrame, min(380, PanelController.shared.room - PanelController.pad - chrome))
    }
    private var middle: CGFloat { searching ? searchFrame : dayFrame }

    private func toggleSearch() {
        withAnimation(.viggo) { searching.toggle() }
        if searching { query = ""; DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true } }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold, design: Fomo.design)).foregroundStyle(.secondary)
            TextField("Søg i Viggo", text: $query)
                .textFieldStyle(.plain).font(Sz.f(14, .medium))
                .focused($searchFocused)
                .onSubmit { SearchBridge.shared.open(query: query) }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Ryd")
            }
            Button { SearchBridge.shared.open(query: query.isEmpty ? nil : query) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .semibold, design: Fomo.design))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Åbn i det store søgevindue (↩)")
            Button("Færdig", action: toggleSearch)
                .buttonStyle(.plain).font(Sz.f(12, .medium)).foregroundStyle(Fomo.accent)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .surface(10)
    }

    private var friendGroup: some View {
        FriendGroup(people: [.init(id: nil, url: state.profile?.image, name: state.profile?.name, label: "Mig")]
                        + state.friends.map { .init(id: $0.id, url: $0.image, name: $0.name, label: $0.firstName, expired: state.friendExpired.contains($0.id)) },
                    selected: state.selectedFriend) { id in withAnimation(.viggo) { state.selectedFriend = id } }
    }

    private var headerTitle: String {
        if let fid = state.selectedFriend, let f = state.friends.first(where: { $0.id == fid }) { return f.firstName }
        return state.profile.map { "Hej \($0.name.components(separatedBy: " ").first ?? $0.name)" } ?? "Viggo+"
    }

    var body: some View {
        let now = state.tick
        VStack(alignment: .leading, spacing: 10) {
            // Swapped views overlap in a ZStack: in the VStack both were stacked for the length of
            // the animation, so the card grew and shrank back.
            ZStack(alignment: .topLeading) {
            if searching {
                searchHeader
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
            } else {
            HStack(spacing: 8) {
                if state.friends.isEmpty, let prof = state.profile { Avatar(url: prof.image, size: 26, name: prof.name) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(headerTitle).font(Sz.f(14, .bold)).lineLimit(1).truncationMode(.tail)
                        .contentTransition(.opacity)
                    Text(DateUtil.longDayF.string(from: now).capFirst).font(Sz.f(10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if !state.friends.isEmpty, updater.available == nil {
                    friendGroup.layoutPriority(1)
                }
                if let r = updater.available {
                    Button { updater.show() } label: {
                        Label("Ny version \(r.version)", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold, design: Fomo.design))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .transition(.opacity)
            }
            }

            if state.needsLogin {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Fomo.red)
                    Text("Du er logget ud af Viggo").font(Sz.f(12))
                    Spacer()
                    Button("Log ind igen") { state.loginWithBrowser() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .surface(10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            OfflineBanner(compact: true)
            if !state.status.isEmpty, !searching {
                Text(state.status).font(Sz.f(11)).foregroundStyle(Fomo.red).fixedSize(horizontal: false, vertical: true)
            }

            if !state.friends.isEmpty, updater.available != nil, !searching {
                HStack { friendGroup; Spacer(minLength: 0) }
            }

            ZStack(alignment: .topLeading) {
            if searching {
                PanelSearch(query: $query, height: searchFrame)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
            // The day scrolls when it is taller than the screen (many friends, a long day), so the
            // buttons at the bottom stay in reach.
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    if let fid = state.selectedFriend, let f = state.friends.first(where: { $0.id == fid }) {
                      VStack(alignment: .leading, spacing: 10) {
                        if state.friendExpired.contains(f.id) {
                            HStack {
                                Text("\(f.firstName) skal logge ind igen").font(Sz.f(11)).foregroundStyle(Fomo.red)
                                Spacer()
                                Button("Log ind igen") { state.addFriend(relogin: f) }.controlSize(.small)
                            }
                        }
                        DayPanel(name: f.firstName, events: state.friendEvents[f.id] ?? [],
                                 homework: state.friendHomework[f.id] ?? [], now: now, friend: f)
                      }
                      .id(f.id)
                      .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
                    } else {
                        DayPanel(name: nil, events: state.events, homework: state.homework, now: now)
                            .id("me")
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    if dayHeight == 0 { dayHeight = h } else { withAnimation(.viggo) { dayHeight = h } }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // No scroll bar: it flashed up every time the panel opened and took a column of room.
            // A soft fade at the bottom says there is more when the day is taller than the panel.
            .scrollIndicators(.never)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    if dayHeight > dayFrame + 1 {
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 18)
                    }
                }
            }
            // A fixed height, worked out here: a scroll view left to size itself in the panel sent
            // AppKit into the same endless layout loop that crashed the app.
            .frame(height: dayFrame)
            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            }
            }
            .clipped()

            PanelFooter(searching: searching, toggleSearch: toggleSearch)
                .padding(.top, 2)
        }
        .animation(.viggo, value: state.needsLogin)
        .animation(.viggo, value: updater.available?.version)
        .animation(.viggo, value: state.lastSync)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            guard !searching else { return }
            let c = h - dayFrame
            if abs(c - chrome) > 0.5 { chrome = c }
        }
        .clipped()
        .onReceive(NotificationCenter.default.publisher(for: .panelClosed)) { _ in searching = false; query = "" }
        .panelEscape(searching) { toggleSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .panelSearchTest)) { n in
            // --panel-search-test drives the search the way clicks and typing would.
            let s = n.object as? String ?? ""
            if s == "open" { if !searching { toggleSearch() } }
            else if s == "close" { if searching { toggleSearch() } }
            else if s.hasPrefix("query:") { query = String(s.dropFirst(6)) }
            else if s == "person" { NotificationCenter.default.post(name: .panelSearchPerson, object: nil) }
            else if s == "state" { print("[panelsøg] efter luk og åbn: søger \(searching)"); fflush(stdout) }
            print("[panelsøg] \(s): søger \(searching), mellemstykke \(Int(middle)) pt"); fflush(stdout)
        }
        .frame(width: MenuView.width)
        .tint(Fomo.accent)
        .overlay(alignment: .top) { StatusPillView(compact: true).padding(.top, 8) }
        .overlay(alignment: .bottomTrailing) { QuietLoginBadges(compact: true).padding(.trailing, 12).padding(.bottom, 38) }
    }
}

// MARK: - Settings (tabs)

enum SettingsPage: String, CaseIterable, Identifiable {
    case konto = "Konto", generelt = "Generelt", panel = "Panel", menubar = "Menubar", timer = "Timer", egne = "Egne punkter", kalender = "Kalender", notifikationer = "Notifikationer", venner = "Venner", udseende = "Udseende og haptik", iphone = "iPhone-app"
    var id: String { rawValue }
    var slug: String {
        rawValue.lowercased().replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "æ", with: "ae").replacingOccurrences(of: " ", with: "-")
    }
    var icon: String {
        switch self {
        case .konto: return "person.fill"
        case .generelt: return "gearshape.fill"
        case .panel: return "rectangle.grid.1x2.fill"
        case .menubar: return "menubar.rectangle"
        case .timer: return "paintpalette.fill"
        case .egne: return "checklist"
        case .kalender: return "calendar"
        case .notifikationer: return "bell.badge.fill"
        case .venner: return "person.2.fill"
        case .udseende: return "hand.tap.fill"
        case .iphone: return "iphone"
        }
    }
    var color: Color {
        switch self {
        case .konto: return .blue
        case .generelt: return .gray
        case .panel: return .teal
        case .menubar: return .indigo
        case .timer: return .pink
        case .egne: return .green
        case .kalender: return .orange
        case .notifikationer: return .red
        case .venner: return .blue
        case .udseende: return .purple
        case .iphone: return .mint
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold, design: Fomo.design))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(color.gradient))
    }
}

/// A sidebar row like in System Settings: accent background when selected.
struct SidebarRow<Content: View>: View {
    var highlight: Namespace.ID? = nil
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content() }
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected {
                        // The blue highlight slides to the page you pick.
                        if let highlight {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Fomo.accent)
                                .matchedGeometryEffect(id: "sel", in: highlight)
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Fomo.accent)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Draws a window's content again when the theme changes, so every colour follows at once.
struct ThemeRoot<Content: View>: View {
    @ObservedObject private var p = Prefs.shared
    @ViewBuilder let content: () -> Content
    var body: some View { content().looked().id(p.look) }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var p = Prefs.shared
    @State private var page: SettingsPage?
    @Namespace private var highlight

    init(initial: SettingsPage = .konto) { _page = State(initialValue: initial) }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let prof = state.profile, !state.needsLogin {
                        SidebarRow(highlight: highlight, selected: page == .konto) { withAnimation(.viggo) { page = .konto } } content: {
                            Avatar(url: prof.image, size: 34, name: prof.name)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(prof.name).font(.system(size: 12, weight: .semibold, design: Fomo.design)).lineLimit(1)
                                Text("Viggo-konto").font(.system(size: 10, design: Fomo.design)).opacity(0.7)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    let hasProfile = state.profile != nil && !state.needsLogin
                    ForEach(SettingsPage.allCases.filter { !($0 == .konto && hasProfile) }) { pg in
                        SidebarRow(highlight: highlight, selected: page == pg) { withAnimation(.viggo) { page = pg } } content: {
                            SettingsIcon(symbol: pg.icon, color: pg.color)
                            Text(pg.rawValue).font(.system(size: 13, design: Fomo.design)).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 34)    // room for the window buttons
                .padding(.bottom, 10)
            }
            .frame(width: 210)
            .background(p.look == .classic ? Color.primary.opacity(0.04) : Fomo.surface)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text((page ?? .konto).rawValue)
                    .font(.system(size: 20, weight: .bold, design: Fomo.design))
                    .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 2)
                ZStack(alignment: .topLeading) {
                Group {
                switch page ?? .konto {
                case .konto: AccountTab()
                case .generelt: GeneralTab()
                case .panel: PanelTab()
                case .menubar: MenubarTab()
                case .timer: LessonsTab()
                case .egne: CustomItemsTab()
                case .kalender: CalendarTab()
                case .notifikationer: NotificationsTab()
                case .venner: FriendsTab()
                case .udseende: AppearanceTab()
                case .iphone: PhoneTab()
                }
                }
                .id("\((page ?? .konto).rawValue)-\(p.look.rawValue)")
                // One background for the whole page: the grouped form drew its own, a shade off
                // the window's, so the title sat on a different colour than the rows.
                .scrollContentBackground(.hidden)
                .transition(.opacity.combined(with: .offset(y: 4)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Fomo.bg)
        .looked()
        .modifier(LoginCardOverlay())
        .overlay(alignment: .bottomTrailing) { QuietLoginBadges().padding(14) }
        .frame(width: 680, height: 500)
    }
}

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject var updater = Updater.shared
    var body: some View {
        Form {
            Section {
                Toggle("Start Viggo+ når Mac'en starter", isOn: Binding(get: { state.launchAtLogin },
                                                                       set: { state.launchAtLogin = $0 }))
                Toggle("Vis antal ulæste beskeder og spørgeskemaer i menubaren", isOn: $p.menubarBadge)
            }
            Section("Opdateringer") {
                Toggle("Tjek automatisk for nye versioner", isOn: $p.autoUpdate)
                Toggle("Installer dem selv når Mac'en ikke bruges", isOn: $p.autoInstall)
                    .disabled(!p.autoUpdate)
                Text("Viggo+ opdaterer sig selv efter 5 minutter uden brug og lægger derefter den nye iPhone-app på din iPhone, så snart den er på samme wifi eller sat til med kabel.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Version \(Updater.shared.current)").foregroundStyle(.secondary)
                    Spacer()
                    Text(updater.lastResult).font(.caption).foregroundStyle(.secondary)
                    Button("Tjek nu") { Task { await updater.check(manual: true) } }
                }
            }
            Section("Genvejstast") {
                Toggle("Åbn panelet med en genvejstast", isOn: $p.hotkeyEnabled)
                Picker("Tast", selection: $p.hotkeyChoice) {
                    ForEach(0..<HotKey.choices.count, id: \.self) { i in Text(HotKey.choices[i].label).tag(i) }
                }
                .disabled(!p.hotkeyEnabled)
            }
            FocusSection()
        }
        .formStyle(.grouped)
        .onChange(of: p.hotkeyEnabled) { state.setupHotKey() }
        .onChange(of: p.hotkeyChoice) { state.setupHotKey() }
    }
}

struct MenubarTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $p.menubarRoutine) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis hverdag efter skoletid").font(.headline)
                        Text("Når dagens sidste time er slut, viser menubaren fx \"Aftensmad 18:00\" og \"Godnat 22:15\".")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Toggle(isOn: $p.menubarBreaks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis pauser mellem timerne").font(.headline)
                        Text("I pausen mellem klassens timer viser menubaren fx \"Pause → 09:55\".")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            Section("Hvad skal vises") {
                if state.routineTitles.isEmpty {
                    Text("Log ind for at se listen").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(state.routineTitles, id: \.self) { t in
                    Toggle(t, isOn: Binding(get: { state.inMenubar(t) }, set: { state.toggleMenubar(t, $0) }))
                }
            }
            .disabled(!p.menubarRoutine)
        }
        .formStyle(.grouped)
    }
}

struct CalendarTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @State private var confirmRemove = false

    private var signature: String {
        "\(p.importSchedule)\(p.importHomework)\(p.importEvents)\(p.showBirthdays)\(p.includedRoutines)\(p.lessonAlarmMinutes)\(p.homeworkAlarm)"
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { p.imported },
                                     set: { on in if on { state.importToCalendar() } else { confirmRemove = true } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis Viggo i Apple Kalender").font(.headline)
                        Text(p.imported ? "Holdes opdateret automatisk" : "Slå til for at importere. Slå fra for at fjerne igen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Hvad skal med") {
                CalRow(title: "Skema", color: .blue, on: $p.importSchedule)
                CalRow(title: "Lektier", color: .orange, on: $p.importHomework)
                CalRow(title: "Begivenheder", color: .purple, on: $p.importEvents)
                CalRow(title: "Fødselsdage", color: .pink, on: $p.showBirthdays)
                DisclosureGroup {
                    if state.routineTitles.isEmpty {
                        Text("Log ind for at se listen").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(state.routineTitles, id: \.self) { t in
                        Toggle(t, isOn: Binding(get: { p.includedRoutines.contains(t) }, set: { state.toggleRoutine(t, $0) }))
                    }
                } label: {
                    HStack {
                        Circle().fill(Fomo.green).frame(width: 9, height: 9)
                        Text("Hverdag")
                        Spacer()
                        Text(p.includedRoutines.isEmpty ? "Ingen" : "\(p.includedRoutines.count) valgt")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!p.imported)

            Section("Påmindelser") {
                Picker("Før hver time", selection: $p.lessonAlarmMinutes) {
                    Text("Ingen").tag(0); Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15)
                }
                Toggle("Lektier dagen før kl. 18", isOn: $p.homeworkAlarm)
            }
            .disabled(!p.imported)
        }
        .formStyle(.grouped)
        .onChange(of: signature) { if p.imported { state.applyCalendar() } }
        .confirmationDialog("Fjern Viggo fra Kalender?", isPresented: $confirmRemove) {
            Button("Fjern", role: .destructive) { state.removeFromCalendar() }
        } message: {
            Text("Sletter kun de kalendere Viggo+ har lavet. Du kan slå det til igen når som helst.")
        }
    }
}

struct CalRow: View {
    let title: String
    let color: Color
    @Binding var on: Bool
    var body: some View {
        Toggle(isOn: $on) {
            HStack {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title)
            }
        }
    }
}


/// Username and password fields. "otto1161" is shown as "otto1161@cloud.skoleit.dk".
/// The key next to a friend: save or remove their SkoleIT login.
// MARK: - Sign-in card


// MARK: - Own items


/// Settings > Generelt > Fokus i timerne.
struct FocusSection: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject var fs = FocusShortcuts.shared
    @State private var testing = false

    private var mode: FocusShortcuts.Mode { fs.mode(p.focusMode) }

    var body: some View {
        Section("Fokus i timerne") {
            Toggle("Slå fokus til når en time starter, og fra når den slutter", isOn: $p.focusEnabled)
            Picker("Fokus", selection: $p.focusMode) {
                ForEach(fs.modes.contains(mode) ? fs.modes : fs.modes + [mode]) { m in Text(m.name).tag(m.id) }
            }
            HStack(spacing: 8) {
                if fs.ready(mode) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Fomo.green)
                    Text("Genvejene er klar")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Fomo.warn)
                    Text("Viggo+ mangler to genveje for at kunne slå fokus til")
                }
                Spacer()
                if fs.ready(mode) {
                    Button(testing ? "Tester…" : "Test") { test() }.disabled(testing)
                } else {
                    Button("Opret genveje") { Task { await fs.install(mode) } }.buttonStyle(.borderedProminent)
                }
            }
            if !fs.message.isEmpty {
                Text(fs.message).font(.caption).foregroundStyle(.secondary)
            }
            Text("macOS lader ikke apps slå fokus til direkte, så Viggo+ laver selv to genveje i Genveje-appen, når du slår det til. Du skal bare trykke Tilføj genvej to gange.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { fs.reload() }
        .onChange(of: p.focusEnabled) { state.updateFocus() }
        .onChange(of: p.focusMode) { fs.message = ""; state.updateFocus() }
    }

    /// Turns the Focus on for three seconds and checks with macOS that it really came on.
    private func test() {
        testing = true
        let n = FocusShortcuts.names(for: mode)
        Task {
            defer { testing = false }
            if let err = await fs.run(n.on) { fs.message = err; return }
            try? await Task.sleep(for: .seconds(1.5))
            let on = fs.activeModes()?.contains(mode.id)
            try? await Task.sleep(for: .seconds(1.5))
            if let err = await fs.run(n.off) { fs.message = err; return }
            switch on {
            case true?: fs.message = "\(mode.name) kom til og gik fra igen ✓"
            case false?: fs.message = "Genvejen kørte, men \(mode.name) blev ikke slået til."
            case nil: fs.message = "Genvejen kørte ✓"
            }
        }
    }
}

/// The row at the bottom of the panel. Four styles to try (Indstillinger, Panel, Knapper i bunden):
/// Ikoner is the old row of eight icons; the others put the four places you go (Søg, Uge, Træning,
/// Beskeder) first and the rest (synk, Viggo, indstillinger, afslut) in one Mere menu.
enum FooterStyle: String, CaseIterable, Identifiable {
    case tabs = "faner", search = "soeg", pill = "pille", icons = "ikoner"
    var id: String { rawValue }
    var title: String {
        switch self { case .tabs: "Faner"; case .search: "Søgefelt"; case .pill: "Pille"; case .icons: "Ikoner" }
    }
    var blurb: String {
        switch self {
        case .tabs: "Fire knapper med navn under, som faner på en iPhone. Resten ligger i Mere."
        case .search: "Et stort søgefelt og tre knapper. Søg er det du bruger mest."
        case .pill: "Fem ikoner samlet i en lille pille i midten. Mest stille."
        case .icons: "Alle otte ikoner på én række, som før."
        }
    }
}

struct PanelFooter: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var p = Prefs.shared
    let searching: Bool
    let toggleSearch: () -> Void

    private var syncText: String? {
        guard let s = state.lastSync else { return nil }
        return DateUtil.cal.isDateInToday(s) ? "Synket \(DateUtil.hm(s))" : DateUtil.cal.isDateInYesterday(s) ? "Synket i går" : "Synket \(DateUtil.day(s))"
    }

    var body: some View {
        Group {
            switch FooterStyle(rawValue: p.footerStyle) ?? .tabs {
            case .icons: icons
            case .tabs: tabs
            case .search: searchRow
            case .pill: pill
            }
        }
        .animation(.viggo, value: p.footerStyle)
    }

    // MARK: Ikoner (the old row)

    private var icons: some View {
        HStack(spacing: 9) {
            // Short, so it never breaks in two next to the buttons: "Synket 13:38".
            if let t = syncText {
                Text(t).font(.system(size: 10, design: Fomo.design)).monospacedDigit().foregroundStyle(Fomo.text2.opacity(0.8))
                    .lineLimit(1).fixedSize()
                    .contentTransition(.numericText())
                    .help(state.syncedText ?? "")
            }
            Spacer(minLength: 4)
            Button { Task { await state.syncWithPill() } } label: { SyncIcon(spinning: state.syncing) }
                .help(state.needsLogin ? "Log ind igen for at synke" : "Synk nu")
            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass").foregroundStyle(searching ? Fomo.accent : Fomo.text2)
            }
            .help(searching ? "Tilbage til dagen (Esc)" : "Søg (⌘F)").keyboardShortcut("f")
            Button { state.openWeek() } label: { Image(systemName: "calendar") }.help("Uge-overblik")
            Button { state.openTraining() } label: { Image(systemName: "dumbbell") }.help("Træning")
            Button { state.openMessages() } label: { Image(systemName: "bubble.left.and.bubble.right").overlay(alignment: .topTrailing) { badge } }
                .help("Beskeder")
            Button { state.openViggo() } label: { Image(systemName: "safari") }.help("Åbn Viggo")
            Button { state.openSettings() } label: { Image(systemName: "gearshape") }.help("Indstillinger")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Afslut")
        }
        .buttonStyle(PressScale(scale: 0.82))
        .foregroundStyle(Fomo.text2)
        .font(.system(size: 12, design: Fomo.design))
    }

    // MARK: Faner

    private var tabs: some View {
        HStack(spacing: 2) {
            tab("magnifyingglass", "Søg", on: searching, action: toggleSearch).keyboardShortcut("f")
            tab("calendar", "Uge") { state.openWeek() }
            tab("dumbbell", "Træning") { state.openTraining() }
            tab("bubble.left.and.bubble.right", "Beskeder", badge: true) { state.openMessages() }
            more(fill: true) { tabLabel("ellipsis", "Mere", on: false) }
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Rectangle().fill(Fomo.text2.opacity(0.15)).frame(height: 0.5).offset(y: -4) }
    }

    private func tab(_ icon: String, _ title: String, on: Bool = false, badge show: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { tabLabel(icon, title, on: on).overlay(alignment: .top) { if show { badge.offset(x: 10, y: 0) } } }
            .buttonStyle(PressScale(scale: 0.9))
            .help(title)
    }

    private func tabLabel(_ icon: String, _ title: String, on: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium, design: Fomo.design)).frame(height: 17)
            Text(title).font(.system(size: 9.5, weight: .medium, design: Fomo.design)).lineLimit(1)
        }
        .foregroundStyle(on ? Fomo.accent : Fomo.text2)
        .frame(maxWidth: .infinity).padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: Søgefelt

    private var searchRow: some View {
        HStack(spacing: 6) {
            Button(action: toggleSearch) {
                HStack(spacing: 6) {
                    Image(systemName: searching ? "xmark.circle.fill" : "magnifyingglass")
                    Text(searching ? "Tilbage til dagen" : "Søg i Viggo").lineLimit(1)
                    Spacer(minLength: 4)
                    if !searching { Text("⌘F").font(.system(size: 10, weight: .medium, design: Fomo.design)).opacity(0.6) }
                }
                .font(.system(size: 12, design: Fomo.design))
                .foregroundStyle(searching ? Fomo.accent : Fomo.text2)
                .padding(.horizontal, 10).frame(height: 28)
                .background(Capsule().fill(Fomo.surface))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScale(scale: 0.97))
            .keyboardShortcut("f")
            circle("calendar", "Uge-overblik") { state.openWeek() }
            circle("dumbbell", "Træning") { state.openTraining() }
            circle("bubble.left.and.bubble.right", "Beskeder", badge: true) { state.openMessages() }
            more { circleLabel("ellipsis") }
        }
    }

    private func circle(_ icon: String, _ help: String, badge show: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(icon).overlay(alignment: .topTrailing) { if show { badge.offset(x: 3, y: -2) } } }
            .buttonStyle(PressScale(scale: 0.85))
            .help(help)
    }

    private func circleLabel(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 12, weight: .medium, design: Fomo.design))
            .foregroundStyle(Fomo.text2)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Fomo.surface))
            .contentShape(Circle())
    }

    // MARK: Pille

    private var pill: some View {
        HStack(spacing: 0) {
            pillButton("magnifyingglass", "Søg (⌘F)", on: searching, action: toggleSearch).keyboardShortcut("f")
            pillButton("calendar", "Uge-overblik") { state.openWeek() }
            pillButton("dumbbell", "Træning") { state.openTraining() }
            pillButton("bubble.left.and.bubble.right", "Beskeder", badge: true) { state.openMessages() }
            more { pillLabel("ellipsis", on: false) }
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(Fomo.surface))
        .frame(maxWidth: .infinity)
    }

    private func pillButton(_ icon: String, _ help: String, on: Bool = false, badge show: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(icon, on: on).overlay(alignment: .topTrailing) { if show { badge.offset(x: -2, y: 2) } } }
            .buttonStyle(PressScale(scale: 0.85))
            .help(help)
    }

    private func pillLabel(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon).font(.system(size: 13, weight: .medium, design: Fomo.design))
            .foregroundStyle(on ? Fomo.accent : Fomo.text2)
            .frame(width: 40, height: 32)
            .contentShape(Rectangle())
    }

    // MARK: shared

    @ViewBuilder private var badge: some View {
        if state.unreadCount > 0 {
            Text("\(state.unreadCount)").font(.system(size: 8, weight: .bold, design: Fomo.design)).foregroundStyle(.white)
                .padding(.horizontal, 3).frame(minWidth: 12, minHeight: 12)
                .background(Capsule().fill(Fomo.red)).offset(x: 7, y: -6)
        }
    }

    /// Synk, Åbn Viggo, Indstillinger and Afslut, with when it last synced at the top.
    private func more<L: View>(fill: Bool = false, @ViewBuilder label: () -> L) -> some View {
        Menu {
            if let t = syncText { Text(t) }
            Button { Task { await state.syncWithPill() } } label: { Label("Synk nu", systemImage: "arrow.clockwise") }
            Divider()
            Button { state.openViggo() } label: { Label("Åbn Viggo", systemImage: "safari") }
            Button { state.openSettings() } label: { Label("Indstillinger …", systemImage: "gearshape") }
            Divider()
            Button { NSApp.terminate(nil) } label: { Label("Afslut Viggo+", systemImage: "power") }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // In Faner it takes the same width as the other four, so the five sit evenly.
        .fixedSize(horizontal: !fill, vertical: true)
        .frame(maxWidth: fill ? .infinity : nil)
        .help("Mere")
    }
}
