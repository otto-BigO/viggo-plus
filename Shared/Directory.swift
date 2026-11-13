import Combine
import Foundation

// MARK: - Models

/// Everyone at the school as Viggo's address book knows them: students, staff and parents,
/// with class, house, room, birthday and phone, and the groups and relations that tie them together.
struct Member: Identifiable, Hashable, Decodable {
    enum Kind: String { case student, staff, parent, other }

    let id: Int
    let name: String
    let image: URL?
    let imageBig: URL?
    let birthday: Date?
    let type: String
    let grade: String
    let house: String
    let room: String
    let studentNo: String
    let initials: String
    let mobile: String
    let phone: String
    let searchText: String

    var kind: Kind {
        let t = type.lowercased()
        if t.hasPrefix("elev") { return .student }
        if t.hasPrefix("forældre") { return .parent }
        if t.contains("ansat") || t.contains("lærer") { return .staff }
        return .other
    }
    var firstName: String { name.components(separatedBy: " ").first ?? name }
    /// "103" as Viggo has it, "10.3" as people say it.
    var className: String { Member.className(grade) }
    var houseRoom: String { [house, room].filter { !$0.isEmpty }.joined(separator: " ") }
    var anyPhone: String { mobile.isEmpty ? phone : mobile }

    static func className(_ g: String) -> String {
        g.count == 3 && g.hasPrefix("10") ? "10.\(g.dropFirst(2))" : g
    }

    var age: Int? {
        guard let b = birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: b, to: Date()).year
    }
    /// The next birthday and how many days until it (0 on the day).
    var nextBirthday: (date: Date, days: Int, turns: Int)? {
        guard let b = birthday else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var c = cal.dateComponents([.month, .day], from: b)
        c.year = cal.component(.year, from: today)
        guard var next = cal.date(from: c) else { return nil }
        if next < today { c.year! += 1; next = cal.date(from: c) ?? next }
        let days = cal.dateComponents([.day], from: today, to: next).day ?? 0
        return (next, days, (c.year ?? 0) - cal.component(.year, from: b))
    }

    enum CodingKeys: String, CodingKey {
        case Id, Name, Image, ImageBig, Birthday, `Type`, Grade, ProfileValue, StudentId, Initials, Mobile, Phone, SearchText
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil)?.trimmingCharacters(in: .whitespaces) ?? "" }
        id = try c.decode(Int.self, forKey: .Id)
        name = s(.Name)
        image = URL(string: s(.Image))
        imageBig = URL(string: s(.ImageBig))
        let b = s(.Birthday)
        birthday = b.hasPrefix("0001") || b.isEmpty ? nil : Member.dayFormat.date(from: String(b.prefix(10)))
        type = s(.Type)
        grade = s(.Grade)
        // "Hus: Drengegangen;*; Værelse: D17"
        var house = "", room = ""
        for part in s(.ProfileValue).components(separatedBy: ";*;") {
            let kv = part.components(separatedBy: ":")
            guard kv.count >= 2 else { continue }
            let v = kv.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            if kv[0].contains("Hus") { house = v } else if kv[0].contains("Værelse") { room = v }
        }
        self.house = house
        self.room = room
        studentNo = (try? c.decodeIfPresent(Int.self, forKey: .StudentId)).flatMap { $0 }.map(String.init) ?? ""
        initials = s(.Initials)
        mobile = s(.Mobile)
        phone = s(.Phone)
        searchText = s(.SearchText).lowercased()
    }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}

/// A class, a line, an elective, a team or any other group in Viggo.
struct MemberGroup: Identifiable, Hashable, Decodable {
    enum Kind: Int, Comparable {
        case klasse, underviser, linje, hold, valgfag, idraet, gruppe, fag, andet
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
        var title: String {
            switch self {
            case .klasse: "Klasse"
            case .underviser: "Lærer for"
            case .linje: "Linje"
            case .hold: "Linjehold"
            case .valgfag: "Valgfag"
            case .idraet: "Idræt og hold"
            case .gruppe: "Kontaktgruppe"
            case .fag: "Fag"
            case .andet: "Andre grupper"
            }
        }
    }

    let id: Int
    let name: String
    let members: [Int]
    let note: String
    let folder: String

