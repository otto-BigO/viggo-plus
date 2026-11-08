import Foundation

enum EventKind: String, Codable { case lesson, event, routine, birthday, duty }

struct ViggoEvent: Codable, Hashable, Identifiable {
    let id: Int
    let rawName: String
    let start: Date
    let end: Date
    let room: String
    let notes: String
    let kind: EventKind
    let teachers: [String]
    let groups: [String]
    /// Links the teacher put in the lesson description (videos, Drive files …).
    var links: [URL] = []

    /// The teacher's description: what to do, read or bring.
    var hasInfo: Bool { !notes.isEmpty }

    var key: String { "\(kind.rawValue)-\(id)" }
    /// The name you gave this lesson in Indstillinger › Timer, otherwise Viggo's.
    var title: String {
        let b = baseTitle
        if let own = Prefs.shared.lessonNames[b], !own.isEmpty { return own }
        return b
    }

    var baseTitle: String {
        let t = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.uppercased().hasPrefix("BE10") { return "BE10 · Projekt" }
        if kind == .lesson, let m = t.firstMatch("^\\d+\\s+(.+)$") { return m[1] }
        return t
    }
    var link: URL { URL(string: "/Shared/Events/Details/?id=\(id)", relativeTo: Config.baseURL)!.absoluteURL }

    /// Short label for the menubar ("Alle på eget område" → "På område").
    var shortTitle: String {
        let l = title.lowercased()
        if l.contains("eget område") { return "På område" }
        if l.contains("eget værelse") { return "På værelse" }
        if l.hasPrefix("godnat") { return "Godnat" }
        if l.contains("fællessamling") { return "Fællessamling" }
        if l.hasPrefix("stilletime") { return "Stilletime" }
        if l.hasPrefix("tjek af") { return "Værelsestjek" }
        return title
    }

    /// For the menu bar, where space is short.
    var menuBarTitle: String { shortTitle.count > 22 ? String(shortTitle.prefix(21)) + "…" : shortTitle }
}

struct Homework: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let group: String
    let day: Date
    let start: Date?
    let end: Date?
    let notes: String
    let author: String
    var done: Bool

    var due: Date { start ?? day }
    var link: URL { URL(string: "/Basic/HomeworkAndAssignment/Details/\(id)/", relativeTo: Config.baseURL)!.absoluteURL }
}

struct Profile: Codable, Equatable {
    let id: Int
    let name: String
    let image: URL?
}

struct ViggoMessage: Codable, Hashable, Identifiable {
    let id: Int
    let sender: String
    let when: String
    let subject: String
    let preview: String
    var link: URL { URL(string: "/Basic/Message/Inbox", relativeTo: Config.baseURL)!.absoluteURL }
}

enum ViggoError: LocalizedError {
    case notLoggedIn, unexpected(String)
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Ikke logget ind på Viggo"
        case .unexpected(let s): return "Fejl: \(s)"
        }
    }
}

