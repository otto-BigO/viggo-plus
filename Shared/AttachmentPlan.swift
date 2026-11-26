import SwiftUI
import PDFKit

/// A list in a PDF attachment (køkkenhold, rengøring, vagter) that has your name on it: when you are on,
/// read from the line with your name, the heading above it and the message the file came with.
struct RosterHit: Identifiable, Hashable {
    var id: Int { file }
    let file: Int
    let thread: Int
    let title: String
    /// "uge 49 og 52, man til fre kl. 6.30" or "onsdag d. 11. november kl. 16.45".
    let summary: String
    let slots: [Slot]
    let from: String

    struct Slot: Hashable { let start: Date; let end: Date }

    func upcoming(now: Date = Date()) -> [Slot] { slots.filter { $0.end > now } }
}

@MainActor enum Roster {
    /// One printed line of a page, put back together from the pieces PDFKit gives ("Julia Trolle" and
    /// "k 107 Teater Uge 49 + 52" sit at the same height but come apart).
    struct Line { let page: Int; let y: CGFloat; let text: String; var parts: [(x: CGFloat, text: String)] = [] }

    static func lines(_ doc: PDFDocument) -> [Line] {
        var out: [Line] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i), let sel = p.selection(for: p.bounds(for: .mediaBox)) else { continue }
            var pieces: [(x: CGFloat, y: CGFloat, s: String)] = []
            for l in sel.selectionsByLine() {
                let s = (l.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { continue }
                let b = l.bounds(for: p)
                pieces.append((b.minX, b.midY, s))
            }
            // Top of the page first; pieces within 3 points of each other are one line, left to right.
            pieces.sort { $0.y > $1.y }
            var rows: [[(x: CGFloat, y: CGFloat, s: String)]] = []
            for piece in pieces {
                if let last = rows.last?.first, abs(last.y - piece.y) < 3 { rows[rows.count - 1].append(piece) } else { rows.append([piece]) }
            }
            for r in rows {
                let sorted = r.sorted { $0.x < $1.x }
                out.append(Line(page: i, y: r[0].y, text: sorted.map(\.s).joined(separator: " "), parts: sorted.map { ($0.x, $0.s) }))
            }
        }
        return out
    }

    /// Does this line have this person on it? The whole name, or the first and the last name.
    static func matches(_ line: String, name: String) -> Bool {
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "da_DK")) }
        let l = " " + fold(line).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) + " "
        let n = fold(name).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard n.count >= 4 else { return false }
        if l.contains(" \(n) ") { return true }
        let parts = n.split(separator: " ").map(String.init)
        guard parts.count >= 2, let first = parts.first, let last = parts.last else { return false }
        return l.contains(" \(first) ") && l.contains(" \(last) ")
    }

    /// "Køkkenhold fra november til marts" → "Køkkenhold", "Køkkenhold uge 46" → "Køkkenhold".
    static func title(subject: String, file: String) -> String {
        var t = subject.replacingOccurrences(of: "(?i)^\\s*(sv|re|fw|vs):\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)\\s+(fra|i|for|til|uge|d\\.|den|\\d).*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if t.count >= 3 { return t }
        let f = (file as NSString).deletingPathExtension.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        return f.isEmpty ? "Fra en vedhæftet fil" : f
    }

    /// Your slots in one PDF, or nil if your name is not in it.
    static func find(name: String, lines: [Line], message: String, subject: String, posted: Date, file: Int, thread: Int,
                     fileName: String, from: String) -> RosterHit? {
        guard let i = lines.firstIndex(where: { matches($0.text, name: name) }) else { return nil }
        let line = lines[i].text
        let title = title(subject: subject, file: fileName)
        let fallback = Deadlines.clock(in: message)
        // A list by weeks: "… Uge 49 + 52", "… Uge 1 + weekenden". Days and time come from the message.
        if let u = line.range(of: "(?i)\\buge\\b.*$", options: .regularExpression) {
            let tail = String(line[u])
            let weeks = tail.replacingOccurrences(of: "[^0-9]+", with: " ", options: .regularExpression).split(separator: " ").compactMap { Int($0) }.filter { (1...53).contains($0) }
            guard !weeks.isEmpty else { return nil }
            let weekend = tail.lowercased().contains("weekend")
            let span = Deadlines.spots(in: message, posted: posted).first { $0.days > 1 }
            let firstDay = span?.day.map { (DateUtil.cal.component(.weekday, from: $0) + 5) % 7 } ?? 0 // Monday is 0
            let count = span?.days ?? 5
            let clock = span.flatMap { s in s.start.map { minutes($0) } }.map { ($0, span?.end.map(minutes)) }
                ?? fallback.map { ($0.start, $0.end) }
            let start = clock?.0 ?? 8 * 60
            let end = clock?.1 ?? start + 60
            var slots: [RosterHit.Slot] = []
            for w in weeks {
                guard let monday = monday(ofWeek: w, near: posted) else { continue }
                var days = (0..<count).map { (firstDay + $0) % 7 }
                if weekend { days += [5, 6].filter { !days.contains($0) } }
                for d in days.sorted() {
                    let day = DateUtil.add(.day, d, monday)
                    slots.append(.init(start: day.addingTimeInterval(Double(start * 60)), end: day.addingTimeInterval(Double(end * 60))))
                }
            }
            let names = ["man", "tirs", "ons", "tors", "fre", "lør", "søn"]
            let dayText = count == 1 ? names[firstDay] : "\(names[firstDay]) til \(names[(firstDay + count - 1) % 7])"
            let weekText = weeks.count == 1 ? "uge \(weeks[0])" : "uge " + weeks.dropLast().map(String.init).joined(separator: ", ") + " og \(weeks.last!)"
            let summary = "\(weekText)\(weekend ? " og weekenden" : ""), \(dayText) kl. \(hm(start))"
            return RosterHit(file: file, thread: thread, title: title, summary: summary, slots: slots, from: subject)
        }
        // A list by headings: the nearest line above with a day and a time ("Onsdag d. 11. november kl. 16.45").
        // At the top of a page, the last heading of the page before.
        for h in lines[..<i].reversed() {
            guard let c = Deadlines.clock(in: h.text), let day = Deadlines.day(in: h.text, posted: posted) else { continue }
            let start = DateUtil.startOfDay(day).addingTimeInterval(Double(c.start * 60))
            let end = DateUtil.startOfDay(day).addingTimeInterval(Double((c.end ?? c.start + 60) * 60))
            let summary = h.text.trimmingCharacters(in: .whitespaces).lowercasedFirst
            return RosterHit(file: file, thread: thread, title: title, summary: summary, slots: [.init(start: start, end: end)], from: subject)
        }
        return nil
    }

    private static func minutes(_ d: Date) -> Int {
        let c = DateUtil.cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    private static func hm(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60)" : String(format: "%d.%02d", m / 60, m % 60) }

    // MARK: lists by room

    private static let dayNames = ["mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag", "søndag"]

    /// "Buen 4 a", "Buen 4" and "B4a", "B4" for house Buen and room B4.
    static func roomPatterns(house: String, room: String) -> [String] {
        let r = room.trimmingCharacters(in: .whitespaces)
        guard let num = r.firstMatch("(\\d+)")?[1] else { return [] }
        var out: [String] = []
        let h = house.trimmingCharacters(in: .whitespaces)
        if h.count >= 2 { out.append("(?i)\\b\(NSRegularExpression.escapedPattern(for: h))\\s+\(num)(?:\\s?[a-d])?\\b") }
        if r.count >= 2, r.first?.isLetter == true { out.append("\\b\(NSRegularExpression.escapedPattern(for: r))[a-d]?\\b") }
        return out
    }

    /// Ulige or lige uger for a spot in a list: on its own line ("Ulige uger  D6a, D7a"), else the column
    /// heading above it nearest to the left or right. nil means every week.
    static func oddWeeks(at i: Int, x: CGFloat, lines: [Line]) -> Bool? {
        func kind(_ t: String) -> Bool? {
            guard let m = t.lowercased().firstMatch("\\b(u?lige)\\s+uger?\\b") else { return nil }
            return m[1] == "ulige"
        }
        if let k = lines[i].parts.compactMap({ kind($0.text) }).first { return k }
        for l in lines[..<i].reversed() where l.page == lines[i].page {
            let heads = l.parts.compactMap { p in kind(p.text).map { (p.x, $0) } }
            if let best = heads.min(by: { abs($0.0 - x) < abs($1.0 - x) }) { return best.1 }
        }
        return nil
    }

    /// The time for each weekday (Monday 0) from the lines on a page: "Dette skal I gøre mandag, onsdag,
    /// torsdag og fredag kl. 07:30", "hver tirsdag kl. 07:20", "Gang og toiletter kl. 7.30(tirsdag 7.20)".
    /// A time with no day named is Monday to Friday.
    static func dayTimes(page: Int, lines: [Line]) -> [Int: Int] {
        var general: [Int: Int] = [:], named: [Int: Int] = [:], special: [Int: Int] = [:]
        let days = dayNames.joined(separator: "|")
        for l in lines where l.page == page {
            var t = l.text.lowercased()
            // "(tirsdag 7.20)": one day at another time.
            while let m = t.firstMatch("\\(?\\b(\(days))\\s+(\\d{1,2})[.:](\\d{2})\\)?"),
                  let d = dayNames.firstIndex(of: m[1]), let h = Int(m[2]), let mi = Int(m[3]), h < 24, mi < 60,
                  let r = t.range(of: m[0]) {
                special[d] = h * 60 + mi
                t.removeSubrange(r)
            }
            guard let c = Deadlines.clock(in: t) else { continue }
            var mentioned = Set<Int>()
            if let n = Deadlines.dayCount(in: t), let first = t.firstMatch("\\b(\(days))\\s*(?:til|-|–)")?[1], let d0 = dayNames.firstIndex(of: first) {
                (0..<n).forEach { mentioned.insert((d0 + $0) % 7) }
            }
            for (i, d) in dayNames.enumerated() where t.range(of: "\\b\(d)", options: .regularExpression) != nil { mentioned.insert(i) }
            if mentioned.isEmpty { (0..<5).forEach { general[$0] = general[$0] ?? c.start } }
            else { mentioned.forEach { named[$0] = named[$0] ?? c.start } }
        }
        return general.merging(named) { $1 }.merging(special) { $1 }
    }

    /// Which area a page is about: "Rengøringsoversigt for" / "STORE HAL" → "Store hal", or the label just
    /// before your room on its line ("Drenge toiletter: D6a" → "Drenge toiletter").
    static func area(page: Int, lines: [Line], before: String) -> String? {
        func tidy(_ s: String) -> String? {
            let t = s.components(separatedBy: CharacterSet(charactersIn: "+(")).first?.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) ?? ""
            guard (3...30).contains(t.count) else { return nil }
            return t.lowercased().capFirst
        }
        let onPage = lines.filter { $0.page == page }
        if let k = onPage.firstIndex(where: { $0.text.lowercased().hasPrefix("rengøringsoversigt for") }) {
            let rest = String(onPage[k].text.dropFirst("rengøringsoversigt for".count))
            if let a = tidy(rest) { return a }
            if k + 1 < onPage.count, let a = tidy(onPage[k + 1].text) { return a }
        }
        if let m = before.firstMatch("([\\p{L}][\\p{L} ]{2,28}):[^:]*$") { return tidy(m[1]) }
        return nil
    }

    /// Your room in a list ("Buen 4 a Otto" or "B4a"): the days and times on that page, in the weeks it says,
    /// for the next four weeks.
    static func findRoom(house: String, room: String, lines: [Line], message: String, subject: String, posted: Date,
                         file: Int, thread: Int, fileName: String, now: Date = Date()) -> RosterHit? {
        let patterns = roomPatterns(house: house, room: room)
        guard !patterns.isEmpty else { return nil }
        for (i, l) in lines.enumerated() {
            for part in l.parts {
                guard let r = patterns.lazy.compactMap({ part.text.range(of: $0, options: .regularExpression) }).first else { continue }
                let spot = String(part.text[r])
                var times = dayTimes(page: l.page, lines: lines)
                if times.isEmpty, let c = Deadlines.clock(in: message) { (0..<5).forEach { times[$0] = c.start } }
                guard !times.isEmpty else { continue }
                let odd = oddWeeks(at: i, x: part.x, lines: lines)
                var slots: [RosterHit.Slot] = []
                let monday = DateUtil.mondayOf(now)
                for w in 0..<4 {
                    let start = DateUtil.add(.weekOfYear, w, monday)
                    if let odd, (DateUtil.cal.component(.weekOfYear, from: start) % 2 == 1) != odd { continue }
                    for (d, m) in times.sorted(by: { $0.key < $1.key }) {
                        let at = DateUtil.add(.day, d, start).addingTimeInterval(Double(m * 60))
                        slots.append(.init(start: at, end: at.addingTimeInterval(30 * 60)))
                    }
                }
                let short = ["man", "tirs", "ons", "tors", "fre", "lør", "søn"]
                // "man til fre kl. 7.30, tirs kl. 7.20": the common time first, the odd days after.
                let common = Dictionary(grouping: times.values, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 0
                let main = times.keys.sorted()
                let mainText = main == Array(0..<5) || main == Array(0..<7) ? "\(short[main.first!]) til \(short[main.last!])"
                    : main.map { short[$0] }.joined(separator: ", ")
                let odds = times.filter { $0.value != common }.sorted { $0.key < $1.key }.map { "\(short[$0.key]) kl. \(hm($0.value))" }
                let weeks = odd.map { $0 ? "ulige uger" : "lige uger" } ?? "hver uge"
                let summary = "\(spot), \(weeks), \(mainText) kl. \(hm(common))" + (odds.isEmpty ? "" : " (\(odds.joined(separator: ", ")))")
                var title = "\(subject) \(fileName)".lowercased().contains("rengøring") ? "Rengøring" : title(subject: subject, file: fileName)
                if let a = area(page: l.page, lines: lines, before: String(part.text[..<r.lowerBound])) { title += ": \(a)" }
                return RosterHit(file: file, thread: thread, title: title, summary: summary, slots: slots, from: subject)
            }
        }
        return nil
    }

    /// The Monday of week `w`, in the school year around `near`: "uge 1" written in November is next year.
    static func monday(ofWeek w: Int, near: Date) -> Date? {
        let cal = DateUtil.cal
        var year = cal.component(.yearForWeekOfYear, from: near)
        let now = cal.component(.weekOfYear, from: near)
        if w < now - 10 { year += 1 } else if w > now + 40 { year -= 1 }
        return cal.date(from: DateComponents(weekday: 2, weekOfYear: w, yearForWeekOfYear: year))
    }
}

/// Reads the PDFs of threads you have read (opened here, or read elsewhere and fetched ahead) once:
/// what it found with your name or room, and the text of each file for search.
@MainActor final class RosterStore: ObservableObject {
    static let shared = RosterStore()
    @Published var hits: [Int: [RosterHit]] = [:]
    /// The text of every PDF read, for search.
    @Published private(set) var texts: [Int: FileText] = [:]
    private var checked: Set<Int> = []
    /// Files already told about in a notification.
    private var notified: Set<Int>

    struct FileText: Codable, Hashable { let thread: Int; let name: String; let text: String }

    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ViggoPlus/Filer", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var textsURL: URL { dir.appendingPathComponent("tekst.json") }

    init() {
        notified = Set(UserDefaults.standard.array(forKey: "rosterNotified") as? [Int] ?? [])
        if let d = try? Data(contentsOf: textsURL), let t = try? JSONDecoder().decode([Int: FileText].self, from: d) { texts = t }
    }

    /// Only for threads that are read already: fetching their files changes nothing on Viggo.
    func check(_ d: ThreadDetail) async {
        guard let name = AppState.shared.profile?.name, !name.isEmpty else { return }
        var me = AppState.shared.profile.flatMap { Directory.shared.member($0.id) }
        for m in d.messages {
            for f in m.files where f.name.lowercased().hasSuffix(".pdf") || f.mime.contains("pdf") {
                guard !checked.contains(f.id) else { continue }
                checked.insert(f.id)
                let local = dir.appendingPathComponent("\(f.id).pdf")
                var data = try? Data(contentsOf: local)
                if data == nil {
                    let client = AppState.shared.client, url = f.url
                    data = await DownloadGate.shared.run { try? await client.data(url) }
                    if let data { try? data.write(to: local) }
                }
                guard let data, let doc = PDFDocument(data: data) else { continue }
                let lines = Roster.lines(doc)
                if texts[f.id] == nil {
                    texts[f.id] = FileText(thread: d.id, name: f.name, text: lines.map(\.text).joined(separator: "\n"))
                    if let j = try? JSONEncoder().encode(texts) { try? j.write(to: textsURL) }
                }
                let posted = m.sentAt ?? Date()
                if me == nil, let id = AppState.shared.profile?.id { await Directory.shared.load(); me = Directory.shared.member(id) }
                guard let hit = Roster.find(name: name, lines: lines, message: m.text, subject: d.subject, posted: posted,
                                            file: f.id, thread: d.id, fileName: f.name, from: m.author)
                    ?? me.flatMap({ Roster.findRoom(house: $0.house, room: $0.room, lines: lines, message: m.text, subject: d.subject,
                                                    posted: posted, file: f.id, thread: d.id, fileName: f.name) }) else { continue }
                var list = hits[d.id] ?? []
                list.removeAll { $0.file == f.id }
                list.append(hit)
                withAnimation(.viggo) { hits[d.id] = list }
                tell(hit, posted: posted)
            }
        }
    }

    /// "Du er på køkkenhold i uge 49" once per file, for lists sent in the last two weeks with times ahead.
    private func tell(_ h: RosterHit, posted: Date) {
        guard !notified.contains(h.file), posted > Date().addingTimeInterval(-14 * 86_400), let next = h.upcoming().first else { return }
        let when = next.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "da_DK")))
        let title = "📋 Du står på listen: \(h.title)", body = "\(h.summary.capFirst). Første gang \(when) kl. \(DateUtil.hm(next.start))."
        // For tests: print it instead, and remember nothing.
        if ProcessInfo.processInfo.environment["VIGGO_NO_NOTIFY"] != nil { print("[vagt] notifikation: \(title) | \(body)"); return }
        notified.insert(h.file)
        UserDefaults.standard.set(Array(notified), forKey: "rosterNotified")
        Notifier.shared.post(title, body, url: URL(string: "viggoplus://thread/\(h.thread)"))
    }

    // MARK: search

    struct TextHit: Identifiable, Hashable {
        var id: String { "\(thread)-\(file ?? "")" }
        let thread: Int
        let subject: String
        let sender: String
        /// The words around the match.
        let snippet: String
        /// The file it was found in, or nil for the message text.
        let file: String?
    }

    /// Matches in the text of read messages and their PDFs, one per thread and file, newest threads first.
    func search(_ raw: String, limit: Int = 20) -> [TextHit] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] }
        let inbox = Inbox.shared
        var out: [TextHit] = []
        let order = Dictionary(inbox.threads.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        for d in inbox.details.values.sorted(by: { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }) {
            if let m = d.messages.first(where: { $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                out.append(TextHit(thread: d.id, subject: d.subject, sender: m.author, snippet: Self.snippet(m.text, q), file: nil))
            }
            for (_, t) in texts.sorted(by: { $0.key < $1.key }) where t.thread == d.id && t.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                out.append(TextHit(thread: d.id, subject: d.subject, sender: d.messages.first?.author ?? "", snippet: Self.snippet(t.text, q), file: t.name))
            }
            if out.count >= limit { break }
        }
        return Array(out.prefix(limit))
    }

    static func snippet(_ text: String, _ q: String) -> String {
        // Bullets in PDFs are often private symbols that draw as a box with a question mark.
        let clean = String(String.UnicodeScalarView(text.unicodeScalars.map {
            $0.properties.generalCategory == .privateUse || $0 == "\u{FFFD}" ? " " : $0 }))
        let flat = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard let r = flat.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(flat.prefix(90)) }
        let start = flat.index(r.lowerBound, offsetBy: -40, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: 60, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end].trimmingCharacters(in: .whitespaces) + (end < flat.endIndex ? "…" : "")
    }
}