    enum CodingKeys: String, CodingKey { case Id, Name, UsersIds, Description, FolderName }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .Id)
        name = ((try? c.decode(String.self, forKey: .Name)) ?? "").trimmingCharacters(in: .whitespaces)
        members = (try? c.decode([Int].self, forKey: .UsersIds)) ?? []
        note = ((try? c.decodeIfPresent(String.self, forKey: .Description)) ?? nil) ?? ""
        folder = ((try? c.decodeIfPresent(String.self, forKey: .FolderName)) ?? nil) ?? ""
    }

    var kind: Kind {
        let n = name.lowercased()
        if n.range(of: "^(\\d{1,2}|\\d{3})$", options: .regularExpression) != nil { return .klasse }
        if n.hasSuffix("-lærere") { return .underviser }
        if n.hasPrefix("linjefag:") { return n.contains("-") ? .hold : .linje }
        if n.hasPrefix("valgfag") { return .valgfag }
        if n.range(of: "^gruppe [a-zæøå]+$", options: .regularExpression) != nil { return .gruppe }
        if ["fodbold", "håndbold", "badminton", "gymnastik", "springgymnastik", "ski", "snowboard", "idræt"].contains(where: { n.hasPrefix($0) }) { return .idraet }
        if ["dansk", "engelsk", "tysk", "matematik", "fysik", "biologi", "geografi", "samfundsfag", "medborgerskab",
            "musik", "kunst", "teater", "kor", "be10"].contains(where: { n.hasPrefix($0) }) { return .fag }
        return .andet
    }

    /// "Linjefag: Musiklinjen-hold1" → "Musiklinjen, hold 1", "103" → "10.3", "Valgfag 1: Guitar" → "Guitar (valgfag 1)".
    var display: String {
        switch kind {
        case .klasse: return Member.className(name)
        case .underviser: return name.replacingOccurrences(of: "-lærere", with: "")
        case .linje, .hold:
            let n = name.replacingOccurrences(of: "Linjefag:", with: "").trimmingCharacters(in: .whitespaces)
            return n.replacingOccurrences(of: "-hold(\\d+)", with: ", hold $1", options: .regularExpression)
                .replacingOccurrences(of: "-(dreng|pige)$", with: " ($1e)", options: .regularExpression)
        case .valgfag:
            if let m = name.firstMatch("^Valgfag\\s*(\\d)\\s*[:\\-]\\s*(.+?)\\s*(\\d{2,})?$") { return "\(m[2]) (valgfag \(m[1]))" }
            return name
        case .fag where !note.isEmpty && name.count < 14:
            return "\(name) (\(note))"
        default: return name
        }
    }
}

/// What someone is to someone else.
struct MemberRelation: Hashable {
    let master: Int
    let user: Int
    let kind: Int
    /// Viggo's ids: 1 far, 2 mor, 3 samlever, 4 kontaktlærer, the rest family and other contacts.
    var isContactTeacher: Bool { kind == 4 }
}

/// What the profile page adds: the address and any field not in the address book.
struct MemberDetails: Hashable {
    var address: [String] = []
    var fields: [(String, String)] = []
    static func == (a: MemberDetails, b: MemberDetails) -> Bool { a.address == b.address && a.fields.map { $0.0 + $0.1 } == b.fields.map { $0.0 + $0.1 } }
    func hash(into h: inout Hasher) { h.combine(address) }
    func field(_ name: String) -> String? { fields.first { $0.0.lowercased().hasPrefix(name.lowercased()) }?.1 }
}

// MARK: - Parsing and fetching

extension Parser {
    static func memberDetails(_ html: String) -> MemberDetails {
        guard let start = html.range(of: "class=\"user-details") else { return MemberDetails() }
        var block = String(html[start.upperBound...])
        if let end = block.range(of: "</section>") { block = String(block[..<end.lowerBound]) }
        var d = MemberDetails()
        if let addr = block.firstMatch("id=\"protected_address\"[^>]*>(.*?)</div>")?[1] {
            d.address = addr.matches("<h4[^>]*>(.*?)</h4>").map { $0[1].strippedHTML.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        // Every <dt>label</dt><dd>value</dd>, skipping "Bor med" (rooms come from the address book).
        for m in block.matches("<dt[^>]*>(.*?)</dt>\\s*<dd[^>]*>(.*?)</dd>") {
            let label = m[1].replacingOccurrences(of: "<small.*?</small>", with: "", options: .regularExpression).strippedHTML
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = m[2].strippedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !value.isEmpty, label != "Medlem af", label != "Bor med" else { continue }
            d.fields.append((label, value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)))
        }
        return d
    }
}

extension ViggoClient {
    struct DirectoryData: Decodable {
        struct Rel: Decodable { let MasterUserId: Int; let UserId: Int; let RelationsId: Int }
        let Users: [Member]
        let Groups: [MemberGroup]
        let Relations: [Rel]?
    }

    func fetchMembers() async throws -> Data { try await getPublic("/Shared/Search/GetautocompleteData") }

