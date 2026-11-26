import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Søg on the Mac: one search for people (name, class, room, house, line, initials), groups,
/// messages (Viggo searches the text of them too), the week's lessons, homework and posts. The
/// results are on the left, the person or group on the right. Same search as on the iPhone.
struct SearchWindow: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dir = Directory.shared
    @StateObject private var inbox = Inbox.shared
    @State private var query = ProcessInfo.processInfo.environment["VIGGO_SEARCH"] ?? ""
    @State private var selection: Found?
    @State private var nav = BrowseHistory()
    /// Links on a page ask the stack to push; the page is swapped in place instead (like a browser),
    /// so the split view resetting the stack when the list selection changes can't undo a step.
    private var path: Binding<[Found]> {
        Binding(get: { [] }, set: { if let f = $0.last { go(to: f) } })
    }
    /// Which way the page slides: in from the right going forward, from the left going back.
    @State private var goingBack = false
    private func go(to f: Found) {
        guard f != nav.current else { return }
        goingBack = false
        withAnimation(.viggo) { nav.go(to: f) }
    }
    private func back() { guard nav.canBack else { return }; goingBack = true; withAnimation(.viggo) { nav.back() } }
    private func forward() { guard nav.canForward else { return }; goingBack = false; withAnimation(.viggo) { nav.forward() } }
    /// Keep the sidebar highlight on the page you are on.
    private func syncSelection() { if selection != nav.current { selection = nav.current } }
    @State private var found: [MessageThread] = []
    @State private var searchingViggo = false
    /// The words `found` is for.
    @State private var searchedFor: String?
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
    /// Words inside read messages and their PDFs.
    @State private var textHits: [RosterStore.TextHit] = []
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var threads: [MessageThread] {
        var seen = Set(localThreads.map(\.id))
        return localThreads + found.filter { seen.insert($0.id).inserted }
    }
    private var nothing: Bool {
        people.isEmpty && groups.isEmpty && threads.isEmpty && lessons.isEmpty && homework.isEmpty && posts.isEmpty && textHits.isEmpty
    }

    private func compute() {
        people = dir.search(q)
        groups = Array(dir.searchGroups(q).prefix(6))
        guard !q.isEmpty else { localThreads = []; lessons = []; homework = []; posts = []; textHits = []; return }
        localThreads = inbox.threads.filter { "\($0.sender) \($0.subject) \($0.preview)".lowercased().contains(q) }
        textHits = RosterStore.shared.search(q, limit: 15)
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
                else if dir.members.isEmpty, dir.loading {
                    SkeletonRows(count: 8, avatar: 30).padding(.horizontal, 14).frame(maxHeight: .infinity, alignment: .top)
                }
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
            NavigationStack(path: path) {
                ZStack {
                    if let s = nav.current {
                        MacFoundView(found: s).id(s)
                            .transition(.asymmetric(insertion: .move(edge: goingBack ? .leading : .trailing).combined(with: .opacity),
                                                    removal: .opacity))
                    } else {
                        ContentUnavailableView("Søg i Viggo", systemImage: "magnifyingglass",
                                               description: Text("Find elever, lærere, klasser, værelser, beskeder og timer."))
                    }
                }
                .clipped()
                .navigationDestination(for: Found.self) { MacFoundView(found: $0) }
            }
        }
        // The panel's search asked for a search or a page in the big window.
        .onReceive(SearchBridge.shared.$request) { r in
            guard let r else { return }
            if let q = r.query { query = q }
            if let f = r.found { selection = f }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchTest)) { n in
            // --feature-test: move around like a user would, so the hook can read the window title.
            switch n.object as? String {
            case "back": back()
            case "forward": forward()
            case "link": if let f = n.userInfo?["found"] as? Found { path.wrappedValue = [f] }
            default: if let f = n.userInfo?["found"] as? Found { selection = f }
            }
            print("[nav] \(nav.pos + 1)/\(nav.items.count), tilbage \(nav.canBack), frem \(nav.canForward)"); fflush(stdout)
        }
        .onChange(of: nav.current) { syncSelection() }
        .onChange(of: selection) {
            guard let s = selection else { return }
            if case .thread(let id) = s { state.openMessages(thread: id); return }
            go(to: s)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .disabled(!nav.canBack).help("Tilbage (⌘[)").keyboardShortcut("[", modifiers: .command)
                Button(action: forward) { Image(systemName: "chevron.right") }
                    .disabled(!nav.canForward).help("Frem (⌘])").keyboardShortcut("]", modifiers: .command)
            }
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
            Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Fomo.warn)
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
                        .buttonStyle(.plain).foregroundStyle(Fomo.accent)
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
        if !textHits.isEmpty {
            Section("I beskeder og filer") {
                ForEach(textHits) { h in
                    Button { state.openMessages(thread: h.thread) } label: { TextHitRow(h: h, q: q) }.buttonStyle(.plain)
                }
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
                            Text(h.title).font(.system(size: 13, weight: .medium, design: Fomo.design))
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
                        Text(b.title).font(.system(size: 13, weight: .medium, design: Fomo.design)).lineLimit(1)
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
        // Coming back from a page runs this again for the same words: keep what we found.
        guard q != searchedFor else { return }
        found = []
        allPeople = false
        guard q.count >= 3 else { searchedFor = q; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searchingViggo = true
        defer { searchingViggo = false }
        let r = (try? await ViggoClient().searchThreads(q)) ?? []
        if !Task.isCancelled { found = r; searchedFor = q }
    }

    private func remember(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentRaw = ([t] + recent.filter { $0.lowercased() != t.lowercased() }).prefix(6).joined(separator: "\n")
    }
}

extension Notification.Name { static let searchTest = Notification.Name("ViggoSearchTest") }

/// Every page you have looked at in Søg, like a browser. `pos` is the one on screen. Back and
/// forward move `pos`; opening something new (from the list or a link on a page) cuts off what
/// was ahead of it.
struct BrowseHistory: Equatable {
    private(set) var items: [Found] = []
    private(set) var pos = 0
    static let limit = 60

    var current: Found? { items.indices.contains(pos) ? items[pos] : nil }
    var canBack: Bool { pos > 0 }
    var canForward: Bool { pos < items.count - 1 }

    mutating func go(to f: Found) {
        if f == current { return }
        items = Array((items.prefix(pos + 1) + [f]).suffix(Self.limit))
        pos = items.count - 1
    }
    @discardableResult mutating func back() -> Bool { guard canBack else { return false }; pos -= 1; return true }
    @discardableResult mutating func forward() -> Bool { guard canForward else { return false }; pos += 1; return true }

    /// Checks the browser rules on fake pages. Run by --feature-test.
    static func selfTest() -> [String] {
        var bad: [String] = []
        var h = BrowseHistory()
        func want(_ ok: Bool, _ what: String) { if !ok { bad.append(what) } }
        want(!h.back() && !h.forward() && h.current == nil, "tom historik")
        h.go(to: .person(1)); h.go(to: .person(2)); h.go(to: .group(3))
        want(h.current == .group(3) && h.items.count == 3, "tre sider")
        want(h.back() && h.current == .person(2) && h.canForward, "tilbage")
        want(h.forward() && h.current == .group(3) && !h.canForward, "frem")
        h.back(); h.back()
        want(h.current == .person(1) && !h.canBack, "tilbage til start")
        h.go(to: .house("A"))
        want(h.items == [.person(1), .house("A")] && !h.canForward, "ny side fjerner frem")
        h.go(to: .house("A"))
        want(h.items.count == 2, "samme side igen tæller ikke")
        for i in 0..<100 { h.go(to: .person(100 + i)) }
        want(h.items.count == limit && h.current == .person(199), "loft på historikken")
        return bad
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
                Text(m.name).font(.system(size: 13, weight: .medium, design: Fomo.design)).lineLimit(1)
                let s = Directory.shared.summary(m)
                if !s.isEmpty { Text(s).font(.system(size: 11, design: Fomo.design)).foregroundStyle(.secondary).lineLimit(1) }
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
                .font(.system(size: 12, weight: .semibold, design: Fomo.design)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(g.kind.color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(g.display).font(.system(size: 13, weight: .medium, design: Fomo.design))
                Text("\(g.kind.title) · \(g.members.count) personer").font(.system(size: 11, design: Fomo.design)).foregroundStyle(.secondary)
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
                    Text(t.sender).font(.system(size: 12, weight: .semibold, design: Fomo.design)).lineLimit(1)
                    Spacer()
                    Text(t.when.shortWhen).font(.system(size: 10, design: Fomo.design)).foregroundStyle(.secondary)
                }
                Text(highlight(t.subject)).font(.system(size: 12, design: Fomo.design)).lineLimit(1)
                Text(highlight(t.preview)).font(.system(size: 11, design: Fomo.design)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        if !q.isEmpty, let r = a.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].inlinePresentationIntent = .stronglyEmphasized
            a[r].foregroundColor = Fomo.accent
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
                Text(e.title).font(.system(size: 13, weight: .medium, design: Fomo.design))
                Text([e.start.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Locale(identifier: "da_DK"))) + " " + DateUtil.hm(e.start),
                      e.room.isEmpty ? nil : e.room, e.teachers.isEmpty ? nil : e.teachers.joined(separator: ", ")]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, design: Fomo.design)).foregroundStyle(.secondary).lineLimit(1)
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
    @State private var zoom = false

    private var me: Int? { state.profile?.id }

    init(id: Int) {
        self.id = id
        // A page you have seen before is drawn complete at once instead of filling in piece by piece.
        _details = State(initialValue: Directory.shared.cachedDetails(id))
        _threads = State(initialValue: Directory.shared.member(id).map { PersonThreads.shared.cached(for: $0) } ?? [])
    }

    var body: some View {
        Group {
            if let m = dir.member(id) { content(m) }
            else if dir.loading { SkeletonRows(count: 4, avatar: 64).padding(24).frame(maxHeight: .infinity, alignment: .top) }
            else { ContentUnavailableView("Ikke fundet", systemImage: "person.slash", description: Text("Personen er ikke i Viggos adressebog.")) }
        }
        .overlay {
            if zoom, let m = dir.member(id) {
                MacPhotoViewer(url: m.imageBig ?? m.image, fallback: m.image, name: m.name) {
                    withAnimation(.easeOut(duration: 0.2)) { zoom = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onChange(of: id) { zoom = false }
        .navigationTitle(dir.member(id)?.name ?? "")
        .task { await dir.load(); await premises.load() }
        .task(id: id) { await loadPerson() }
    }

    /// Details and messages at the same time, each shown as soon as it is there.
    private func loadPerson() async {
        details = dir.cachedDetails(id)
        guard let m = dir.member(id) else { details = await dir.details(id); return }
        threads = PersonThreads.shared.cached(for: m)
        async let d = dir.details(id)
        async let t = PersonThreads.shared.threads(for: m)
        let (dd, tt) = await (d, t)
        withAnimation(.viggo) {
            if details == nil { details = dd }
            if tt.map(\.id) != threads.map(\.id) { threads = tt }
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
                                Text(t.subject).font(.system(size: 13, weight: .medium, design: Fomo.design)).lineLimit(1)
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
                // The small cached picture (240 px) is sharp at this size and needs no download.
                Avatar(url: m.image ?? m.imageBig, size: 96, name: m.name)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .onTapGesture { if m.imageBig ?? m.image != nil { withAnimation(.spring(duration: 0.3)) { zoom = true } } }
                    .help(m.imageBig ?? m.image == nil ? "" : "Vis billedet stort")
                Text(m.name).font(.system(size: 20, weight: .bold, design: Fomo.design)).multilineTextAlignment(.center).textSelection(.enabled)
                Text(dir.summary(m)).font(.system(size: 12, design: Fomo.design)).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                                    .font(.system(size: 13, weight: .semibold, design: Fomo.design))
                                Text([c.room.isEmpty ? nil : c.room, "til \(untilText(c.start, c.end))"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 12, design: Fomo.design)).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "mappin.circle.fill").foregroundStyle(Fomo.warn) }
                    } else {
                        Label(w.next.map { "Fri til \(DateUtil.hm($0.start))" } ?? "Ingen flere timer i dag",
                              systemImage: "cup.and.saucer.fill").foregroundStyle(Fomo.green)
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
                                    .font(.caption.weight(.semibold)).foregroundStyle(Fomo.green)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Fomo.green.opacity(0.14)))
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
            if let g = dir.group(id) { content(g) } else { SkeletonRows(count: 6, avatar: 30).padding(24).frame(maxHeight: .infinity, alignment: .top) }
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
                        Text(b.author).font(.system(size: 13, weight: .semibold, design: Fomo.design))
                        Text("\(b.board) · \(b.when)").font(.system(size: 11, design: Fomo.design)).foregroundStyle(.secondary)
                    }
                }
                Text(b.title).font(.system(size: 20, weight: .bold, design: Fomo.design)).textSelection(.enabled)
                Text(b.body.isEmpty ? b.text : b.body).font(.system(size: 13, design: Fomo.design)).textSelection(.enabled)
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

// MARK: - profile picture, big

/// The profile picture filling the page, like a lightbox. The full-size picture is fetched
/// (the cache keeps small copies only), with the small one shown until it arrives. Click
/// anywhere or press Esc to close it.
struct MacPhotoViewer: View {
    let url: URL?
    let fallback: URL?
    let name: String
    let close: () -> Void
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.78)).ignoresSafeArea()
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                } else if let small = (fallback ?? url).flatMap(AvatarCache.image) {
                    small.resizable().scaledToFit().blur(radius: failed ? 0 : 6).overlay { if !failed { ProgressView().controlSize(.large) } }
                } else if !failed {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: "person.crop.circle.badge.exclamationmark").font(.system(size: 60, design: Fomo.design)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: 560, maxHeight: 560)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.horizontal, 36).padding(.top, 36).padding(.bottom, 56)
            .contextMenu {
                if let image {
                    Button("Kopiér billede") { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) }
                    Button("Gem billede…") { save(image) }
                }
                if let url { Button("Åbn i browser") { NSWorkspace.shared.open(url) } }
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold, design: Fomo.design)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("Luk (Esc)")
                }
                Spacer()
                Text(name).font(.system(size: 15, weight: .semibold, design: Fomo.design)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { failed = true; return }
        let data = await DownloadGate.shared.run { try? await URLSession.shared.data(from: url).0 }
        if let data, let img = NSImage(data: data) {
            image = img
            if CommandLine.arguments.contains("--feature-test") {
                let px = img.representations.first.map { "\($0.pixelsWide)x\($0.pixelsHigh)" } ?? "?"
                print("[photo] stort billede hentet: \(px) px"); fflush(stdout)
            }
            return
        }
        if let fallback, fallback != url, let d = try? await URLSession.shared.data(from: fallback).0, let img = NSImage(data: d) { image = img; return }
        failed = true
    }

    private func save(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).jpg"
        panel.allowedContentTypes = [.jpeg]
        guard panel.runModal() == .OK, let dest = panel.url,
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { return }
        try? jpg.write(to: dest)
    }
}
