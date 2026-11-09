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

// MARK: - Menubar panel

struct MenuView: View {
    static var width: CGFloat { 320 * (Prefs.shared.panelLarge ? 1.12 : 1) }
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject var updater = Updater.shared
    @Namespace private var ring

    private var headerTitle: String {
        if let fid = state.selectedFriend, let f = state.friends.first(where: { $0.id == fid }) { return f.name }
        return state.profile.map { "Hej \($0.name.components(separatedBy: " ").first ?? $0.name)" } ?? "Viggo+"
    }

    var body: some View {
        let now = state.tick
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if state.friends.isEmpty, let prof = state.profile { Avatar(url: prof.image, size: 26, name: prof.name) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(headerTitle).font(Sz.f(14, .bold)).lineLimit(1)
                        .contentTransition(.opacity)
                    Text(DateUtil.longDayF.string(from: now).capitalized).font(Sz.f(10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if !state.friends.isEmpty, updater.available == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            PersonChip(ring: ring, url: state.profile?.image, label: "Mig", fullName: state.profile?.name, selected: state.selectedFriend == nil) {
                                withAnimation(.viggo) { state.selectedFriend = nil }
                            }
                            ForEach(state.friends) { f in
                                PersonChip(ring: ring, url: f.image, label: f.firstName, fullName: f.name, selected: state.selectedFriend == f.id,
                                           expired: state.friendExpired.contains(f.id)) { withAnimation(.viggo) { state.selectedFriend = f.id } }
                            }
                        }
                    }
                    .fixedSize(horizontal: state.friends.count <= 4, vertical: false)
                }
                if let r = updater.available {
                    Button { updater.show() } label: {
                        Label("Ny version \(r.version)", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            if state.needsLogin {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("Du er logget ud af Viggo").font(Sz.f(12))
                    Spacer()
                    Button("Log ind") { state.loginWithBrowser() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !state.status.isEmpty {
                Text(state.status).font(Sz.f(11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if !state.friends.isEmpty, updater.available != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        PersonChip(ring: ring, url: state.profile?.image, label: "Mig", fullName: state.profile?.name, selected: state.selectedFriend == nil) {
                            withAnimation(.viggo) { state.selectedFriend = nil }
                        }
                        ForEach(state.friends) { f in
                            PersonChip(ring: ring, url: f.image, label: f.firstName, fullName: f.name, selected: state.selectedFriend == f.id,
                                       expired: state.friendExpired.contains(f.id)) { withAnimation(.viggo) { state.selectedFriend = f.id } }
                        }
                    }
                }
            }

            if let fid = state.selectedFriend, let f = state.friends.first(where: { $0.id == fid }) {
                if state.friendExpired.contains(f.id) {
                    HStack {
                        Text("\(f.firstName) skal logge ind igen").font(Sz.f(11)).foregroundStyle(.orange)
                        Spacer()
                        Button("Log ind igen") { state.addFriend(relogin: f) }.controlSize(.small)
                    }
                }
                DayPanel(name: f.firstName, events: state.friendEvents[f.id] ?? [],
                         homework: state.friendHomework[f.id] ?? [], now: now)
                    .id(f.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            } else {
                DayPanel(name: nil, events: state.events, homework: state.homework, now: now)
                    .id("me")
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }

            HStack(spacing: 14) {
                if let s = state.lastSync {
                    Text("Synket \(DateUtil.hm(s))").font(.system(size: 10)).foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { Task { await state.sync() } } label: { SyncIcon(spinning: state.syncing) }.help("Synk nu")
                Button { state.openWeek() } label: { Image(systemName: "calendar") }.help("Uge-overblik")
                Button { state.openViggo() } label: { Image(systemName: "safari") }.help("Åbn Viggo")
                Button { state.openSettings() } label: { Image(systemName: "gearshape") }.help("Indstillinger")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Afslut")
            }
            .buttonStyle(PressScale(scale: 0.82))
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
            .padding(.top, 2)
        }
        .animation(.viggo, value: state.needsLogin)
        .animation(.viggo, value: updater.available?.version)
        .animation(.viggo, value: state.lastSync)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: MenuView.width)
    }
}

// MARK: - Settings (tabs)

enum SettingsPage: String, CaseIterable, Identifiable {
    case konto = "Konto", generelt = "Generelt", panel = "Panel", menubar = "Menubar", timer = "Timer", egne = "Egne punkter", kalender = "Kalender", notifikationer = "Notifikationer", venner = "Venner"
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
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
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
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                                .matchedGeometryEffect(id: "sel", in: highlight)
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
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
                                Text(prof.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text("Viggo-konto").font(.system(size: 10)).opacity(0.7)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    let hasProfile = state.profile != nil && !state.needsLogin
                    ForEach(SettingsPage.allCases) { pg in
                        SidebarRow(highlight: highlight, selected: page == pg && !(pg == .konto && hasProfile)) { withAnimation(.viggo) { page = pg } } content: {
                            SettingsIcon(symbol: pg.icon, color: pg.color)
                            Text(pg.rawValue).font(.system(size: 13)).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 34)    // room for the window buttons
                .padding(.bottom, 10)
            }
            .frame(width: 210)
            .background(Color.primary.opacity(0.04))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text((page ?? .konto).rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 2)
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
                }
                }
                .id(page ?? .konto)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(LoginCardOverlay())
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
            Section("Fokus i timerne") {
                Toggle("Slå fokus til når en time starter, og fra når den slutter", isOn: $p.focusEnabled)
                TextField("Genvej når timen starter", text: $p.focusOnShortcut)
                TextField("Genvej når timen slutter", text: $p.focusOffShortcut)
                HStack {
                    Button("Test start") { state.runShortcut(p.focusOnShortcut) }
                    Button("Test slut") { state.runShortcut(p.focusOffShortcut) }
                    Spacer()
                    Button("Åbn Genveje") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                }
                Text("macOS lader ikke apps slå fokus til direkte. Lav to genveje i Genveje-appen med handlingen \"Indstil fokus\" (fx Forstyr ikke til og fra), og giv dem navnene ovenfor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                        Circle().fill(.green).frame(width: 9, height: 9)
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

