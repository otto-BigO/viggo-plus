import SwiftUI

/// A time or day in a message, ready to go in the schedule: the title from the subject (or the
/// sentence), the day and the time all filled in from what the message says.
struct PlanDraft: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var start: Date
    var end: Date
    /// False when the message gave a day but no time; the time is then a guess to change.
    var timed: Bool
    var from: String
    /// Days in a row ("mandag til fredag" is 5): one item in the schedule for each.
    var days = 1

    static let scheme = "viggoplus-day"

    /// A link for one spot: viggoplus-day://<day>?s=<start>&e=<end>&t=<title>&f=<subject>.
    static func link(for s: Deadlines.Spot, title: String, subject: String) -> URL? {
        guard let d = s.day else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = "\(Int(d.timeIntervalSince1970))"
        c.queryItems = [URLQueryItem(name: "t", value: title), URLQueryItem(name: "f", value: subject)]
            + (s.start.map { [URLQueryItem(name: "s", value: "\(Int($0.timeIntervalSince1970))")] } ?? [])
            + (s.end.map { [URLQueryItem(name: "e", value: "\(Int($0.timeIntervalSince1970))")] } ?? [])
            + (s.days > 1 ? [URLQueryItem(name: "n", value: "\(s.days)")] : [])
        return c.url
    }

    /// The day the link points at.
    static func day(of url: URL) -> Date? {
        guard url.scheme == scheme, let t = Double(url.host ?? "") else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    init?(url: URL) {
        guard let day = Self.day(of: url) else { return nil }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { q.first { $0.name == n }?.value }
        let start = v("s").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        // No time in the message: a guess at 10:00, marked so the box says to pick one.
        let s = start ?? DateUtil.startOfDay(day).addingTimeInterval(10 * 3600)
        let e = v("e").flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? s.addingTimeInterval(3600)
        self.init(title: v("t") ?? "", start: s, end: max(e, s.addingTimeInterval(15 * 60)), timed: start != nil, from: v("f") ?? "",
                  days: min(14, max(1, v("n").flatMap(Int.init) ?? 1)))
    }

    init(title: String, start: Date, end: Date, timed: Bool, from: String, days: Int = 1) {
        self.title = title; self.start = start; self.end = end; self.timed = timed; self.from = from; self.days = days
    }

    /// Each day's start and end, for a span of days.
    var slots: [(Date, Date)] {
        (0..<days).map { (DateUtil.add(.day, $0, start), DateUtil.add(.day, $0, end)) }
    }
}

extension Deadlines {
    /// Each time or day in a message with the link that opens PlanSheet for it.
    static func planLinks(text: String, posted: Date?, subject: String) -> [(range: NSRange, url: URL?)] {
        let ns = text as NSString
        let all = sentences(text)
        return spots(in: text, posted: posted ?? Date()).map { s in
            let words = ns.substring(with: s.range)
            let sentence = all.first { $0.contains(words) } ?? words
            return (s.range, PlanDraft.link(for: s, title: title(subject: subject, sentence: sentence), subject: subject))
        }
    }

    /// Marks each time or day in a message (bold on a soft background) and links it to a
    /// PlanDraft, so a tap can put it in the schedule.
    @MainActor static func markTimes(_ out: inout AttributedString, text: String, posted: Date?, subject: String, onAccent: Bool) {
        for (r, url) in planLinks(text: text, posted: posted, subject: subject) {
            guard let range = Range(r, in: text),
                  let lo = AttributedString.Index(range.lowerBound, within: out),
                  let hi = AttributedString.Index(range.upperBound, within: out) else { continue }
            if out[lo..<hi].runs.contains(where: { $0.link != nil }) { continue }
            out[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
            out[lo..<hi].backgroundColor = onAccent ? Color.white.opacity(0.22) : Fomo.accent.opacity(0.14)
            if let url { out[lo..<hi].link = url }
        }
    }
}

/// The box that opens when you click a time in a message: everything is filled in, so one click
/// on "Tilføj til skema" is enough. If it is already in the schedule, it offers to remove it.
struct PlanSheet: View {
    @ObservedObject private var p = Prefs.shared
    @State var draft: PlanDraft
    var showDay: ((Date) -> Void)? = nil
    let close: () -> Void
    @State private var added = false
    @FocusState private var titleFocused: Bool

