import Foundation
import SwiftUI

/// Pakkeliste. Teachers write what to bring into the lesson info ("Husk lommeregner") or into
/// a message or post ("Medbring idrætstøj på fredag"). This finds those sentences for a day,
/// adds what you put on the list yourself, and lets you tick things off as you pack.
///
/// It reads the same things as the Deadline-radar: lesson info, posts, threads you have read and
/// the subject and preview of unread ones. It never opens an unread thread.
struct PackItem: Identifiable, Hashable {
    let id: String
    /// What to bring, e.g. "Lommeregner".
    let text: String
    /// Where it came from, e.g. "Matematik · Thomas" or "Besked fra Keld".
    let from: String
    /// The sentence it was found in, empty for your own.
    let sentence: String
    /// Set for your own items, so they can be removed or repeated.
    var custom: PackStore.Custom?
}

@MainActor
final class PackStore: ObservableObject {
    static let shared = PackStore()

    /// Something you added. Without a subject it is for one day; with one, for every day with that subject.
    struct Custom: Codable, Hashable, Identifiable {
        var id = UUID()
        var text: String
        var day: String?
        var subject: String?
    }

    @Published private(set) var custom: [Custom] = []
    /// Ticked items per day ("2026-11-16": ids).
    @Published private(set) var ticked: [String: Set<String>] = [:]
    /// Found items you removed, so they do not come back.
    @Published private(set) var hidden: Set<String> = []

    private struct Store: Codable { var custom: [Custom]; var ticked: [String: Set<String>]; var hidden: Set<String> }
    private var url: URL { CookieJar.dir.appendingPathComponent("packing.json") }