    func fetchMemberDetails(_ id: Int) async throws -> MemberDetails {
        Parser.memberDetails(String(decoding: try await getPublic("/Basic/Users/Details/\(id)?ajax=1"), as: UTF8.self))
    }

    /// Viggo's own search in the inbox. It looks in the text of the messages too, without opening
    /// (and so marking as read) any of them.
    func searchThreads(_ text: String) async throws -> [MessageThread] {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let q = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let html = String(decoding: try await getPublic("/Basic/Message/Folder/\(Self.inboxFolder)/?ajax=2&pagesize=200&searchText=\(q)"), as: UTF8.self)
        return Parser.threads(html, unread: [])
    }
}

// MARK: - State

@MainActor
final class Directory: ObservableObject {
    static let shared = Directory()
    private let client = ViggoClient()

    @Published private(set) var members: [Member] = []
    @Published private(set) var groups: [MemberGroup] = []
    @Published private(set) var relations: [MemberRelation] = []
    @Published private(set) var loading = false
    @Published var error: String?
    private var byID: [Int: Member] = [:]
    private var groupsOf: [Int: [MemberGroup]] = [:]
    private var details: [Int: MemberDetails] = [:]
    /// Worked out once when the address book loads, so searching only compares strings.
    private var sortedGroupsOf: [Int: [MemberGroup]] = [:]
    private var lineOf: [Int: String] = [:]
    private var summaryOf: [Int: String] = [:]
    private struct Index { let name: String; let parts: [Substring]; let line: String; let house: String; let room: String; let initials: String }
    private var index: [Index] = []
    private var loadedAt: Date?

    private var cacheURL: URL { CookieJar.dir.appendingPathComponent("directory.json") }

    init() {
        if let data = try? Data(contentsOf: cacheURL) { apply(data) }
    }

    /// The address book changes rarely, so fetch it at most every few hours.
    func load(force: Bool = false) async {
        if !force, let t = loadedAt, Date().timeIntervalSince(t) < 6 * 3600, !members.isEmpty { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await client.fetchMembers()
            if apply(data) {
                try? data.write(to: cacheURL, options: .atomic)
                loadedAt = Date()
                error = nil
            }
        } catch ViggoError.notLoggedIn {
            error = "Du er logget ud af Viggo."
        } catch {
            if members.isEmpty { self.error = "Kunne ikke hente personer fra Viggo." }
        }
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let d = try? JSONDecoder().decode(ViggoClient.DirectoryData.self, from: data), !d.Users.isEmpty else { return false }
        members = d.Users.filter { !$0.name.isEmpty }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        byID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        groups = d.Groups.filter { !$0.members.isEmpty }
        var of: [Int: [MemberGroup]] = [:]
        for g in groups { for m in g.members { of[m, default: []].append(g) } }
        groupsOf = of
        relations = (d.Relations ?? []).map { MemberRelation(master: $0.MasterUserId, user: $0.UserId, kind: $0.RelationsId) }
        sortedGroupsOf = of.mapValues { list in
            list.filter { !$0.name.lowercased().hasPrefix("alle ") }
                .sorted { $0.kind == $1.kind ? $0.display.localizedCompare($1.display) == .orderedAscending : $0.kind < $1.kind }
        }
        lineOf = sortedGroupsOf.compactMapValues { $0.first { $0.kind == .linje }?.display }
        summaryOf = [:]
        index = members.map { m in
            let name = m.name.lowercased()
            return Index(name: name, parts: name.split(separator: " "), line: lineOf[m.id]?.lowercased() ?? "",
                         house: m.house.lowercased(), room: m.room.lowercased(), initials: m.initials.lowercased())
        }
        return true
    }

    func member(_ id: Int) -> Member? { byID[id] }
    func member(named name: String) -> Member? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return members.first { $0.name.lowercased() == n }
    }

    /// The groups someone is in, most telling first. "Alle ..." groups say nothing, so they are left out.
    func groups(of id: Int) -> [MemberGroup] { sortedGroupsOf[id] ?? [] }
    func group(_ id: Int) -> MemberGroup? { groups.first { $0.id == id } }

    /// The line someone is on ("Musiklinjen"), from their Linjefag group.
    func line(of id: Int) -> String? { lineOf[id] }

    func roommates(of m: Member) -> [Member] {
        guard !m.room.isEmpty else { return [] }
        return members.filter { $0.id != m.id && $0.kind == .student && $0.room == m.room && $0.house == m.house }
    }
    func classmates(of m: Member) -> [Member] {
        guard !m.grade.isEmpty else { return [] }
        return members.filter { $0.id != m.id && $0.kind == .student && $0.grade == m.grade }
    }

