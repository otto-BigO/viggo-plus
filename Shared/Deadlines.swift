import Foundation
import SwiftUI

/// Deadline-radar. Teachers write deadlines into ordinary messages and posts ("Husk deadline
/// for tilmelding er i dag kl. 13.00"), and Viggo never puts them anywhere. This reads the
/// Danish text, finds the date and time, and keeps a list with reminders.
///
/// What it may read: posts (full text), threads you have already read (full text) and the
/// subject and preview of unread threads. It never opens an unread thread, since Viggo would
/// mark it read and show the sender "Læst af".
struct Deadline: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let due: Date
    let hasTime: Bool
    /// "tråd:250710" or "opslag:<bulletin id>".
    let source: String
    let sourceTitle: String
    let from: String
    /// The sentence the deadline was found in.
    let snippet: String
    var found: Date

    var threadID: Int? { source.hasPrefix("tråd:") ? Int(source.dropFirst(5)) : nil }
    var bulletinID: String? { source.hasPrefix("opslag:") ? String(source.dropFirst(7)) : nil }

    /// When it stops being upcoming: the time, or the end of the day without one.
    var end: Date { hasTime ? due : DateUtil.add(.day, 1, DateUtil.startOfDay(due)) }

    private static let dayF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEE d. MMM"; return f
    }()

    /// "I dag kl. 13.00", "I morgen", "Fre. 20. nov kl. 9.55".
    func whenText(now: Date = Date()) -> String {
        let days = DateUtil.cal.dateComponents([.day], from: DateUtil.startOfDay(now), to: DateUtil.startOfDay(due)).day ?? 0
        let day: String
        switch days {
        case 0: day = "I dag"
        case 1: day = "I morgen"
        case -1: day = "I går"
        default:
            let s = Self.dayF.string(from: due).replacingOccurrences(of: ".$", with: "", options: .regularExpression)
            day = s.prefix(1).uppercased() + s.dropFirst()
        }
        guard hasTime else { return day }
        let c = DateUtil.cal.dateComponents([.hour, .minute], from: due)
        return "\(day) kl. \(c.hour ?? 0).\(String(format: "%02d", c.minute ?? 0))"
    }
}

@MainActor
final class Deadlines: ObservableObject {
    static let shared = Deadlines()

    @Published private(set) var all: [Deadline] = []
    @Published private(set) var done: Set<String> = []
    @Published private(set) var dismissed: Set<String> = []
    /// Reminders already shown on the Mac ("id|aften", "id|snart").
    private var reminded: Set<String> = []
    /// Nothing is announced on the very first scan, or a fresh install would ping for every old message.
    private var initialized = false

    private var url: URL { CookieJar.dir.appendingPathComponent("deadlines.json") }

    private struct Store: Codable {
        var all: [Deadline]; var done: Set<String>; var dismissed: Set<String>
        var reminded: Set<String>; var initialized: Bool
    }

