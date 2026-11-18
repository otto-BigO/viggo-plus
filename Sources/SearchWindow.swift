import AppKit
import SwiftUI

/// Søg on the Mac: one search for people (name, class, room, house, line, initials), groups,
/// messages (Viggo searches the text of them too), the week's lessons, homework and posts. The
/// results are on the left, the person or group on the right. Same search as on the iPhone.
struct SearchWindow: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dir = Directory.shared
    @StateObject private var inbox = Inbox.shared
    @State private var query = ProcessInfo.processInfo.environment["VIGGO_SEARCH"] ?? ""
    @State private var selection: Found?
    @State private var path: [Found] = []
    @State private var found: [MessageThread] = []
    @State private var searchingViggo = false
    @State private var allPeople = false
    @AppStorage("recentSearches") private var recentRaw = ""

    /// The query the results are for. It follows what you type after a short pause.
    @State private var q = Directory.normalize(ProcessInfo.processInfo.environment["VIGGO_SEARCH"] ?? "")
    @State private var people: [Member] = []
    @State private var groups: [MemberGroup] = []
    @State private var localThreads: [MessageThread] = []
    @State private var lessons: [ViggoEvent] = []
    @State private var homework: [Homework] = []
    @State private var posts: [Bulletin] = []
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var threads: [MessageThread] {
        var seen = Set(localThreads.map(\.id))
        return localThreads + found.filter { seen.insert($0.id).inserted }
    }
    private var nothing: Bool {
        people.isEmpty && groups.isEmpty && threads.isEmpty && lessons.isEmpty && homework.isEmpty && posts.isEmpty
    }

    private func compute() {
        people = dir.search(q)
        groups = Array(dir.searchGroups(q).prefix(6))
        guard !q.isEmpty else { localThreads = []; lessons = []; homework = []; posts = []; return }
        localThreads = inbox.threads.filter { "\($0.sender) \($0.subject) \($0.preview)".lowercased().contains(q) }
        guard q.count >= 2 else { lessons = []; homework = []; posts = []; return }
        let now = Date()
        lessons = state.events.filter { e in
            e.end > now && (e.kind == .lesson || e.kind == .event) &&
            "\(e.title) \(e.rawName) \(e.room) \(e.teachers.joined(separator: " ")) \(e.notes)".lowercased().contains(q)
        }
        .sorted { $0.start < $1.start }.prefix(6).map { $0 }
        homework = state.homework.filter { "\($0.title) \($0.group) \($0.notes) \($0.author)".lowercased().contains(q) }
            .sorted { $0.due > $1.due }.prefix(5).map { $0 }
        posts = state.bulletins.filter { "\($0.title) \($0.author) \($0.body) \($0.text)".lowercased().contains(q) }.prefix(5).map { $0 }
        if CommandLine.arguments.contains("--feature-test") {
            print("[search] \(q): \(people.count) personer, \(groups.count) grupper, \(localThreads.count) beskeder, \(lessons.count) timer, \(homework.count) lektier, \(posts.count) opslag")
            fflush(stdout)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if q.isEmpty { suggestions } else { results }
            }
            .overlay {
                if !q.isEmpty, nothing, !searchingViggo, !dir.loading { ContentUnavailableView.search(text: query) }
                else if dir.members.isEmpty, dir.loading { ProgressView("Henter personer") }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Navn, klasse, værelse, besked…")
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                remember(query)
                // Return opens the first person or group, like Spotlight.
                if let m = people.first { selection = .person(m.id) } else if let g = groups.first { selection = .group(g.id) }
            }
            .task(id: query) {
                let n = Directory.normalize(query)
                if !n.isEmpty, n != q { try? await Task.sleep(for: .milliseconds(120)) }
                guard !Task.isCancelled else { return }
                if n != q { q = n }
                compute()
            }
            .task(id: q) { await searchViggo() }
            .task { await dir.load(); if inbox.threads.isEmpty { await inbox.load() }; compute() }
            .onChange(of: dir.members.count) { compute() }
            .onChange(of: inbox.threads.count) { compute() }
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if let s = selection { MacFoundView(found: s).id(s) }
                    else {
                        ContentUnavailableView("Søg i Viggo", systemImage: "magnifyingglass",
                                               description: Text("Find elever, lærere, klasser, værelser, beskeder og timer."))
                    }
                }
                .navigationDestination(for: Found.self) { MacFoundView(found: $0) }
            }
        }
        .onChange(of: selection) {
            path = []
            if case .thread(let id) = selection { state.openMessages(thread: id) }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await dir.load(force: true); compute() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Hent adressebogen igen")
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    // MARK: before typing

    @ViewBuilder private var suggestions: some View {
        if let e = dir.error {
            Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        if !recent.isEmpty {
            Section("Seneste") {
                ForEach(recent, id: \.self) { r in
                    Button { query = r } label: { Label(r, systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain)
                }
                Button("Ryd seneste") { recentRaw = "" }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        if let me = state.profile.flatMap({ dir.member($0.id) }) {
            Section("Dine") {
                let mine = dir.groups(of: me.id).filter { [.klasse, .linje, .gruppe].contains($0.kind) }
                ForEach(mine) { g in MacGroupRow(g: g).tag(Found.group(g.id)) }
                if !me.room.isEmpty {
                    Label("Dig og værelse \(me.room)", systemImage: "bed.double.fill").tag(Found.person(me.id))
                }
            }
        }
        Section {
            ForEach(["10.4", "Musiklinjen", "D17", "Valgfag", "Fødselsdag"], id: \.self) { s in
                Button { query = s } label: { Label(s, systemImage: "magnifyingglass") }.buttonStyle(.plain)
            }
        } header: { Text("Prøv fx") } footer: {
            Text("Søg efter navn, klasse (10.4), værelse (D17), hus, linje, valgfag, initialer eller elevnummer. Beskeder søges i hele teksten.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: results

    @ViewBuilder private var results: some View {
        if q == "fødselsdag" || q == "fødselsdage" { birthdays }
        if !people.isEmpty {
            Section("Personer") {
                ForEach(allPeople ? people : Array(people.prefix(8))) { m in MacPersonRow(m: m).tag(Found.person(m.id)) }
                if people.count > 8 {
                    Button(allPeople ? "Vis færre" : "Vis alle \(people.count)") { withAnimation(.viggo) { allPeople.toggle() } }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
            }
        }
        if !groups.isEmpty {
            Section("Grupper") {
                ForEach(groups) { g in MacGroupRow(g: g).tag(Found.group(g.id)) }
            }
        }
        if !threads.isEmpty || searchingViggo {
            Section {
                ForEach(threads.prefix(20)) { t in MacFoundThreadRow(t: t, q: q).tag(Found.thread(t.id)) }
            } header: {
                HStack { Text("Beskeder"); if searchingViggo { ProgressView().controlSize(.mini) } }
            }
        }
        if !lessons.isEmpty {
            Section("Skema") {
                ForEach(lessons) { e in
                    Button { state.openLesson(e) } label: { MacLessonRow(e: e) }.buttonStyle(.plain)
                }
            }
        }
        if !homework.isEmpty {
            Section("Lektier") {
                ForEach(homework) { h in
                    Button { NSWorkspace.shared.open(h.link) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title).font(.system(size: 13, weight: .medium))
                            Text("\(h.group) · \(h.due.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "da_DK"))))")
                                .font(.caption).foregroundStyle(.secondary)
                            if !h.notes.isEmpty { Text(h.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !posts.isEmpty {
            Section("Opslag") {
                ForEach(posts) { b in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text("\(b.author) · \(b.when)").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(Found.bulletin(b))
                }
            }
        }
    }

    /// "Fødselsdag": the students with a birthday coming up.
    @ViewBuilder private var birthdays: some View {
        let soon = dir.members.filter { $0.kind == .student }
            .compactMap { m in m.nextBirthday.map { (m, $0) } }
            .sorted { $0.1.days < $1.1.days }.prefix(15)
        Section("Næste fødselsdage") {
            ForEach(Array(soon), id: \.0.id) { m, b in
                HStack {
                    MacPersonRow(m: m)
                    Spacer()
                    Text(b.days == 0 ? "I dag 🎉" : b.days == 1 ? "I morgen" : "om \(b.days) dage")
                        .font(.caption.weight(.semibold)).foregroundStyle(b.days < 7 ? .pink : .secondary)
                }
                .tag(Found.person(m.id))
            }
        }
    }

    private func searchViggo() async {
        found = []
        allPeople = false
        guard q.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searchingViggo = true
        defer { searchingViggo = false }
        let r = (try? await ViggoClient().searchThreads(q)) ?? []
        if !Task.isCancelled { found = r }
    }

    private func remember(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentRaw = ([t] + recent.filter { $0.lowercased() != t.lowercased() }).prefix(6).joined(separator: "\n")
    }
}

// MARK: - what a result shows

struct MacFoundView: View {
    let found: Found
    var body: some View {
        switch found {
        case .person(let id): MacPersonView(id: id)
        case .group(let id): MacGroupView(id: id)
        case .house(let h): MacHouseView(house: h)
        case .bulletin(let b): MacBulletinView(b: b)
        case .thread:
            ContentUnavailableView("Åbnet i Beskeder", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Tråden er åbnet i beskedvinduet."))
        }
    }
}

// MARK: - rows

struct MacPersonRow: View {
    let m: Member
    var size: CGFloat = 30
    var body: some View {
        HStack(spacing: 10) {
            Avatar(url: m.image, size: size, name: m.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                let s = Directory.shared.summary(m)
                if !s.isEmpty { Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(.vertical, 1)
    }
}

extension MemberGroup.Kind {
    var symbol: String {
        switch self {
        case .klasse: "person.3.fill"
        case .underviser: "graduationcap.fill"
        case .linje, .hold: "star.fill"
        case .valgfag: "paintpalette.fill"
        case .idraet: "figure.run"
        case .gruppe: "person.2.circle.fill"
        case .fag: "book.fill"
        case .andet: "square.grid.2x2.fill"
        }
    }
    var color: Color {
        switch self {
        case .klasse: .blue
        case .underviser: .indigo
        case .linje, .hold: .orange
        case .valgfag: .pink
        case .idraet: .green
        case .gruppe: .teal
        case .fag: .purple
        case .andet: .gray
        }
    }
}

struct MacGroupRow: View {
    let g: MemberGroup
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: g.kind.symbol)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(g.kind.color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(g.display).font(.system(size: 13, weight: .medium))
                Text("\(g.kind.title) · \(g.members.count) personer").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MacFoundThreadRow: View {
    let t: MessageThread
    let q: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Avatar(url: t.image, size: 28, name: t.sender)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(t.sender).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(t.when.shortWhen).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(highlight(t.subject)).font(.system(size: 12)).lineLimit(1)
                Text(highlight(t.preview)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        if !q.isEmpty, let r = a.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].inlinePresentationIntent = .stronglyEmphasized
            a[r].foregroundColor = .accentColor
        }
        return a
    }
}

struct MacLessonRow: View {
    let e: ViggoEvent
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(e.subjectColor).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 13, weight: .medium))
                Text([e.start.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Locale(identifier: "da_DK"))) + " " + DateUtil.hm(e.start),
                      e.room.isEmpty ? nil : e.room, e.teachers.isEmpty ? nil : e.teachers.joined(separator: ", ")]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - a person

struct MacPersonView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dir = Directory.shared
    @StateObject private var inbox = Inbox.shared
    @ObservedObject private var premises = Premises.shared
    let id: Int
    @State private var details: MemberDetails?
    @State private var threads: [MessageThread] = []
    @State private var showAllGroups = false

    private var me: Int? { state.profile?.id }

    var body: some View {
        Group {
            if let m = dir.member(id) { content(m) }
            else if dir.loading { ProgressView() }
            else { ContentUnavailableView("Ikke fundet", systemImage: "person.slash", description: Text("Personen er ikke i Viggos adressebog.")) }
        }
        .navigationTitle(dir.member(id)?.name ?? "")
        .task { await dir.load(); await premises.load() }
        .task(id: id) {
            details = await dir.details(id)
            if let m = dir.member(id) {
                let mine = inbox.threads.filter { $0.sender == m.name }
                let r = (try? await ViggoClient().searchThreads(m.name)) ?? []
                var seen = Set(mine.map(\.id))
                threads = mine + r.filter { seen.insert($0.id).inserted }
            }
        }
    }

    private func content(_ m: Member) -> some View {
        Form {
            header(m)
            whereNow(m)
            Section("Info") {
                if !m.className.isEmpty {
                    if let g = dir.groups(of: m.id).filter({ $0.kind == .klasse }).min(by: { $0.members.count < $1.members.count }) {
                        NavigationLink(value: Found.group(g.id)) { info("Klasse", m.className) }
                    } else { info("Klasse", m.className) }
                }
                if let l = dir.line(of: m.id) ?? details?.field("Skolelinje") {
                    if let g = dir.groups(of: m.id).first(where: { $0.kind == .linje }) {
                        NavigationLink(value: Found.group(g.id)) { info("Linje", l) }
                    } else { info("Linje", l) }
                }
                if !m.houseRoom.isEmpty {
                    if !m.house.isEmpty {
                        NavigationLink(value: Found.house(m.house)) { info("Værelse", m.houseRoom) }
                    } else { info("Værelse", m.houseRoom) }
                }
                if !m.studentNo.isEmpty { info("Elevnummer", m.studentNo) }
                if !m.initials.isEmpty { info("Initialer", m.initials) }
                if let b = m.birthday {
                    info("Fødselsdag", b.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "da_DK"))))
                    if let n = m.nextBirthday {
                        info("Fylder \(n.turns)", n.days == 0 ? "I dag 🎉" : n.days == 1 ? "I morgen" : "Om \(n.days) dage")
                    }
                }
                if !m.mobile.isEmpty { phoneRow("Mobil", m.mobile) }
                if !m.phone.isEmpty { phoneRow("Telefon", m.phone) }
                if let mail = details?.field("Email") {
                    info("Email", mail).contextMenu {
                        Button("Skriv mail") { if let u = URL(string: "mailto:\(mail)") { NSWorkspace.shared.open(u) } }
                        Button("Kopiér") { copy(mail) }
                    }
                }
                if let a = details?.address.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces)) }).filter({ !$0.isEmpty }), !a.isEmpty {
                    let text = a.joined(separator: ", ")
                    info("Bor", text).contextMenu {
                        Button("Vis i Kort") {
                            let s = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let u = URL(string: "maps://?q=\(s)") { NSWorkspace.shared.open(u) }
                        }
                        Button("Kopiér") { copy(text) }
                    }
                }
                ForEach(extraFields(m), id: \.0) { f in info(f.0, f.1) }
            }

            people("Bor med", dir.roommates(of: m))
            people("Kontaktlærer", dir.contactTeachers(of: m.id))
            familySection(m)
            people(m.kind == .parent ? "Børn" : "Børn på skolen", dir.children(of: m.id))
            people("Kontaktelever", dir.contactStudents(of: m.id))
            lessonsWith(m)
            groupsSection(m)

            if !threads.isEmpty {
                Section("Beskeder") {
                    ForEach(threads.prefix(10)) { t in
                        Button { state.openMessages(thread: t.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.subject).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text("\(t.sender) · \(t.when.shortWhen)").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func header(_ m: Member) -> some View {
        Section {
            VStack(spacing: 8) {
                Avatar(url: m.imageBig ?? m.image, size: 96, name: m.name)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .onTapGesture { if let u = m.imageBig ?? m.image { NSWorkspace.shared.open(u) } }
                    .help("Åbn billedet")
                Text(m.name).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center).textSelection(.enabled)
                Text(dir.summary(m)).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if m.id != me {
                    HStack(spacing: 10) {
                        Button { state.compose(to: [Person(id: m.id, name: m.name, image: m.image, info: "")]) } label: {
                            Label("Besked", systemImage: "bubble.left.fill")
                        }
                        if !m.anyPhone.isEmpty {
                            Button { open("tel:\(m.anyPhone)") } label: { Label("Ring", systemImage: "phone.fill") }
                            Button { open("sms:\(m.anyPhone)") } label: { Label("SMS", systemImage: "message.fill") }
                        }
                    }
                    .controlSize(.large)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    /// Which room someone is in right now, from Viggo's room overview.
    @ViewBuilder private func whereNow(_ m: Member) -> some View {
        let now = state.tick
        let w = premises.whereNow(m.id, at: now)
        let canAdd = m.kind == .student && m.id != me && !state.isFriend(m.id)
        if m.kind == .student || m.kind == .staff, !premises.bookings.isEmpty || canAdd {
            Section {
                if !premises.bookings.isEmpty {
                    if let c = w.now {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title.replacingOccurrences(of: "^\\d{1,2}[.:]\\d{2}\\s*-\\s*\\d{1,2}[.:]\\d{2}\\s+", with: "", options: .regularExpression))
                                    .font(.system(size: 13, weight: .semibold))
                                Text([c.room.isEmpty ? nil : c.room, "til \(untilText(c.start, c.end))"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "mappin.circle.fill").foregroundStyle(.orange) }
                    } else {
                        Label(w.next.map { "Fri til \(DateUtil.hm($0.start))" } ?? "Ingen flere timer i dag",
                              systemImage: "cup.and.saucer.fill").foregroundStyle(.green)
                    }
                    if let n = w.next {
                        Label("Næste: \(n.title) kl. \(DateUtil.hm(n.start))\(n.room.isEmpty ? "" : " i \(n.room)")", systemImage: "arrow.forward.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                if canAdd {
                    Button { Task { await state.addFriend(member: m) } } label: { Label("Tilføj som ven", systemImage: "person.badge.plus") }
                }
            } header: { Text("Lige nu") } footer: {
                if canAdd { Text("Uden login: Viggo+ finder \(m.firstName)s timer i Viggos lokaleoversigt.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).textSelection(.enabled).multilineTextAlignment(.trailing) }
    }

    private func phoneRow(_ label: String, _ number: String) -> some View {
        info(label, number).contextMenu {
            Button("Ring") { open("tel:\(number)") }
            Button("Send SMS") { open("sms:\(number)") }
            Button("Kopiér") { copy(number) }
        }
    }

    private func open(_ s: String) { if let u = URL(string: s.replacingOccurrences(of: " ", with: "")) { NSWorkspace.shared.open(u) } }
    private func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

    private func extraFields(_ m: Member) -> [(String, String)] {
        let known = ["fødselsdag", "mobil", "telefon", "klasse", "skolelinje", "elevnummer", "hus", "værelse", "initialer", "email"]
        return (details?.fields ?? []).filter { f in !known.contains { f.0.lowercased().hasPrefix($0) } }
    }

    @ViewBuilder private func people(_ title: String, _ list: [Member]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { p in NavigationLink(value: Found.person(p.id)) { MacPersonRow(m: p, size: 26) } }
            }
        }
    }

    @ViewBuilder private func familySection(_ m: Member) -> some View {
        let fam = dir.family(of: m.id)
        if !fam.isEmpty {
            Section("Familie") {
                ForEach(fam, id: \.1.id) { rel, p in
                    NavigationLink(value: Found.person(p.id)) {
                        HStack {
                            MacPersonRow(m: p, size: 26)
                            Spacer()
                            Text(rel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// For a teacher: your next lessons with them.
    @ViewBuilder private func lessonsWith(_ m: Member) -> some View {
        if m.kind == .staff {
            let now = Date()
            let keys = [m.name.lowercased(), m.initials.lowercased()].filter { !$0.isEmpty }
            let list = state.events.filter { e in e.end > now && e.teachers.contains { t in keys.contains(t.lowercased()) } }
                .sorted { $0.start < $1.start }.prefix(5)
            if !list.isEmpty {
                Section("Dine næste timer med \(m.firstName)") {
                    ForEach(Array(list)) { e in
                        Button { state.openLesson(e) } label: { MacLessonRow(e: e).frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Every group the person is in. The ones you are in too are marked "Fælles" and come first.
    @ViewBuilder private func groupsSection(_ m: Member) -> some View {
        let all = dir.groups(of: m.id)
        if !all.isEmpty {
            let mine = (me != nil && me != m.id) ? Set(dir.shared(me!, m.id).map(\.id)) : []
            let sorted = all.filter { mine.contains($0.id) } + all.filter { !mine.contains($0.id) }
            let shown = showAllGroups ? sorted : sorted.filter { mine.contains($0.id) || ($0.kind != .fag && $0.kind != .andet) }
            Section {
                ForEach(shown) { g in
                    NavigationLink(value: Found.group(g.id)) {
                        HStack {
                            MacGroupRow(g: g)
                            Spacer(minLength: 6)
                            if mine.contains(g.id) {
                                Label("Fælles", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.14)))
                            }
                        }
                    }
                }
                if shown.count < sorted.count || showAllGroups {
                    Button(showAllGroups ? "Vis færre" : "Vis alle \(all.count) grupper") { withAnimation(.viggo) { showAllGroups.toggle() } }
                }
            } header: {
                Text(mine.isEmpty ? "Grupper" : "Grupper · \(mine.count) fælles med dig")
            }
        }
    }
}

// MARK: - a group, a house, a post

struct MacGroupView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dir = Directory.shared
    let id: Int
    @State private var filter = ""

    var body: some View {
        Group {
            if let g = dir.group(id) { content(g) } else { ProgressView() }
        }
        .task { await dir.load() }
    }

    private func content(_ g: MemberGroup) -> some View {
        let all = g.members.compactMap { dir.member($0) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let f = Directory.normalize(filter)
        let shown = f.isEmpty ? all : all.filter { "\($0.name) \(dir.summary($0))".lowercased().contains(f) }
        let kinds: [(String, Member.Kind)] = [("Elever", .student), ("Ansatte", .staff), ("Forældre", .parent), ("Andre", .other)]
        return Form {
            Section {
                HStack(spacing: 12) {
                    MacGroupRow(g: g)
                    Spacer()
                    Button { state.compose(to: all.map { Person(id: $0.id, name: $0.name, image: $0.image, info: "") }) } label: {
                        Label("Skriv til gruppen", systemImage: "square.and.pencil")
                    }
                }
                if !g.note.isEmpty, g.kind != .klasse { Text(g.note).font(.caption).foregroundStyle(.secondary) }
                TextField("Find i \(g.display)", text: $filter)
            }
            ForEach(kinds, id: \.0) { title, k in
                let list = shown.filter { $0.kind == k }
                if !list.isEmpty {
                    Section("\(title) (\(list.count))") {
                        ForEach(list) { m in NavigationLink(value: Found.person(m.id)) { MacPersonRow(m: m, size: 26) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(g.display)
    }
}

struct MacHouseView: View {
    @StateObject private var dir = Directory.shared
    let house: String

    var body: some View {
        let people = dir.members.filter { $0.kind == .student && $0.house == house }
        let rooms = Dictionary(grouping: people, by: \.room)
        let keys = rooms.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        Form {
            ForEach(keys, id: \.self) { r in
                Section(r.isEmpty ? "Uden værelse" : "Værelse \(r)") {
                    ForEach(rooms[r]!.sorted { $0.name < $1.name }) { p in
                        NavigationLink(value: Found.person(p.id)) { MacPersonRow(m: p, size: 26) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(house)
        .overlay { if people.isEmpty { ContentUnavailableView("Ingen", systemImage: "house", description: Text("Ingen elever bor i \(house).")) } }
        .task { await dir.load() }
    }
}

struct MacBulletinView: View {
    let b: Bulletin
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Avatar(url: b.authorImage, size: 36, name: b.author)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.author).font(.system(size: 13, weight: .semibold))
                        Text("\(b.board) · \(b.when)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text(b.title).font(.system(size: 20, weight: .bold)).textSelection(.enabled)
                Text(b.body.isEmpty ? b.text : b.body).font(.system(size: 13)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(b.links, id: \.self) { u in
                    Link(destination: u) { Label(u.host ?? u.absoluteString, systemImage: "link") }
                }
                HStack { Spacer(); Button("Åbn opslagstavlen i Viggo") { AppState.shared.openViggo() } }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(b.title)
    }
}