    /// Parents and other family: (relation name, person).
    func family(of id: Int) -> [(String, Member)] {
        relations.filter { $0.user == id && !$0.isContactTeacher }.compactMap { r in
            byID[r.master].map { (Self.relationName(r.kind), $0) }
        }.sorted { $0.0 < $1.0 }
    }
    func contactTeachers(of id: Int) -> [Member] {
        relations.filter { $0.user == id && $0.isContactTeacher }.compactMap { byID[$0.master] }
    }
    /// For a parent: their children. For a teacher: their contact students.
    func children(of id: Int) -> [Member] {
        relations.filter { $0.master == id && !$0.isContactTeacher }.compactMap { byID[$0.user] }
    }
    func contactStudents(of id: Int) -> [Member] {
        relations.filter { $0.master == id && $0.isContactTeacher }.compactMap { byID[$0.user] }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    static func relationName(_ k: Int) -> String {
        switch k {
        case 1: "Far"
        case 2: "Mor"
        case 3: "Samlever"
        case 4: "Kontaktlærer"
        case 11, 12: "Kontakt"
        default: "Familie"
        }
    }

    /// The groups you and someone else are both in.
    func shared(_ a: Int, _ b: Int) -> [MemberGroup] {
        let mine = Set(groups(of: a).map(\.id))
        return groups(of: b).filter { mine.contains($0.id) }
    }

    func details(_ id: Int) async -> MemberDetails? {
        if let d = details[id] { return d }
        guard let d = try? await client.fetchMemberDetails(id) else { return nil }
        details[id] = d
        return d
    }

    /// One line about someone for a list: "10.4 · Musiklinjen · Drengegangen D17", "Lærer · HG", "Mor til Otto".
    func summary(_ m: Member) -> String {
        if let s = summaryOf[m.id] { return s }
        let s = makeSummary(m)
        summaryOf[m.id] = s
        return s
    }

    private func makeSummary(_ m: Member) -> String {
        switch m.kind {
        case .student:
            return [m.className.isEmpty ? nil : m.className, line(of: m.id), m.houseRoom.isEmpty ? nil : m.houseRoom]
                .compactMap { $0 }.joined(separator: " · ")
        case .staff:
            return ["Ansat", m.initials.isEmpty ? nil : m.initials].compactMap { $0 }.joined(separator: " · ")
        case .parent:
            let kids = relations.filter { $0.master == m.id && !$0.isContactTeacher }
            guard let first = kids.first, let kid = byID[first.user] else { return "Forælder" }
            return "\(Self.relationName(first.kind)) til \(kid.firstName)" + (kids.count > 1 ? " og \(kids.count - 1) mere" : "")
        case .other:
            return m.type
        }
    }

    // MARK: search

    /// Everyone matching a query: by name, class ("10.4", "104"), house, room ("d17"), initials,
    /// student number, phone or line. Students first, then staff, then parents.
    func search(_ query: String) -> [Member] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)
        let classQ = q.replacingOccurrences(of: ".", with: "")
        var scored: [(Int, Member)] = []
        let long = q.count >= 3
        for (m, x) in zip(members, index) {
            var score = 0
            if x.name == q { score = 100 }
            else if x.name.hasPrefix(q) { score = 80 }
            else if words.allSatisfy({ w in x.parts.contains { $0.hasPrefix(w) } }) { score = 60 }
            else if !x.initials.isEmpty, x.initials == q { score = 70 }
            else if !x.room.isEmpty, x.room == q { score = 65 }
            else if !m.grade.isEmpty, m.grade == classQ, m.kind == .student { score = 50 }
            else if long, !x.line.isEmpty, x.line.hasPrefix(q) { score = 45 }
            else if long, !x.house.isEmpty, x.house.hasPrefix(q) { score = 40 }
            else if long, words.allSatisfy({ m.searchText.contains($0) }) { score = 20 }
            guard score > 0 else { continue }
            score += m.kind == .student ? 3 : m.kind == .staff ? 2 : 0
            scored.append((score, m))
        }
        return scored.sorted { $0.0 == $1.0 ? $0.1.name < $1.1.name : $0.0 > $1.0 }.map(\.1)
    }

    func searchGroups(_ query: String) -> [MemberGroup] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        let classQ = q.replacingOccurrences(of: ".", with: "")
        return groups.filter { g in
            !g.name.lowercased().hasPrefix("alle ") &&
            (g.name.lowercased() == classQ || g.display.lowercased().contains(q) || (q.count >= 3 && g.name.lowercased().contains(q)))
        }
        .sorted { $0.kind == $1.kind ? $0.display < $1.display : $0.kind < $1.kind }
    }

    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