    private var existing: PlannedItem? {
        p.planned.first { abs($0.start.timeIntervalSince(draft.start)) < 60 && $0.title == draft.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(existing == nil ? "Tilføj til skema" : "Står i dit skema", systemImage: existing == nil ? "calendar.badge.plus" : "calendar.badge.checkmark")
                .font(.headline)
                .foregroundStyle(existing == nil ? Color.primary : Fomo.green)
            TextField("Hvad", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
            DatePicker(draft.days > 1 ? "Første dag" : "Dag", selection: day, displayedComponents: .date)
            if draft.days > 1, let last = draft.slots.last {
                Text("\(draft.days) dage i træk, til og med \(last.0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "da_DK"))))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                DatePicker("Fra", selection: startTime, displayedComponents: .hourAndMinute)
                DatePicker("til", selection: endTime, displayedComponents: .hourAndMinute)
            }
            if !draft.timed {
                Text("Beskeden siger ikke hvornår på dagen, så vælg en tid.")
                    .font(.caption).foregroundStyle(Fomo.warn)
            }
            HStack {
                if let showDay {
                    Button("Vis dagen") { showDay(draft.start); close() }
                }
                Spacer()
                if let e = existing {
                    Button("Fjern fra skema", role: .destructive) {
                        let starts = Set(draft.slots.map { Int($0.0.timeIntervalSince1970 / 60) })
                        let before = p.planned
                        withAnimation(.viggo) {
                            p.planned.removeAll { $0.id == e.id || $0.title == e.title && starts.contains(Int($0.start.timeIntervalSince1970 / 60)) }
                        }
                        StatusPill.shared.done("Fjernet fra skemaet") { withAnimation(.viggo) { Prefs.shared.planned = before } }
                        close()
                    }
                    .foregroundStyle(Fomo.red)
                } else {
                    // When it can't be pressed, the button says why.
                    let noTitle = draft.title.trimmingCharacters(in: .whitespaces).isEmpty
                    Button(added ? "Tilføjet" : noTitle ? "Skriv en titel først" : "Tilføj til skema") { add() }
                        .buttonStyle(.borderedProminent)
                        .tint(Fomo.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(noTitle || added)
                }
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(width: 330)
        #endif
    }

    private func add() {
        let t = draft.title.trimmingCharacters(in: .whitespaces)
        withAnimation(.viggo) {
            for (s, e) in draft.slots {
                p.planned.append(PlannedItem(title: t, start: s, end: max(e, s.addingTimeInterval(15 * 60)), from: draft.from))
            }
        }
        added = true
        Haptic.tap()
        let ids = Set(p.planned.suffix(draft.slots.count).map(\.id))
        StatusPill.shared.done(draft.slots.count > 1 ? "\(draft.slots.count) dage sat i skema" : "Sat i skema") {
            withAnimation(.viggo) { Prefs.shared.planned.removeAll { ids.contains($0.id) } }
        }
        Task { try? await Task.sleep(for: .milliseconds(450)); close() }
    }

    // The day and the two times are edited apart; changing the day keeps the times.
    private var day: Binding<Date> {
        Binding(get: { draft.start }, set: { d in
            let shift = DateUtil.startOfDay(d).timeIntervalSince(DateUtil.startOfDay(draft.start))
            draft.start += shift; draft.end += shift
        })
    }
    private var startTime: Binding<Date> {
        Binding(get: { draft.start }, set: { t in
            let len = draft.end.timeIntervalSince(draft.start)
            draft.start = at(t, on: draft.start); draft.end = draft.start.addingTimeInterval(max(len, 15 * 60)); draft.timed = true
        })
    }
    private var endTime: Binding<Date> {
        Binding(get: { draft.end }, set: { t in draft.end = at(t, on: draft.start); draft.timed = true })
    }
    private func at(_ time: Date, on day: Date) -> Date {
        let c = DateUtil.cal.dateComponents([.hour, .minute], from: time)
        return DateUtil.startOfDay(day).addingTimeInterval(Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60))
    }
}

/// Upcoming things added from messages, for Indstillinger, with a way to remove them.
struct PlannedSection: View {
    @ObservedObject private var p = Prefs.shared
    var body: some View {
        let list = p.planned.filter { $0.end > Date() }.sorted { $0.start < $1.start }
        if !list.isEmpty {
            Section {
                ForEach(list) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title)
                            Text("\(i.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "da_DK")))) kl. \(DateUtil.hm(i.start))-\(DateUtil.hm(i.end))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { withAnimation(.viggo) { p.planned.removeAll { $0.id == i.id } } } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: { Text("Fra beskeder") } footer: {
                Text("Klik på en tid i en besked for at sætte den i skemaet.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