    init() {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: data) else { return }
        all = s.all; done = s.done; dismissed = s.dismissed; reminded = s.reminded; initialized = s.initialized
    }

    private func save() {
        let s = Store(all: all, done: done, dismissed: dismissed, reminded: reminded, initialized: initialized)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
    }

    /// Not done, not removed, and not more than a day past.
    func upcoming(now: Date = Date()) -> [Deadline] {
        all.filter { !done.contains($0.id) && !dismissed.contains($0.id) && $0.end > now.addingTimeInterval(-86_400) }
            .sorted { $0.due < $1.due }
    }

    func deadlines(from source: String) -> [Deadline] { all.filter { $0.source == source }.sorted { $0.due < $1.due } }
    func isActive(_ d: Deadline) -> Bool { !done.contains(d.id) && !dismissed.contains(d.id) }

    func toggleDone(_ d: Deadline) {
        if done.remove(d.id) == nil { done.insert(d.id) }
        changed()
    }

    func dismiss(_ d: Deadline) { dismissed.insert(d.id); done.remove(d.id); changed() }
    func restore(_ d: Deadline) { dismissed.remove(d.id); done.remove(d.id); changed() }

    private func changed() {
        save()
        #if os(iOS)
        AppState.shared.scheduleAhead()
        #endif
    }

    /// Made-up deadlines for the doc pictures. Not saved.
    func showDemo(_ list: [Deadline]) { all = list; done = []; dismissed = [] }

    // MARK: scanning

    /// Everything Viggo+ already has: posts, the inbox previews and the threads it has open.
    func scanAll(now: Date = Date()) {
        let s = AppState.shared
        var found: [Deadline] = []
        for b in s.bulletins {
            found += Self.find(in: b.body.isEmpty ? b.text : b.body, subject: b.title, posted: Self.postedDate(b.when, now: now) ?? now,
                               source: "opslag:\(b.id)", from: b.author, now: now)
        }
        let inbox = Inbox.shared
        for m in s.messages where inbox.details[m.id] == nil {
            found += Self.find(in: m.preview, subject: m.subject, posted: Self.postedDate(m.when, now: now) ?? now,
                               source: "tråd:\(m.id)", from: m.sender, now: now)
        }
        for t in inbox.threads where inbox.details[t.id] == nil {
            found += Self.find(in: t.preview, subject: t.subject, posted: Self.postedDate(t.when, now: now) ?? now,
                               source: "tråd:\(t.id)", from: t.sender, now: now)
        }
        for d in inbox.details.values { found += Self.find(in: d, now: now) }
        // For screenshots and checking the screens: VIGGO_DEADLINE_DEMO=1 puts a made-up deadline on the
        // newest read thread, tomorrow at 13.00.
        if ProcessInfo.processInfo.environment["VIGGO_DEADLINE_DEMO"] != nil, let t = inbox.threads.first(where: { !$0.unread }) ?? inbox.threads.first,
           let due = DateUtil.cal.date(bySettingHour: 13, minute: 0, second: 0, of: DateUtil.add(.day, 1, now)) {
            found.append(Deadline(id: "tråd:\(t.id)|demo", title: "Tilmelding til weekenden", due: due, hasTime: true, source: "tråd:\(t.id)",
                                  sourceTitle: t.subject, from: t.sender, snippet: "Husk deadline for tilmelding i morgen kl. 13.00", found: now))
        }
        add(found, now: now)
    }

    /// One thread, when it is opened or fetched ahead.
    func scan(_ d: ThreadDetail, now: Date = Date()) { add(Self.find(in: d, now: now), now: now) }

    private func add(_ list: [Deadline], now: Date) {
        let known = Set(all.map(\.id))
        var fresh: [Deadline] = []
        for d in list where !known.contains(d.id) && !fresh.contains(where: { $0.id == d.id }) {
            // A thread seen first by its preview and then in full may give the same deadline with a
            // better title or a time. Keep one per source and day.
            if let i = all.firstIndex(where: { $0.source == d.source && DateUtil.cal.isDate($0.due, inSameDayAs: d.due) }) {
                if d.hasTime && !all[i].hasTime { all[i] = Deadline(id: all[i].id, title: all[i].title, due: d.due, hasTime: true, source: d.source,
                                                                     sourceTitle: d.sourceTitle, from: d.from, snippet: d.snippet, found: all[i].found) }
                continue
            }
            fresh.append(d)
        }
        // Forget ones that are long past.
        all.removeAll { $0.end < now.addingTimeInterval(-14 * 86_400) }
        guard !fresh.isEmpty || !initialized else { save(); return }
        all += fresh
        if initialized, Prefs.shared.deadlineRadar {
            let upcoming = fresh.filter { $0.end > now }
            if upcoming.count == 1, let d = upcoming.first {
                Notifier.shared.post("📌 Ny deadline: \(d.title)", "\(d.whenText(now: now)) · \(d.snippet)", url: nil)
            } else if upcoming.count > 1 {
                Notifier.shared.post("📌 \(upcoming.count) nye deadlines", upcoming.prefix(4).map { "• \($0.title), \($0.whenText(now: now).lowercased())" }.joined(separator: "\n"), url: nil)
            }
        }
        initialized = true
        save()
        #if os(iOS)
        if !fresh.isEmpty { AppState.shared.scheduleAhead() }
        #endif
    }

    // MARK: reminders

    /// The evening before at the homework reminder time, and 2 hours before (or the morning of the day).
    func reminders(now: Date = Date()) -> [(at: Date, id: String, title: String, body: String)] {
        guard Prefs.shared.deadlineRadar else { return [] }
        var out: [(Date, String, String, String)] = []
        let p = Prefs.shared
        for d in upcoming(now: now) where d.end > now {
            let day = DateUtil.startOfDay(d.due)
            if let eve = DateUtil.cal.date(bySettingHour: p.homeworkReminderAt / 60, minute: p.homeworkReminderAt % 60, second: 0, of: DateUtil.add(.day, -1, day)) {
                out.append((eve, "\(d.id)|aften", "📌 Deadline i morgen: \(d.title)", "\(d.whenText(now: eve)) · \(d.from)"))
            }
            let soon = d.hasTime ? d.due.addingTimeInterval(-2 * 3600)
                : DateUtil.cal.date(bySettingHour: p.morningHour, minute: 2, second: 0, of: day) ?? day
            out.append((max(soon, day), "\(d.id)|snart", d.hasTime ? "📌 Deadline om 2 timer: \(d.title)" : "📌 Deadline i dag: \(d.title)",
                        "\(d.whenText(now: day)) · \(d.snippet)"))
        }
        return out.filter { $0.0 > now }.map { (at: $0.0, id: $0.1, title: $0.2, body: $0.3) }
    }

    /// The Mac shows reminders itself when their time has come (the iPhone hands them to iOS).
    func tick(now: Date = Date()) {
        guard Prefs.shared.deadlineRadar else { return }
        var any = false
        for r in reminders(now: now.addingTimeInterval(-10 * 60)) where r.at <= now && !reminded.contains(r.id) {
            reminded.insert(r.id)
            any = true
            Notifier.shared.post(r.title, r.body)
        }
        if any { save() }
    }

    // MARK: reading Danish

    static func find(in d: ThreadDetail, now: Date) -> [Deadline] {
        // The first message sets the subject; later answers ("Det er rykket til fredag") count too.
        // Your own messages are left out: "jeg nåede ikke at tilmelde mig inden kl. 13" is no deadline.
        let me = AppState.shared.profile?.id
        return d.messages.enumerated().flatMap { i, m -> [Deadline] in
            guard m.authorID != me else { return [] }
            return find(in: m.text, subject: d.subject, posted: postedDate(m.date, now: now) ?? now,
                        source: "tråd:\(d.id)", from: m.author, now: now, readSubject: i == 0)
        }
    }

    private static let trigger = try! NSRegularExpression(pattern:
        "(?i)\\b(deadline|frist|senest|seneste|aflever\\w*|tilmeld\\w*|framel\\w*|afmeld\\w*|betal\\w*|indbetal\\w*|husk\\w*|inden|skal\\s+(?:være|have|sendes|uploades|afleveres)|sidste\\s+(?:dag|chance|frist))\\b")

    private static let weekdays = ["mandag": 2, "tirsdag": 3, "onsdag": 4, "torsdag": 5, "fredag": 6, "lørdag": 7, "søndag": 1]
    private static let months: [String: Int] = ["januar": 1, "februar": 2, "marts": 3, "april": 4, "maj": 5, "juni": 6, "juli": 7, "august": 8,
                                                "september": 9, "oktober": 10, "november": 11, "december": 12, "jan": 1, "feb": 2, "mar": 3,
                                                "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "okt": 10, "nov": 11, "dec": 12]

    /// Deadlines in one text. Every sentence with a deadline word and a date or a time counts.
    static func find(in text: String, subject: String, posted: Date, source: String, from: String, now: Date,
                     readSubject: Bool = true) -> [Deadline] {
        var out: [Deadline] = []
        let sentences = (readSubject ? [subject] : []) + Self.sentences(text)
        for s in sentences {
            let r = NSRange(s.startIndex..., in: s)
            guard trigger.firstMatch(in: s, range: r) != nil else { continue }
            let time = Self.time(in: s)
            var day = Self.day(in: s, posted: posted)
            if day == nil, time != nil { day = DateUtil.startOfDay(posted) }
            guard let day else { continue }
            var due = day
            if let (h, m) = time { due = DateUtil.cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
            let end = time != nil ? due : DateUtil.add(.day, 1, day)
            guard end > now else { continue }
            let snippet = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = time != nil ? DateUtil.iso.string(from: due) : DateUtil.ymd(due)
            let d = Deadline(id: "\(source)|\(key)", title: title(subject: subject, sentence: snippet), due: due, hasTime: time != nil,
                             source: source, sourceTitle: subject, from: from, snippet: String(snippet.prefix(160)), found: now)
            if let i = out.firstIndex(where: { DateUtil.cal.isDate($0.due, inSameDayAs: due) }) {
                if d.hasTime && !out[i].hasTime { out[i] = d }
            } else {
                out.append(d)
            }
        }
        return out
    }

    /// Splits at line breaks and at a full stop followed by a capital letter, so "kl. 13.00" and
    /// "d. 20. nov" stay whole.
    static func sentences(_ text: String) -> [String] {
        text.replacingOccurrences(of: "([.!?])\\s+(?=\\p{Lu})", with: "$1\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 3 }
    }

    /// "kl. 13.00", "kl 9.55", "kl. 13", "13:00".
    static func time(in s: String) -> (Int, Int)? {
        if let m = s.firstMatch("(?i)\\bkl\\.?\\s*(\\d{1,2})(?:[.:](\\d{2}))?"), let h = Int(m[1]), h < 24 {
            let min = Int(m[2]) ?? 0
            return min < 60 ? (h, min) : nil
        }
        if let m = s.firstMatch("\\b(\\d{1,2}):(\\d{2})\\b"), let h = Int(m[1]), let min = Int(m[2]), h < 24, min < 60 { return (h, min) }
        return nil
    }

    /// The day a sentence points at, counted from when it was written.
    static func day(in raw: String, posted: Date) -> Date? {
        let s = raw.lowercased()
        let base = DateUtil.startOfDay(posted)
        // "20. november", "20 nov", "d. 3. dec 2026".
        let monthNames = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let m = s.firstMatch("\\b(\\d{1,2})\\.?\\s*(\(monthNames))\\b\\.?(?:\\s*(\\d{4}))?"), let d = Int(m[1]), let mo = months[m[2]] {
            return date(d, mo, Int(m[3]), base)
        }
        // "20/11", "20/11-26", "d. 20.11", "20.11.2026". A plain "13.00" is a time, so a dot date
        // needs "d."/"den" before it or a year after it.
        if let m = s.firstMatch("\\b(\\d{1,2})/(\\d{1,2})(?:[/-](\\d{2,4}))?\\b"), let d = Int(m[1]), let mo = Int(m[2]) {
            if let r = date(d, mo, m[3].isEmpty ? nil : Int(m[3]), base) { return r }
        }
        if let m = s.firstMatch("\\b(?:d\\.|den)\\s*(\\d{1,2})\\.(\\d{1,2})\\b"), let d = Int(m[1]), let mo = Int(m[2]) {
            if let r = date(d, mo, nil, base) { return r }
        }
        if let m = s.firstMatch("\\b(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2,4})\\b"), let d = Int(m[1]), let mo = Int(m[2]) {
            if let r = date(d, mo, Int(m[3]), base) { return r }
        }
        if s.firstMatch("\\bi\\s+overmorgen\\b") != nil { return DateUtil.add(.day, 2, base) }
        if s.firstMatch("\\bi\\s+morgen\\b") != nil { return DateUtil.add(.day, 1, base) }
        if s.firstMatch("\\bi\\s+(?:dag|aften|eftermiddag|formiddag)\\b") != nil { return base }
        // "på fredag", "fredag d.", "næste mandag".
        if let m = s.firstMatch("\\b(næste\\s+)?(mandag|tirsdag|onsdag|torsdag|fredag|lørdag|søndag)\\b"), let wd = weekdays[m[2]] {
            let now = DateUtil.cal.component(.weekday, from: base)
            var ahead = (wd - now + 7) % 7
            if !m[1].isEmpty && ahead == 0 { ahead = 7 }
            return DateUtil.add(.day, ahead, base)
        }
        if s.firstMatch("\\b(?:i\\s+)?weekenden\\b") != nil, s.contains("inden") || s.contains("senest") || s.contains("deadline") {
            let now = DateUtil.cal.component(.weekday, from: base)
            return DateUtil.add(.day, (6 - now + 7) % 7, base) // the Friday
        }
        return nil
    }

    private static func date(_ d: Int, _ mo: Int, _ y: Int?, _ base: Date) -> Date? {
        guard (1...31).contains(d), (1...12).contains(mo) else { return nil }
        var year = y.map { $0 < 100 ? 2000 + $0 : $0 } ?? DateUtil.cal.component(.year, from: base)
        guard var r = DateUtil.cal.date(from: DateComponents(year: year, month: mo, day: d)),
              DateUtil.cal.component(.day, from: r) == d else { return nil }
        // "15/1" written in December is next year.
        if y == nil, r < DateUtil.add(.day, -60, base) {
            year += 1
            r = DateUtil.cal.date(from: DateComponents(year: year, month: mo, day: d)) ?? r
        }
        return r
    }

    private static let generic: Set<String> = ["svar", "hej", "info", "information", "besked", "vigtigt", "husk", "deadline", "påmindelse", "reminder", "vedr", "re", "fw"]

    /// The subject without "- deadline kl. 9.55", unless it says nothing; then the sentence.
    static func title(subject: String, sentence: String) -> String {
        var t = subject.replacingOccurrences(of: "(?i)^\\s*(sv|re|fw|vs):\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)\\s*[-–:,]?\\s*(deadline|frist|husk).*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if t.count >= 3, !generic.contains(t.lowercased()) { return t }
        var s = sentence.replacingOccurrences(of: "(?i)^(kære|hej)\\s+[^.,!]*[.,!]?\\s*", with: "", options: .regularExpression)
        if s.isEmpty { s = sentence }
        return s.count > 60 ? String(s.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" : s
    }

    /// "10. nov 2026 12:49", "6 timer siden", "i går 14:02", "12:49".
    static func postedDate(_ when: String, now: Date = Date()) -> Date? {
        let w = when.lowercased()
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "maj": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "okt": 10, "nov": 11, "dec": 12]
        if let m = w.firstMatch("(\\d{1,2})\\.\\s*(\\w{3})\\w*\\.?\\s*(\\d{4})(?:\\s+(\\d{1,2})[:.](\\d{2}))?"), let d = Int(m[1]), let mo = months[m[2]], let y = Int(m[3]) {
            return DateUtil.cal.date(from: DateComponents(year: y, month: mo, day: d, hour: Int(m[4]) ?? 12, minute: Int(m[5]) ?? 0))
        }
        if let m = w.firstMatch("(\\d+)\\s*(minut|min|time|sekund)"), let n = Int(m[1]) {
            let unit: Double = m[2].hasPrefix("time") ? 3600 : m[2].hasPrefix("sekund") ? 1 : 60
            return now.addingTimeInterval(-Double(n) * unit)
        }
        if w.contains("siden") || w.contains("lige nu") { return now }
        let base = w.contains("i går") ? DateUtil.add(.day, -1, now) : now
        if let m = w.firstMatch("(\\d{1,2})[:.](\\d{2})"), let h = Int(m[1]), let mi = Int(m[2]) {
            return DateUtil.cal.date(bySettingHour: h, minute: mi, second: 0, of: base)
        }
        return w.contains("i går") || w.contains("i dag") ? base : nil
    }
}

// MARK: - views shared by both apps

/// "Viggo+ fandt en deadline" at the top of a message or post, with Påmind mig / Fjern.
struct DeadlineSuggestion: View {
    @ObservedObject private var store = Deadlines.shared
    let source: String

    var body: some View {
        let list = store.deadlines(from: source).filter { $0.end > Date() }
        if !list.isEmpty {
            VStack(spacing: 8) {
                ForEach(list) { d in row(d) }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func row(_ d: Deadline) -> some View {
        let on = store.isActive(d)
        return HStack(spacing: 10) {
            Image(systemName: on ? "pin.fill" : "pin.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.orange : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.orange.opacity(on ? 0.16 : 0.07)))
            VStack(alignment: .leading, spacing: 1) {
                Text(on ? "Deadline \(d.whenText().lowercasedFirst)" : "Deadline fundet")
                    .font(.subheadline.weight(.semibold))
                Text(on ? "Viggo+ minder dig om den" : "\(d.whenText()) · ikke på din liste")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(on ? "Fjern" : "Påmind mig") {
                withAnimation(.viggo) { on ? store.dismiss(d) : store.restore(d) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(on ? .secondary : .orange)
            .controlSize(.small)
        }
        .padding(10)
        .background {
            // Solid underneath, so it can sit over a scrolling thread.
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.22)))
    }
}

/// One deadline in a list: tick it off, see when and from whom.
struct DeadlineRow: View {
    @ObservedObject private var store = Deadlines.shared
    let d: Deadline
    var compact = false

    var body: some View {
        let isDone = store.done.contains(d.id)
        let late = !isDone && d.end < Date()
        let soon = !isDone && !late && d.due.timeIntervalSinceNow < 86_400
        HStack(spacing: compact ? 8 : 12) {
            Button { withAnimation(.viggo) { store.toggleDone(d) } } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 15 : 20))
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(d.title).font(compact ? .system(size: 12, weight: .medium) : .subheadline.weight(.semibold))
                    .strikethrough(isDone).lineLimit(1)
                Text(d.from.isEmpty ? d.sourceTitle : d.from)
                    .font(compact ? .system(size: 10) : .caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(late ? "Overskredet" : d.whenText())
                .font(compact ? .system(size: 11, weight: .semibold) : .caption.weight(.semibold))
                .foregroundStyle(late ? Color.red : soon ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
        .opacity(isDone ? 0.55 : 1)
        .contextMenu {
            Button(isDone ? "Ikke færdig" : "Færdig", systemImage: "checkmark") { store.toggleDone(d) }
            Button("Fjern fra listen", systemImage: "trash", role: .destructive) { withAnimation(.viggo) { store.dismiss(d) } }
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}