enum Parser {
    static func events(_ data: Data) throws -> [ViggoEvent] {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ViggoError.unexpected("Uventet skema-svar")
        }
        return arr.compactMap { o in
            guard let id = o["id"] as? Int,
                  let s = o["start"] as? String, let e = o["end"] as? String,
                  let start = DateUtil.iso.date(from: s), let end = DateUtil.iso.date(from: e) else { return nil }
            let type = o["type"] as? String ?? ""
            let el = o["elementType"] as? Int ?? -1
            let kind: EventKind
            switch (type, el) {
            case ("birthday", _): kind = .birthday
            case ("guard", _): kind = .duty
            case (_, 0): kind = .lesson
            default: kind = .event
            }
            let lower = (o["name"] as? String ?? "").lowercased()
            let finalKind: EventKind = (kind == .event || kind == .lesson) && Parser.isRoutine(lower) ? .routine : kind
            let teachers = (o["usersWithSubstitutes"] as? [[String: Any]] ?? []).compactMap {
                ($0["user"] as? [String: Any])?["fullName"] as? String
            }.filter { !$0.isEmpty }
            var groups: [String] = []
            for g in o["groups"] as? [[String: Any]] ?? [] {
                let n = (g["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let d = (g["description"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let label = d.isEmpty || d == n ? n : "\(n) (\(d))"
                if !label.isEmpty, !groups.contains(label) { groups.append(label) }
            }
            return ViggoEvent(
                id: id,
                rawName: (o["name"] as? String ?? "").htmlDecoded,
                start: start, end: end,
                room: (o["premises"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                notes: (o["description"] as? String ?? "").strippedHTML,
                kind: finalKind, teachers: teachers, groups: groups,
                links: (o["description"] as? String ?? "").matches("href=\"(https?://[^\"]+)\"")
                    .compactMap { URL(string: $0[1].htmlDecoded) })
        }
    }

    static let routineWords = ["morgenmad", "middag", "aftensmad", "rengøring", "godnat", "stilletime",
                               "tjek af", "oprydning", "eget værelse", "eget område", "morgensamling",
                               "fællessamling", "aflever", "telefon"]
    static func isRoutine(_ lower: String) -> Bool { routineWords.contains { lower.contains($0) } }

    static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "maj": 5, "jun": 6,
                         "jul": 7, "aug": 8, "sep": 9, "okt": 10, "nov": 11, "dec": 12]

    static func homework(_ html: String, near ref: Date) -> [Homework] {
        let refYear = DateUtil.cal.component(.year, from: ref)
        let refMonth = DateUtil.cal.component(.month, from: ref)
        var out: [Homework] = []
        for block in html.components(separatedBy: "<p><span>").dropFirst() {
            guard let h = block.firstMatch("^([^<]+)</span>\\s*<small>(\\d{1,2})\\.\\s*([^<]+)</small>"),
                  let dayNum = Int(h[2]),
                  let month = months[String(h[3].trimmingCharacters(in: .whitespaces).lowercased().prefix(3))] else { continue }
            var year = refYear
            if month < refMonth - 6 { year += 1 } else if month > refMonth + 6 { year -= 1 }
            guard let day = DateUtil.cal.date(from: DateComponents(year: year, month: month, day: dayNum)) else { continue }
            let section = block.components(separatedBy: "<p><span>").first ?? block
            for item in section.components(separatedBy: "flaticon-homework\"></i>").dropFirst() {
                guard let idS = item.firstMatch("HomeworkAndAssignment/Details/(\\d+)")?[1], let id = Int(idS) else { continue }
                let title = item.firstMatch("<strong>(.*?)</strong>")?[1].strippedHTML ?? "Lektie"
                let group = item.firstMatch("<small>\\s*<i class=\"flaticon-group\"></i>(.*?)</small>")?[1].strippedHTML ?? ""
                var start: Date?, end: Date?
                if let t = item.firstMatch("<p>\\s*(\\d{1,2}):(\\d{2})\\s*-\\s*(\\d{1,2}):(\\d{2})") {
                    start = DateUtil.cal.date(bySettingHour: Int(t[1])!, minute: Int(t[2])!, second: 0, of: day)
                    end = DateUtil.cal.date(bySettingHour: Int(t[3])!, minute: Int(t[4])!, second: 0, of: day)
                }
                var notes = item.firstMatch("<div class=\"content\">(.*?)</div></div>")?[1].strippedHTML ?? ""
                if notes == "." { notes = "" }
                let author = item.firstMatch("<small class=\"fix-height muted\">(.*?)</small>")?[1].strippedHTML ?? ""
                let done = item.contains("ajax-toggle on")
                out.append(Homework(id: id, title: title, group: group, day: day, start: start, end: end,
                                    notes: notes, author: author, done: done))
            }
        }
        return out
    }

    static func profile(_ html: String) -> Profile? {
        guard let m = html.firstMatch("<div class=\"user\"><img src=\"([^\"]*)\"[^>]*>\\s*<a href=\"/Basic/Users/Details/(\\d+)\">(.*?)</a>"),
              let id = Int(m[2]) else { return nil }
        return Profile(id: id, name: m[3].strippedHTML, image: URL(string: m[1].htmlDecoded))
    }

    static func messages(_ html: String) -> [ViggoMessage] {
        html.components(separatedBy: "<li id=\"tree-item-message-id-").dropFirst().compactMap { c in
            guard let idS = c.firstMatch("^(\\d+)")?[1], let id = Int(idS) else { return nil }
            let who = c.firstMatch("<div><div>(.*?)</div><small>(.*?)</small></div>")
            let subject = c.firstMatch("<div class=\"h\"[^>]*>(.*?)</div>")?[1].strippedHTML ?? ""
            let preview = c.firstMatch("<div class=\"h\"[^>]*>.*?</div>\\s*<div>(.*?)</div>")?[1].strippedHTML ?? ""
            return ViggoMessage(id: id, sender: who?[1].strippedHTML ?? "", when: who?[2].strippedHTML ?? "",
                                subject: subject, preview: preview)
        }
    }
}
