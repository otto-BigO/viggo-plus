import SwiftUI

/// Where a search result leads.
enum Found: Hashable {
    case person(Int)
    case group(Int)
    case thread(Int)
    case bulletin(Bulletin)
}

// MARK: - Søg

/// One search for everything: people (by name, class, room, house, line, initials), groups,
/// messages (Viggo searches the text of them too), the week's lessons, homework and posts.
struct SearchScreen: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dir = Directory.shared
    @StateObject private var inbox = Inbox.shared
    @State private var query = ProcessInfo.processInfo.environment["VIGGO_SEARCH"] ?? ""
    @State private var path: [Found] = []
    @State private var found: [MessageThread] = []
    @State private var searchingViggo = false
    @State private var allPeople = false
    @AppStorage("recentSearches") private var recentRaw = ""
    @Environment(\.dismiss) private var dismiss

    private var q: String { Directory.normalize(query) }
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var people: [Member] { dir.search(query) }
    private var groups: [MemberGroup] { Array(dir.searchGroups(query).prefix(6)) }
    private var threads: [MessageThread] {
        guard !q.isEmpty else { return [] }
        let local = inbox.threads.filter { "\($0.sender) \($0.subject) \($0.preview)".lowercased().contains(q) }
        var seen = Set(local.map(\.id))
        return local + found.filter { seen.insert($0.id).inserted }
    }
    private var lessons: [ViggoEvent] {
        guard q.count >= 2 else { return [] }
        let now = Date()
        return state.events.filter { e in
            e.end > now && (e.kind == .lesson || e.kind == .event) &&
            "\(e.title) \(e.rawName) \(e.room) \(e.teachers.joined(separator: " ")) \(e.notes)".lowercased().contains(q)
        }
        .sorted { $0.start < $1.start }.prefix(6).map { $0 }
    }
    private var homework: [Homework] {
        guard q.count >= 2 else { return [] }
        return state.homework.filter { "\($0.title) \($0.group) \($0.notes) \($0.author)".lowercased().contains(q) }
            .sorted { $0.due > $1.due }.prefix(5).map { $0 }
    }
    private var posts: [Bulletin] {
        guard q.count >= 2 else { return [] }
        return state.bulletins.filter { "\($0.title) \($0.author) \($0.body) \($0.text)".lowercased().contains(q) }.prefix(5).map { $0 }
    }
    private var nothing: Bool {
        people.isEmpty && groups.isEmpty && threads.isEmpty && lessons.isEmpty && homework.isEmpty && posts.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if q.isEmpty { suggestions } else { results }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if !q.isEmpty, nothing, !searchingViggo, !dir.loading { ContentUnavailableView.search(text: query) }
                else if dir.members.isEmpty, dir.loading { ProgressView("Henter personer") }
            }
            .navigationTitle("Søg")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Navn, klasse, værelse, besked…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { remember(query) }
            .task(id: q) { await searchViggo() }
            .task { await dir.load(); if inbox.threads.isEmpty { await inbox.load() } }
            .refreshable { await dir.load(force: true) }
            .navigationDestination(for: Found.self) { FoundScreen(found: $0) }
            .animation(.viggo, value: q)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Luk") { dismiss() } }
            }
        }
    }

    // MARK: before typing

    @ViewBuilder private var suggestions: some View {
        if let e = dir.error {
            Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { r in
                    Button { query = r } label: { Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary) }
                }
                Button("Ryd seneste", role: .destructive) { recentRaw = "" }.font(.subheadline)
            } header: { Text("Seneste") }
        }
        if let me = state.profile.flatMap({ dir.member($0.id) }) {
            Section {
                let mine = dir.groups(of: me.id).filter { [.klasse, .linje, .gruppe].contains($0.kind) }
                ForEach(mine) { g in
                    NavigationLink(value: Found.group(g.id)) { GroupRow(g: g) }
                }
                if !me.room.isEmpty {
                    NavigationLink(value: Found.person(me.id)) {
                        Label("Dig og værelse \(me.room)", systemImage: "bed.double.fill")
                    }
                }
            } header: { Text("Dine") }
        }
        Section {
            ForEach(["10.4", "Musiklinjen", "D17", "Valgfag", "Fødselsdag"], id: \.self) { s in
                Button { query = s } label: { Label(s, systemImage: "magnifyingglass").foregroundStyle(.primary) }
            }
        } header: { Text("Prøv fx") } footer: {
            Text("Søg efter navn, klasse (10.4), værelse (D17), hus, linje, valgfag, initialer eller elevnummer. Beskeder søges i hele teksten.")
        }
    }

    // MARK: results

    @ViewBuilder private var results: some View {
        if q == "fødselsdag" || q == "fødselsdage" {
            birthdays
        }
        if !people.isEmpty {
            Section {
                ForEach(allPeople ? people : Array(people.prefix(8))) { m in
                    NavigationLink(value: Found.person(m.id)) { PersonRow(m: m) }
                }
                if people.count > 8 {
                    Button(allPeople ? "Vis færre" : "Vis alle \(people.count)") { withAnimation(.viggo) { allPeople.toggle() } }
                }
            } header: { Text("Personer") }
        }
        if !groups.isEmpty {
            Section("Grupper") {
                ForEach(groups) { g in NavigationLink(value: Found.group(g.id)) { GroupRow(g: g) } }
            }
        }
        if !threads.isEmpty || searchingViggo {
            Section {
                ForEach(threads.prefix(20)) { t in
                    NavigationLink(value: Found.thread(t.id)) { FoundThreadRow(t: t, q: q) }
                }
            } header: {
                HStack { Text("Beskeder"); if searchingViggo { ProgressView().controlSize(.mini) } }
            }
        }
        if !lessons.isEmpty {
            Section("Skema") {
                ForEach(lessons) { e in
                    Button { state.shownLesson = e } label: { LessonRow(e: e) }.foregroundStyle(.primary)
                }
            }
        }
        if !homework.isEmpty {
            Section("Lektier") {
                ForEach(homework) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title).font(.body.weight(.medium))
                        Text("\(h.group) · \(h.due.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "da_DK"))))").font(.caption).foregroundStyle(.secondary)
                        if !h.notes.isEmpty { Text(h.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
        }
        if !posts.isEmpty {
            Section("Opslag") {
                ForEach(posts) { b in
                    NavigationLink(value: Found.bulletin(b)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title).font(.body.weight(.medium)).lineLimit(1)
                            Text("\(b.author) · \(b.when)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
                NavigationLink(value: Found.person(m.id)) {
                    HStack {
                        PersonRow(m: m)
                        Spacer()
                        Text(b.days == 0 ? "I dag 🎉" : b.days == 1 ? "I morgen" : "om \(b.days) dage")
                            .font(.caption.weight(.semibold)).foregroundStyle(b.days < 7 ? .pink : .secondary)
                    }
                }
            }
        }
    }

    private func searchViggo() async {
        found = []
        allPeople = false
        guard q.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))         // wait until typing pauses
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

/// The magnifier that opens Søg.
struct SearchButton: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Button { Haptic.tap(); state.showSearch = true } label: { Image(systemName: "magnifyingglass") }
            .accessibilityLabel("Søg i alt")
    }
}

/// The screen for a result, also used from other screens (a name in a message, a teacher on a lesson).
struct FoundScreen: View {
    let found: Found
    var body: some View {
        switch found {
        case .person(let id): PersonScreen(id: id)
        case .group(let id): GroupScreen(id: id)
        case .thread(let id): ThreadScreen(id: id)
        case .bulletin(let b): BulletinScreen(b: b)
        }
    }
}

// MARK: - Rows

struct PersonRow: View {
    @StateObject private var dir = Directory.shared
    let m: Member
    var size: CGFloat = 44
    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: m.image, size: size, name: m.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                let s = dir.summary(m)
                if !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct GroupRow: View {
    let g: MemberGroup
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: GroupRow.symbol(g.kind))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GroupRow.color(g.kind).gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(g.display).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text("\(g.kind.title) · \(g.members.count) personer").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func symbol(_ k: MemberGroup.Kind) -> String {
        switch k {
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
    static func color(_ k: MemberGroup.Kind) -> Color {
        switch k {
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

private struct FoundThreadRow: View {
    let t: MessageThread
    let q: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: t.image, size: 36, name: t.sender)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(t.sender).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(t.when.shortWhen).font(.caption).foregroundStyle(.secondary)
                }
                Text(highlight(t.subject)).font(.subheadline).lineLimit(1)
                Text(highlight(t.preview)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        if !q.isEmpty, let r = a.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].font = .body.weight(.bold)
            a[r].foregroundColor = .accentColor
        }
        return a
    }
}

private struct LessonRow: View {
    let e: ViggoEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.title).font(.body.weight(.medium))
            Text([e.start.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Locale(identifier: "da_DK"))) + " " + DateUtil.hm(e.start),
                  e.room.isEmpty ? nil : e.room, e.teachers.isEmpty ? nil : e.teachers.joined(separator: ", ")]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: - A person

struct PersonScreen: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dir = Directory.shared
    @StateObject private var inbox = Inbox.shared
    @Environment(\.openURL) private var openURL
    let id: Int
    @State private var details: MemberDetails?
    @State private var threads: [MessageThread] = []
    @State private var composing = false
    @State private var showAllGroups = false

    private var me: Int? { state.profile?.id }

    var body: some View {
        Group {
            if let m = dir.member(id) { content(m) }
            else if dir.loading { ProgressView() }
            else { ContentUnavailableView("Ikke fundet", systemImage: "person.slash", description: Text("Personen er ikke i Viggos adressebog.")) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await dir.load() }
        .task(id: id) {
            details = await dir.details(id)
            if let m = dir.member(id) {
                let mine = inbox.threads.filter { $0.sender == m.name }
                let r = (try? await ViggoClient().searchThreads(m.name)) ?? []
                var seen = Set(mine.map(\.id))
                threads = mine + r.filter { seen.insert($0.id).inserted }
            }
        }
        .sheet(isPresented: $composing) {
            if let m = dir.member(id) { ComposeScreen(to: [Person(id: m.id, name: m.name, image: m.image, info: "")]) }
        }
    }

    private func content(_ m: Member) -> some View {
        List {
            header(m)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            if let f = state.friends.first(where: { $0.viggoID == m.id }) {
                let (text, busy) = state.friendStatus(f, now: Date())
                Section("Lige nu") {
                    Label(text, systemImage: busy ? "clock.fill" : "cup.and.saucer.fill").foregroundStyle(busy ? .orange : .green)
                }
            }

            Section("Info") {
                if !m.className.isEmpty { info("Klasse", m.className, "person.3.fill") }
                if let l = dir.line(of: m.id) ?? details?.field("Skolelinje") { info("Linje", l, "star.fill") }
                if !m.house.isEmpty { info("Hus", m.house, "house.fill") }
                if !m.room.isEmpty { info("Værelse", m.room, "bed.double.fill") }
                if !m.studentNo.isEmpty { info("Elevnummer", m.studentNo, "number") }
                if !m.initials.isEmpty { info("Initialer", m.initials, "textformat") }
                if let b = m.birthday {
                    info("Fødselsdag", b.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "da_DK"))), "gift.fill")
                    if let n = m.nextBirthday {
                        info("Fylder \(n.turns)", n.days == 0 ? "I dag 🎉" : n.days == 1 ? "I morgen" : "Om \(n.days) dage", "calendar")
                    }
                }
                if !m.mobile.isEmpty { phoneRow("Mobil", m.mobile) }
                if !m.phone.isEmpty { phoneRow("Telefon", m.phone) }
                if let mail = details?.field("Email") {
                    Button { if let u = URL(string: "mailto:\(mail)") { openURL(u) } } label: { info("Email", mail, "envelope.fill") }
                }
                if let a = details?.address, !a.isEmpty {
                    Button {
                        let s = a.joined(separator: ", ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let u = URL(string: "maps://?q=\(s)") { openURL(u) }
                    } label: { info("Bor", a.joined(separator: ", "), "mappin.and.ellipse") }
                }
                // Anything else Viggo's profile page has.
                ForEach(extraFields(m), id: \.0) { f in info(f.0, f.1, "info.circle") }
            }

            people("Bor med", dir.roommates(of: m))
            people("Kontaktlærer", dir.contactTeachers(of: m.id))
            familySection(m)
            people(m.kind == .parent ? "Børn" : "Børn på skolen", dir.children(of: m.id))
            people("Kontaktelever", dir.contactStudents(of: m.id))

            if let me, me != m.id {
                let shared = dir.shared(me, m.id).filter { $0.kind != .andet }
                if !shared.isEmpty {
                    Section {
                        Text(shared.map(\.display).joined(separator: ", ")).font(.subheadline)
                    } header: { Text("Fælles med dig (\(shared.count))") }
                }
            }

            lessonsWith(m)
            groupsSection(m)

            if !threads.isEmpty {
                Section("Beskeder") {
                    ForEach(threads.prefix(10)) { t in
                        NavigationLink(value: Found.thread(t.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.subject).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("\(t.sender) · \(t.when.shortWhen)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func header(_ m: Member) -> some View {
        VStack(spacing: 10) {
            AsyncImage(url: m.imageBig ?? m.image) { img in img.resizable().scaledToFill() } placeholder: {
                Avatar(url: m.image, size: 120, name: m.name)
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            Text(m.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text(dir.summary(m)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                action("Besked", "bubble.left.fill") { composing = true }
                if !m.anyPhone.isEmpty {
                    action("Ring", "phone.fill") { openURL(URL(string: "tel:\(m.anyPhone)")!) }
                    action("SMS", "message.fill") { openURL(URL(string: "sms:\(m.anyPhone)")!) }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); run() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption.weight(.medium))
            }
            .frame(width: 76, height: 56)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(PressScale())
    }

    private func info(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(.primary)
        }
        .font(.subheadline)
        .textSelection(.enabled)
    }

    private func phoneRow(_ label: String, _ number: String) -> some View {
        Button { openURL(URL(string: "tel:\(number)")!) } label: { info(label, number, "phone.fill") }
            .contextMenu {
                Button("Kopiér", systemImage: "doc.on.doc") { UIPasteboard.general.string = number }
                Button("Send SMS", systemImage: "message") { openURL(URL(string: "sms:\(number)")!) }
            }
    }

    /// Fields from the profile page that the address book doesn't already cover.
    private func extraFields(_ m: Member) -> [(String, String)] {
        let known = ["fødselsdag", "mobil", "telefon", "klasse", "skolelinje", "elevnummer", "hus", "værelse", "initialer", "email"]
        return (details?.fields ?? []).filter { f in !known.contains { f.0.lowercased().hasPrefix($0) } }
    }

    @ViewBuilder private func people(_ title: String, _ list: [Member]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { p in NavigationLink(value: Found.person(p.id)) { PersonRow(m: p, size: 36) } }
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
                            PersonRow(m: p, size: 36)
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
                        Button { state.shownLesson = e } label: { LessonRow(e: e) }.foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func groupsSection(_ m: Member) -> some View {
        let all = dir.groups(of: m.id)
        if !all.isEmpty {
            let shown = showAllGroups ? all : all.filter { $0.kind != .fag && $0.kind != .andet }
            Section {
                ForEach(shown) { g in NavigationLink(value: Found.group(g.id)) { GroupRow(g: g) } }
                if shown.count < all.count || showAllGroups {
                    Button(showAllGroups ? "Vis færre" : "Vis alle \(all.count) grupper") { withAnimation(.viggo) { showAllGroups.toggle() } }
                }
            } header: { Text("Grupper") }
        }
    }
}

// MARK: - A group

struct GroupScreen: View {
    @StateObject private var dir = Directory.shared
    let id: Int
    @State private var filter = ""
    @State private var composing = false

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
        return List {
            Section {
                HStack(spacing: 14) {
                    GroupRow(g: g)
                    Spacer()
                    Button { Haptic.tap(); composing = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Skriv til gruppen")
                }
                if !g.note.isEmpty, g.kind != .klasse { Text(g.note).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(kinds, id: \.0) { title, k in
                let list = shown.filter { $0.kind == k }
                if !list.isEmpty {
                    Section("\(title) (\(list.count))") {
                        ForEach(list) { m in NavigationLink(value: Found.person(m.id)) { PersonRow(m: m, size: 36) } }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(g.display)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Find i \(g.display)")
        .sheet(isPresented: $composing) {
            ComposeScreen(to: all.map { Person(id: $0.id, name: $0.name, image: $0.image, info: "") })
        }
    }
}
