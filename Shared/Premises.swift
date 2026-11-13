import Foundation

/// Viggo's room overview (Lokaler, /Basic/Premises) lists every booking at the school with the
/// groups and teachers on it, and every logged-in student may see it. Together with the groups
/// from the address book that gives anyone's lessons, so a friend no longer has to log in.
@MainActor final class Premises: ObservableObject {
    static let shared = Premises()

    struct Booking {
        let event: ViggoEvent
        let groups: Set<Int>
        let users: Set<Int>
    }

    @Published private(set) var bookings: [Booking] = []
    @Published private(set) var loadedAt: Date?
    private let client = ViggoClient()
    private var cacheURL: URL { CookieJar.dir.appendingPathComponent("premises.json") }

    init() {
        if let data = try? Data(contentsOf: cacheURL) { apply(data) }
    }

    /// This week and next. Rooms change during the day, so at most every 20 minutes unless `force`.
    /// A second call while one runs waits for it instead of returning empty-handed.
    private var running: Task<Void, Never>?
    func load(force: Bool = false) async {
        if let running { await running.value; if !force { return } }
        if !force, let t = loadedAt, Date().timeIntervalSince(t) < 20 * 60 { return }
        let t = Task { await fetch() }
        running = t
        await t.value
        running = nil
    }

    private func fetch() async {
        let monday = DateUtil.mondayOf(Date())
        func week(_ w: Int) -> String {
            let m = DateUtil.add(.weekOfYear, w, monday)
            let s = DateUtil.ymd(m), e = DateUtil.ymd(DateUtil.add(.day, 6, m))
            return "/Shared/Events/GetEventItems?target=OnlyPremises&date=\(s)&type=week&startDate=\(s)&endDate=\(e)"
        }
        // Both weeks at once; each is a big response for the whole school.
        let c = client, p0 = week(0), p1 = week(1)
        async let a = try? c.getPublic(p0)
        async let b = try? c.getPublic(p1)
        var all: [Any] = []
        for data in [await a, await b] {
            guard let data, let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return }
            all += arr
        }
        guard let data = try? JSONSerialization.data(withJSONObject: all), apply(data) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        loadedAt = Date()
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let events = try? Parser.events(data) else { return false }
        var ids: [Int: (Set<Int>, Set<Int>)] = [:]
        for o in arr {
            guard let id = o["id"] as? Int else { continue }
            let g = (o["groups"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }
            let u = (o["usersWithSubstitutes"] as? [[String: Any]] ?? []).compactMap { ($0["user"] as? [String: Any])?["id"] as? Int }
            ids[id] = (Set(g), Set(u))
        }
        var seen = Set<String>()
        bookings = events.filter { seen.insert($0.key).inserted }.map {
            Booking(event: $0, groups: ids[$0.id]?.0 ?? [], users: ids[$0.id]?.1 ?? [])
        }.sorted { $0.event.start < $1.event.start }
        return !bookings.isEmpty
    }

    /// Someone's lessons and events: the bookings for a group they are in, or with them as teacher.
    func schedule(for id: Int) -> [ViggoEvent] {
        let gs = Directory.shared.groupIDs(of: id)
        return bookings.filter { !$0.groups.isDisjoint(with: gs) || $0.users.contains(id) }.map(\.event)
    }

    /// What someone has right now and what comes next today.
    func whereNow(_ id: Int, at now: Date = Date()) -> (now: ViggoEvent?, next: ViggoEvent?) {
        let today = schedule(for: id).filter { DateUtil.cal.isDate($0.start, inSameDayAs: now) }
        return (today.first { $0.start <= now && $0.end > now }, today.first { $0.start > now })
    }
}
