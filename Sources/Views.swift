import SwiftUI

@main
struct ViggoPlusApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap.fill")
                if !state.menuTitle.isEmpty { Text(state.menuTitle) }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Small pieces

struct Avatar: View {
    let url: URL?
    var size: CGFloat = 28
    var body: some View {
        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

struct EventRow: View {
    let e: ViggoEvent
    let now: Date
    var body: some View {
        let past = e.end < now
        let current = e.start <= now && e.end > now
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DateUtil.hm(e.start))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 13, weight: current ? .semibold : .regular)).lineLimit(1)
                if !e.room.isEmpty {
                    Text(e.room).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if current {
                Text("NU").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
        }
        .opacity(past ? 0.4 : 1)
        .contentShape(Rectangle())
    }
}

struct DayList: View {
    let items: [ViggoEvent]
    let now: Date
    var empty = "Intet i dag 🎉"
    var body: some View {
        if items.isEmpty {
            Text(empty).font(.system(size: 12)).foregroundStyle(.secondary)
        } else if items.count <= 7 {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items) { EventRow(e: $0, now: now) }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { EventRow(e: $0, now: now) }
                }
            }.frame(height: 230)
        }
    }
}

struct PersonChip: View {
    let url: URL?
    let label: String
    let selected: Bool
    var expired = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Avatar(url: url, size: 30)
                    .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 2).padding(-2))
                    .opacity(expired ? 0.4 : 1)
                Text(label).font(.system(size: 10, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .frame(width: 48)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menubar panel

struct MenuView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let now = state.tick
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let prof = state.profile { Avatar(url: prof.image, size: 30) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.profile.map { "Hej \($0.name.components(separatedBy: " ").first ?? $0.name)" } ?? "Viggo+")
                        .font(.system(size: 15, weight: .bold))
                    Text(DateUtil.longDayF.string(from: now).capitalized).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if state.syncing { ProgressView().controlSize(.small) }
                Button { Task { await state.sync() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Synk nu")
            }

            if state.needsLogin {
                Button("Log ind på Viggo…") { state.loginWithBrowser() }.buttonStyle(.borderedProminent)
            }
            if !state.status.isEmpty {
                Text(state.status).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if !state.friends.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        PersonChip(url: state.profile?.image, label: "Mig", selected: state.selectedFriend == nil) {
                            state.selectedFriend = nil
                        }
                        ForEach(state.friends) { f in
                            PersonChip(url: f.image, label: f.firstName, selected: state.selectedFriend == f.id,
                                       expired: state.friendExpired.contains(f.id)) { state.selectedFriend = f.id }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }

            Divider()
            if let fid = state.selectedFriend, let f = state.friends.first(where: { $0.id == fid }) {
                FriendPanel(friend: f, now: now)
            } else {
                MyPanel(now: now)
            }

            Divider()
            HStack {
                if let s = state.lastSync {
                    Text("Synket \(DateUtil.hm(s))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Viggo") { state.openViggo() }.buttonStyle(.borderless)
                Button("Indstillinger") { state.openSettings() }.buttonStyle(.borderless)
                Button("Afslut") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            .font(.system(size: 11))
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct FriendPanel: View {
    @EnvironmentObject var state: AppState
    let friend: Friend
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.friendExpired.contains(friend.id) {
                HStack {
                    Text("\(friend.firstName)s login er udløbet").font(.system(size: 11)).foregroundStyle(.orange)
                    Spacer()
                    Button("Log ind igen") { state.addFriend(relogin: friend) }.controlSize(.small)
                }
            }
            DayPanel(name: friend.firstName, events: state.friendEvents[friend.id] ?? [],
                     homework: state.friendHomework[friend.id] ?? [], now: now, showMessages: false)
        }
    }
}

struct MyPanel: View {
    @EnvironmentObject var state: AppState
    let now: Date
    var body: some View {
        DayPanel(name: nil, events: state.events, homework: state.homework, now: now, showMessages: true)
    }
}

/// Same layout for you and your friends.
struct DayPanel: View {
    @EnvironmentObject var state: AppState
    let name: String?
    let events: [ViggoEvent]
    let homework: [Homework]
    let now: Date
    let showMessages: Bool

    var body: some View {
        let today = state.items(on: now, from: events)
        let tomorrow = state.items(on: DateUtil.add(.day, 1, now), from: events)
        let evening = state.afterSchool(now, from: events)
        let hw = homework.filter { $0.day >= DateUtil.startOfDay(now) }
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: name.map { "\($0) i dag" } ?? "I dag")
            DayList(items: today, now: now)
            if let first = tomorrow.first {
                Text("I morgen: \(first.title) kl. \(DateUtil.hm(first.start)) · \(tomorrow.count) punkter")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !evening.isEmpty {
                SectionHeader(title: "Resten af dagen")
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(evening) { EventRow(e: $0, now: now) }
                }
            }
            if name == nil, !state.dutyTonight.isEmpty {
                Text("Aftenvagt: \(state.dutyTonight.joined(separator: ", "))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Divider()
            SectionHeader(title: "Lektier og afleveringer")
            if hw.isEmpty {
                Text("Ingen lektier 🙌").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(hw.prefix(5)) { h in
                    HStack(spacing: 8) {
                        Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(h.done ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.title).font(.system(size: 13)).strikethrough(h.done).lineLimit(1)
                            Text("\(DateUtil.day(h.due))\(h.group.isEmpty ? "" : " · \(h.group)")")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if name == nil { NSWorkspace.shared.open(h.link) } }
                }
            }

            if showMessages {
                Divider()
                SectionHeader(title: "Seneste beskeder")
                if state.messages.isEmpty {
                    Text("Ingen beskeder").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(state.messages.prefix(3)) { m in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(m.sender).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Spacer()
                                Text(m.when).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Text(m.subject).font(.system(size: 12)).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.openViggo(m.link) }
                    }
                }
            }
        }
    }
}

// MARK: - Settings (tabs)

enum SettingsPage: String, CaseIterable, Identifiable {
    case konto = "Konto", menubar = "Menubar", kalender = "Kalender", notifikationer = "Notifikationer", venner = "Venner"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .konto: return "person.fill"
        case .menubar: return "menubar.rectangle"
        case .kalender: return "calendar"
        case .notifikationer: return "bell.badge.fill"
        case .venner: return "person.2.fill"
        }
    }
    var color: Color {
        switch self {
        case .konto: return .gray
        case .menubar: return .indigo
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

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var page: SettingsPage? = .konto

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                if let prof = state.profile, !state.needsLogin {
                    HStack(spacing: 10) {
                        Avatar(url: prof.image, size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(prof.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("Viggo-konto").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(SettingsPage.konto)
                }
                Section {
                    ForEach(SettingsPage.allCases) { pg in
                        Label { Text(pg.rawValue) } icon: { SettingsIcon(symbol: pg.icon, color: pg.color) }
                            .tag(pg)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch page ?? .konto {
                case .konto: AccountTab()
                case .menubar: MenubarTab()
                case .kalender: CalendarTab()
                case .notifikationer: NotificationsTab()
                case .venner: FriendsTab()
                }
            }
            .navigationTitle((page ?? .konto).rawValue)
        }
        .frame(width: 680, height: 500)
    }
}

struct AccountTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @State private var username = Prefs.shared.username.replacingOccurrences(of: Config.loginDomain, with: "")
    @State private var password = ""

    var body: some View {
        Form {
            if let prof = state.profile, !state.needsLogin {
                Section {
                    HStack(spacing: 12) {
                        Avatar(url: prof.image, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prof.name).font(.headline)
                            Text("Logget ind på \(Config.baseURL.host ?? "Viggo")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Log ud", role: .destructive) { state.logout() }
                    }
                }
                Section("Automatisk login") {
                    if p.hasPassword {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Logger selv ind igen når sessionen udløber")
                                Text(p.username).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Fjern") { state.forgetSavedLogin() }
                        }
                        Toggle("Lås op med Touch ID ved start", isOn: $p.useTouchID)
                    } else {
                        Text("Gem dit SkoleIT-login, så logger Viggo+ selv ind igen i stedet for at spørge dig.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Brugernavn (fx brugernavn)", text: $username)
                        SecureField("Adgangskode", text: $password)
                        HStack {
                            Button("Gem login") { Task { await state.saveLogin(username: username, password: password); password = "" } }
                                .buttonStyle(.borderedProminent)
                                .disabled(username.isEmpty || password.isEmpty)
                            Spacer()
                            Text(state.loginMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Section("Log ind") {
                    Button("Åbn Viggo-login…") { state.loginWithBrowser() }.buttonStyle(.borderedProminent)
                    Text("UNI-Login, SkoleIT eller adgangskode. Når sessionen udløber, får du besked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Eller gem SkoleIT-login (logger selv ind igen)") {
                    TextField("Brugernavn (fx brugernavn)", text: $username)
                    SecureField("Adgangskode", text: $password)
                    HStack {
                        Button("Gem og log ind") { Task { await state.saveLogin(username: username, password: password); password = "" } }
                            .disabled(username.isEmpty || password.isEmpty)
                        Spacer()
                        Text(state.loginMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Lås op med Touch ID ved start", isOn: $p.useTouchID)
                }
            }
        }
        .formStyle(.grouped)
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

struct NotificationsTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Form {
            Section("Giv besked om") {
                Toggle("Flyttede eller aflyste timer", isOn: $p.notifyChanges)
                Toggle("Nye lektier", isOn: $p.notifyHomework)
                Toggle("Nye beskeder", isOn: $p.notifyMessages)
            }
            Section("Daglig brief") {
                Toggle("Slået til", isOn: $p.briefs)
                Stepper("Morgen kl. \(p.morningHour)", value: $p.morningHour, in: 5...11).disabled(!p.briefs)
                Stepper("Aften kl. \(p.eveningHour)", value: $p.eveningHour, in: 16...23).disabled(!p.briefs)
            }
            Section {
                Button("Send test-notifikation") {
                    Notifier.shared.post("Viggo+ test", state.brief(for: Date(), prefix: "I dag"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FriendsTab: View {
    @EnvironmentObject var state: AppState
    @State private var editing: Friend?
    @State private var adding = false

    var body: some View {
        Form {
            Section {
                if state.friends.isEmpty {
                    Text("Ingen venner tilføjet endnu").foregroundStyle(.secondary)
                }
                ForEach(state.friends) { f in
                    let expired = state.friendExpired.contains(f.id)
                    HStack(spacing: 10) {
                        Avatar(url: f.image, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name)
                            let (txt, col): (String, Color) = {
                                if f.savedUsername != nil {
                                    switch f.loginVerified {
                                    case true?: return ("Gemt login virker · logger selv ind igen", .green)
                                    case false?: return ("Gemt login virker ikke", .red)
                                    case nil: return ("Login gemt · ikke verificeret", .orange)
                                    }
                                }
                                return expired ? ("Login udløbet", .orange) : ("Skema synket", .secondary)
                            }()
                            Text(txt).font(.caption).foregroundStyle(col)
                        }
                        Spacer()
                        if f.savedUsername != nil && f.loginVerified != true {
                            Button("Verificér") { Task { await state.verifyFriendLogin(f) } }
                        } else if expired {
                            Button("Log ind igen") { state.addFriend(relogin: f) }
                        }
                        Menu {
                            if f.savedUsername == nil {
                                Button("Gem login…") { editing = f }
                            } else {
                                Button("Verificér login") { Task { await state.verifyFriendLogin(f) } }
                                Button("Skift gemt login…") { editing = f }
                                Button("Fjern gemt login") { state.forgetFriendLogin(f) }
                            }
                            Divider()
                            Button("Fjern ven", role: .destructive) { state.removeFriend(f) }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            Section {
                Button("Tilføj ven…") { state.friendMessage = ""; adding = true }.buttonStyle(.borderedProminent)
                Text("Din ven logger selv ind i et privat vindue. Kun skema og lektier hentes, og det bliver på din Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if !state.friendMessage.isEmpty {
                    Text(state.friendMessage).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { f in FriendLoginSheet(friend: f) }
        .sheet(isPresented: $adding) { AddFriendSheet() }
    }
}

struct FriendLoginSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    @State private var username = ""
    @State private var password = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Avatar(url: friend.image, size: 40)
                VStack(alignment: .leading) {
                    Text("Automatisk login for \(friend.firstName)").font(.headline)
                    Text("Lad \(friend.firstName) selv skrive sit SkoleIT-login.").font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField("Brugernavn", text: $username).textFieldStyle(.roundedBorder)
            if !username.isEmpty {
                Text("Logger ind som \(AppState.normalize(username))").font(.caption).foregroundStyle(.secondary)
            }
            SecureField("Adgangskode", text: $password).textFieldStyle(.roundedBorder)
            Label("Gemmes i nøgleringen og låses med Touch ID eller din Mac-kode. Test det bagefter med Verificér.",
                  systemImage: "touchid")
                .font(.caption).foregroundStyle(.secondary)
            if !state.friendMessage.isEmpty && !working { Text(state.friendMessage).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Annuller") { dismiss() }
                Button("Gem") {
                    working = true
                    Task {
                        let ok = await state.saveFriendLogin(friend, username: username, password: password)
                        working = false
                        password = ""
                        if ok { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || working)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

struct AddFriendSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var remember = true
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tilføj ven").font(.title3.bold())
            Text("Lad din ven selv logge ind. Kun skema og lektier hentes, og det bliver på din Mac.")
                .font(.caption).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("UNI-Login eller adgangskode", systemImage: "globe").font(.headline)
                    Text("Åbner Viggos egen login-side i et privat vindue.").font(.caption).foregroundStyle(.secondary)
                    Button("Åbn Viggo-login…") { dismiss(); state.addFriend() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("SkoleIT-login", systemImage: "person.badge.key").font(.headline)
                    TextField("Brugernavn", text: $username).textFieldStyle(.roundedBorder)
                    if !username.isEmpty {
                        Text("Logger ind som \(AppState.normalize(username))").font(.caption).foregroundStyle(.secondary)
                    }
                    SecureField("Adgangskode", text: $password).textFieldStyle(.roundedBorder)
                    Toggle("Gem i nøgleringen (Touch ID) og log selv ind igen", isOn: $remember)
                    HStack {
                        if working { ProgressView().controlSize(.small) }
                        Text(state.friendMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button("Tilføj") {
                            working = true
                            Task {
                                let ok = await state.addFriendWithPassword(username: username, password: password, remember: remember)
                                working = false
                                if ok { password = ""; dismiss() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(username.isEmpty || password.isEmpty || working)
                    }
                }
                .padding(4)
            }

            HStack { Spacer(); Button("Annuller") { dismiss() } }
        }
        .padding(20)
        .frame(width: 400)
    }
}