/// "Du står på listen" at the top of a thread whose PDF has your name: put every time in the schedule at once.
struct RosterCard: View {
    @ObservedObject private var store = RosterStore.shared
    @ObservedObject private var p = Prefs.shared
    let detail: ThreadDetail
    /// Space around it, only taken when there is something to show.
    var padding = EdgeInsets()
    var maxWidth: CGFloat? = nil

    var body: some View {
        // The thread view starts the check (RosterStore.check); this only shows what it found.
        let list = (store.hits[detail.id] ?? []).filter { !$0.upcoming().isEmpty }
        if !list.isEmpty {
            VStack(spacing: 8) {
                ForEach(list) { h in row(h, h.upcoming()) }
            }
            .frame(maxWidth: maxWidth)
            .padding(padding)
        }
    }

    private func planned(_ h: RosterHit, _ s: RosterHit.Slot) -> Bool {
        p.planned.contains { $0.title == h.title && abs($0.start.timeIntervalSince(s.start)) < 60 }
    }

    private func row(_ h: RosterHit, _ slots: [RosterHit.Slot]) -> some View {
        let on = slots.allSatisfy { planned(h, $0) }
        return HStack(spacing: 10) {
            Image(systemName: on ? "calendar.badge.checkmark" : "person.text.rectangle")
                .font(.system(size: 15, weight: .semibold, design: Fomo.design))
                .foregroundStyle(on ? Fomo.green : Fomo.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Fomo.surface2))
            VStack(alignment: .leading, spacing: 1) {
                Text(on ? "\(h.title) står i dit skema" : "Du står på listen: \(h.title)")
                    .font(.subheadline.weight(.semibold))
                Text(h.summary).font(.caption).foregroundStyle(Fomo.text2).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(on ? "Fjern" : slots.count == 1 ? "Sæt i skema" : "Sæt i skema (\(slots.count))") {
                let before = p.planned
                withAnimation(.viggo) {
                    if on {
                        p.planned.removeAll { i in i.title == h.title && slots.contains { abs($0.start.timeIntervalSince(i.start)) < 60 } }
                    } else {
                        for s in slots where !planned(h, s) {
                            p.planned.append(PlannedItem(title: h.title, start: s.start, end: s.end, from: h.from))
                        }
                    }
                }
                Haptic.tap()
                let n = slots.count
                StatusPill.shared.done(on ? "Fjernet fra skemaet" : n == 1 ? "Sat i skema" : "\(n) gange sat i skema") {
                    withAnimation(.viggo) { Prefs.shared.planned = before }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(on ? .secondary : Fomo.accent)
            .controlSize(.small)
        }
        .padding(10)
        .surface(14)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