    init() {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: data) else { return }
        custom = s.custom; ticked = s.ticked; hidden = s.hidden
    }

    private func save() {
        // Forget ticks older than a week.
        let cut = DateUtil.ymd(DateUtil.add(.day, -7, Date()))
        ticked = ticked.filter { $0.key >= cut }
        custom.removeAll { $0.subject == nil && ($0.day ?? "") < cut }
        if let data = try? JSONEncoder().encode(Store(custom: custom, ticked: ticked, hidden: hidden)) {
            try? data.write(to: url, options: .atomic)
        }
        #if os(iOS)
        AppState.shared.scheduleAhead()
        #endif
    }

    func isTicked(_ item: PackItem, on day: Date) -> Bool { ticked[DateUtil.ymd(day)]?.contains(item.id) == true }

    func toggle(_ item: PackItem, on day: Date) {
        let k = DateUtil.ymd(day)
        var s = ticked[k] ?? []
        if s.remove(item.id) == nil { s.insert(item.id) }
        ticked[k] = s
        save()
    }

    func add(_ text: String, on day: Date) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        custom.append(Custom(text: t.capFirst, day: DateUtil.ymd(day)))
        save()
    }

    /// Every day with this subject, or (without one) only this day.
    func repeatEvery(_ c: Custom, subject: String?, day: Date) {
        guard let i = custom.firstIndex(where: { $0.id == c.id }) else { return }
        custom[i].subject = subject
        custom[i].day = subject == nil ? DateUtil.ymd(day) : nil
        save()
    }

    func remove(_ item: PackItem) {
        if let c = item.custom { custom.removeAll { $0.id == c.id } } else { hidden.insert(item.id) }
        save()
    }

    func clear() {
        custom = []; ticked = [:]; hidden = []
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: what to bring on a day

    /// Found items, then your own. Ticked ones are kept, so you can see what is packed.
    func items(on day: Date) -> [PackItem] {
        let s = AppState.shared
        var out: [PackItem] = []
        func add(_ i: PackItem) {
            guard !hidden.contains(i.id), !out.contains(where: { $0.id == i.id || $0.text.lowercased() == i.text.lowercased() }) else { return }
            out.append(i)
        }
        let lessons = s.items(on: day).filter { $0.kind == .lesson || $0.kind == .event }
        // The teacher's info for the day's lessons.
        for e in lessons where e.hasInfo {
            for sentence in Deadlines.sentences(e.notes) {
                guard let thing = Self.thing(in: sentence) else { continue }
                let who = e.teachers.first.map { " · \($0.components(separatedBy: " ").first ?? $0)" } ?? ""
                add(PackItem(id: "lektion:\(e.key)|\(thing.lowercased())", text: thing, from: e.shortTitle + who, sentence: sentence))
            }
        }
        // Posts and messages that point at the day.
        let now = Date()
        func scan(_ text: String, subject: String, when: String, source: String, from: String) {
            let posted = Deadlines.postedDate(when, now: now) ?? now
            for sentence in [subject] + Deadlines.sentences(text) {
                guard let thing = Self.thing(in: sentence), let d = Deadlines.day(in: sentence, posted: posted),
                      DateUtil.cal.isDate(d, inSameDayAs: day) else { continue }
                add(PackItem(id: "\(source)|\(thing.lowercased())", text: thing, from: from, sentence: sentence))
            }
        }
        for b in s.bulletins {
            scan(b.body.isEmpty ? b.text : b.body, subject: b.title, when: b.when, source: "opslag:\(b.id)", from: "Opslag fra \(b.author.firstWord)")
        }
        let inbox = Inbox.shared
        for d in inbox.details.values {
            let me = s.profile?.id
            for m in d.messages where m.authorID != me {
                scan(m.text, subject: d.subject, when: m.date, source: "tråd:\(d.id)", from: "Besked fra \(m.author.firstWord)")
            }
        }
        for t in inbox.threads where inbox.details[t.id] == nil {
            scan(t.preview, subject: t.subject, when: t.when, source: "tråd:\(t.id)", from: "Besked fra \(t.sender.firstWord)")
        }
        // Your own: for this day, or for a subject the day has.
        let key = DateUtil.ymd(day)
        let subjects = Set(lessons.map { Self.subject(of: $0) })
        for c in custom where c.day == key || c.subject.map(subjects.contains) == true {
            add(PackItem(id: "egen:\(c.id)", text: c.text, from: c.subject.map { "Hver gang der er \($0)" } ?? "Din egen", sentence: "", custom: c))
        }
        return out
    }

    /// What a subject is called for "every time there is ...": the lesson's short title.
    static func subject(of e: ViggoEvent) -> String { e.shortTitle }

    /// Subjects on a day, for repeating your own item.
    func subjects(on day: Date) -> [String] {
        var seen: [String] = []
        for e in AppState.shared.items(on: day) where e.kind == .lesson {
            let s = Self.subject(of: e)
            if !seen.contains(s) { seen.append(s) }
        }
        return seen
    }

    // MARK: reading Danish

    /// "Husk lommeregner", "Husk at medbringe idrætstøj", "Medbring en kuglepen", "Tag computeren med",
    /// "I skal have høretelefoner med". Not "Husk at aflevere" or "Husk at læse s. 20": those are tasks.
    static func thing(in raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "(?i)(?:^|[^\\p{L}])(?:husk(?:\\s+at)?\\s+(?:medbringe|tage|have|at\\s+tage)|medbring(?:e)?|ta(?:g|')(?=\\s+.+\\bmed\\b)|(?:i|du|vi)\\s+skal\\s+(?:have|tage|bruge|medbringe)|husk)\\s+(.+)",
        ]
        // Every place in the sentence: "Husk at forberede dig + medbringe evalueringen" has the thing second.
        for p in patterns {
            var rest = s
            while let m = rest.firstMatch(p) {
                if let t = clean(m[1]) { return t }
                guard let r = rest.range(of: m[0]) else { break }
                rest = String(rest[rest.index(after: r.lowerBound)...])
            }
        }
        return nil
    }

    private static func clean(_ found: String) -> String? {
        var t = found
        // Up to the end of the clause.
        if let r = t.range(of: "(?i)\\s+(?:med\\b|til\\s+(?:timen|i\\s+morgen|på)|i\\s+morgen|på\\s+(?:mandag|tirsdag|onsdag|torsdag|fredag|lørdag|søndag)|kl\\.?\\s*\\d)|[.!?;:(+]|\\s+-\\s+|\\s+og\\s+(?:husk|så|vi|i|du)\\b",
                              options: .regularExpression) {
            t = String(t[..<r.lowerBound])
        }
        // A list ("penalhus, lineal og vinkelmåler") stays whole; otherwise a comma ends it.
        if let comma = t.firstIndex(of: ","), !t[comma...].contains(" og ") { t = String(t[..<comma]) }
        if t == t.uppercased() { t = t.lowercased() }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        t = t.replacingOccurrences(of: "(?i)^(?:jeres|din|dit|dine|jer|en|et|egen|eget|egne)\\s+", with: "", options: .regularExpression)
        let lower = t.lowercased()
        // "Husk at aflevere", "husk at læse": a task, not a thing.
        if Self.notThings.contains(lower) || Self.notThings.contains(lower.firstWord) || lower.hasPrefix("at ") || taskWords.contains(where: { lower.hasPrefix($0) }) { return nil }
        guard t.count >= 3, t.count <= 64, t.split(separator: " ").count <= 8 else { return nil }
        return t.capFirst
    }

    /// Small words and "I skal have gjort/læst", which are about a task.
    private static let notThings: Set<String> = ["fri", "den", "det", "dem", "dig", "jer", "mig", "sig", "til", "med", "fra", "om", "noget",
                                                 "gjort", "læst", "lavet", "skrevet", "afleveret", "set", "hørt", "forberedt", "klaret", "øvet"]

    private static let taskWords = ["deadline", "aflever", "tilmeld", "afmeld", "framel", "betal", "indbetal", "læs", "lav ", "svar", "skriv",
                                    "upload", "send", "kom ", "møde", "mød ", "vær ", "være", "at ", "jer ", "dig ", "det ", "den ", "der ", "hvis",
                                    "vi ", "i ", "du ", "også", "lige", "nu ", "så ", "på ", "til ", "kl", "frist"]
}

