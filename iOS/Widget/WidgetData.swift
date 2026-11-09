import Foundation

/// What the widgets show. The app writes it after every sync into the app group,
/// the widget only reads it (it never talks to Viggo itself).
struct WidgetItem: Codable, Hashable {
    let title: String
    let start: Date
    let end: Date
    let room: String
    let kind: String
    let color: String?

    var isPause: Bool { kind == "pause" }
}

struct WidgetData: Codable {
    var name: String?
    var items: [WidgetItem]
    var homework: Int
    var updated: Date
    var loggedOut: Bool
    /// The open homework, for the large widget and Siri.
    var homeworkList: [String]? = nil

    static let empty = WidgetData(name: nil, items: [], homework: 0, updated: .distantPast, loggedOut: false)

    /// What runs at `t`, and what comes next (pauses are skipped for "next").
    func now(_ t: Date) -> (current: WidgetItem?, next: WidgetItem?, later: [WidgetItem]) {
        let current = items.first { $0.start <= t && $0.end > t }
        let upcoming = items.filter { $0.start > t && !$0.isPause }
        return (current, upcoming.first, Array(upcoming.dropFirst()))
    }
}

enum WidgetStore {
    static let group = "group.com.ottobigo.viggoplus"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget.json")
    }
    static func load() -> WidgetData {
        guard let url, let d = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(WidgetData.self, from: d)) ?? .empty
    }
    static func save(_ w: WidgetData) {
        guard let url, let d = try? JSONEncoder().encode(w) else { return }
        try? d.write(to: url, options: .atomic)
    }
}

// MARK: - Spoken answers (Siri, Shortcuts)

extension WidgetData {
    private static let hmF: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private func hm(_ d: Date) -> String { Self.hmF.string(from: d) }
    private func today(_ t: Date) -> [WidgetItem] { items.filter { Calendar.current.isDate($0.start, inSameDayAs: t) } }
    private func at(_ i: WidgetItem) -> String { i.room.isEmpty ? "" : " i \(i.room)" }

    var missing: String? {
        if loggedOut { return "Du er logget ud af Viggo. Åbn Viggo+ og log ind." }
        if items.isEmpty { return "Åbn Viggo+ en gang, så den kan hente dit skema." }
        return nil
    }

    func sayNow(_ t: Date) -> String {
        if let m = missing { return m }
        let (cur, next, _) = now(t)
        let nextToday = next.flatMap { Calendar.current.isDate($0.start, inSameDayAs: t) ? $0 : nil }
        if let c = cur, !c.isPause {
            var s = "Du har \(c.title)\(at(c)) til \(hm(c.end))."
            if let n = nextToday { s += " Bagefter har du \(n.title) kl. \(hm(n.start))." }
            return s
        }
        if let n = nextToday { return "Du har fri nu. Næste er \(n.title)\(at(n)) kl. \(hm(n.start))." }
        return "Du har fri resten af dagen." + (sayTomorrow(t).map { " " + $0 } ?? "")
    }

    func sayFree(_ t: Date) -> String {
        if let m = missing { return m }
        let school = today(t).filter { $0.kind == "lesson" }
        guard let end = school.map(\.end).max() else { return "Du har ingen timer i dag." }
        if end <= t { return "Du har allerede fri i dag. Din sidste time sluttede kl. \(hm(end))." }
        let left = school.filter { $0.end > t }.count
        return "Du har fri kl. \(hm(end)). Der er \(left) \(left == 1 ? "time" : "timer") tilbage."
    }

    func sayTomorrow(_ t: Date) -> String? {
        guard let tm = Calendar.current.date(byAdding: .day, value: 1, to: t),
              let first = items.first(where: { Calendar.current.isDate($0.start, inSameDayAs: tm) && !$0.isPause && $0.kind != "routine" })
        else { return nil }
        return "I morgen starter du med \(first.title) kl. \(hm(first.start))."
    }

    func sayHomework() -> String {
        if let m = missing { return m }
        let list = homeworkList ?? []
        if homework == 0 { return "Du har ingen lektier. Godt gået!" }
        if list.isEmpty { return "Du har \(homework) lektier." }
        return "Du har \(homework) \(homework == 1 ? "lektie" : "lektier"): " + list.prefix(4).joined(separator: ", ") + "."
    }
}
