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
