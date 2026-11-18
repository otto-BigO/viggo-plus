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
    struct Line { let page: Int; let y: CGFloat; let text: String }

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
                out.append(Line(page: i, y: r[0].y, text: r.sorted { $0.x < $1.x }.map(\.s).joined(separator: " ")))
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

    /// The Monday of week `w`, in the school year around `near`: "uge 1" written in November is next year.
    static func monday(ofWeek w: Int, near: Date) -> Date? {
        let cal = DateUtil.cal
        var year = cal.component(.yearForWeekOfYear, from: near)
        let now = cal.component(.weekOfYear, from: near)
        if w < now - 10 { year += 1 } else if w > now + 40 { year -= 1 }
        return cal.date(from: DateComponents(weekday: 2, weekOfYear: w, yearForWeekOfYear: year))
    }
}

/// Fetches the PDFs of an opened thread once and keeps what it found with your name.
@MainActor final class RosterStore: ObservableObject {
    static let shared = RosterStore()
    @Published var hits: [Int: [RosterHit]] = [:]
    private var checked: Set<Int> = []

    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ViggoPlus/Filer", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// The thread is open, so it is read already: fetching its files changes nothing on Viggo.
    func check(_ d: ThreadDetail) async {
        guard let name = AppState.shared.profile?.name, !name.isEmpty else { return }
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
                if let hit = Roster.find(name: name, lines: lines, message: m.text, subject: d.subject, posted: m.sentAt ?? Date(),
                                         file: f.id, thread: d.id, fileName: f.name, from: m.author) {
                    var list = hits[d.id] ?? []
                    list.removeAll { $0.file == f.id }
                    list.append(hit)
                    withAnimation(.viggo) { hits[d.id] = list }
                }
            }
        }
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.green : Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill((on ? Color.green : Color.accentColor).opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(on ? "\(h.title) står i dit skema" : "Du står på listen: \(h.title)")
                    .font(.subheadline.weight(.semibold))
                Text(h.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(on ? "Fjern" : slots.count == 1 ? "Sæt i skema" : "Sæt i skema (\(slots.count))") {
                withAnimation(.viggo) {
                    if on {
                        p.planned.removeAll { i in i.title == h.title && slots.contains { abs($0.start.timeIntervalSince(i.start)) < 60 } }
                    } else {
                        for s in slots where !planned(h, s) {
                            p.planned.append(PlannedItem(title: h.title, start: s.start, end: s.end, from: h.from))
                        }
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(on ? .secondary : .accentColor)
            .controlSize(.small)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.07))
        }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.2)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