extension String {
    var firstWord: String { components(separatedBy: " ").first ?? self }
}

// MARK: - the card, shared by I dag and Uge

#if os(iOS)
struct PackCard: View {
    @ObservedObject private var store = PackStore.shared
    @EnvironmentObject var state: AppState
    let day: Date
    var title = "Pak"
    @State private var adding = ""
    @FocusState private var typing: Bool

    var body: some View {
        let items = store.items(on: day)
        let left = items.filter { !store.isTicked($0, on: day) }.count
        Card(title: title, icon: "backpack.fill", badge: left) {
            VStack(spacing: 0) {
                ForEach(items) { row($0) }
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint)
                    TextField("Tilføj noget at huske", text: $adding)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit {
                            withAnimation(.viggo) { store.add(adding, on: day) }
                            adding = ""
                        }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func row(_ i: PackItem) -> some View {
        let done = store.isTicked(i, on: day)
        return HStack(spacing: 12) {
            Button { Haptic.tap(); withAnimation(.viggo) { store.toggle(i, on: day) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressScale(scale: 0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text(i.text).font(.body).strikethrough(done).foregroundStyle(done ? .secondary : .primary).lineLimit(2)
                Text(i.from).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if !i.sentence.isEmpty { Text(i.sentence) }
            if let c = i.custom {
                if c.subject == nil {
                    ForEach(store.subjects(on: day), id: \.self) { s in
                        Button("Hver gang der er \(s)", systemImage: "repeat") { store.repeatEvery(c, subject: s, day: day) }
                    }
                } else {
                    Button("Kun denne dag", systemImage: "calendar") { store.repeatEvery(c, subject: nil, day: day) }
                }
            }
            Button("Fjern", systemImage: "trash", role: .destructive) { withAnimation(.viggo) { store.remove(i) } }
        }
    }
}
#endif
