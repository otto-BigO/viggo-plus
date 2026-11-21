import AppKit
import SwiftUI

/// Asks the big Søg window to show a search or a page (from the panel's search).
final class SearchBridge: ObservableObject {
    static let shared = SearchBridge()
    struct Request: Equatable { let id = UUID(); var query: String?; var found: Found? }
    @Published var request: Request?

    @MainActor func open(query: String? = nil, found: Found? = nil) {
        request = Request(query: query, found: found)
        AppState.shared.openSearch()
    }
}

/// Search inside the panel itself: the magnifier turns the panel into a search, in the panel's own
/// look. People open as a small card right here; groups, rooms and posts open in the big window.
struct PanelSearch: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var dir = Directory.shared
    @ObservedObject private var inbox = Inbox.shared
    @ObservedObject private var files = RosterStore.shared
    @Binding var query: String
    let height: CGFloat
    @State private var q = ""
    @State private var person: Int?
    @AppStorage("recentSearches") private var recentRaw = ""
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var people: [Member] { dir.search(q) }
    private var groups: [MemberGroup] { Array(dir.searchGroups(q).prefix(4)) }
    private var threads: [MessageThread] {
        guard q.count >= 2 else { return [] }
        return Array(inbox.threads.filter { "\($0.sender) \($0.subject) \($0.preview)".lowercased().contains(q) }.prefix(4))
    }
    /// Words inside read messages and their PDFs, leaving out threads already shown by their subject.
    private var textHits: [RosterStore.TextHit] {
        let shown = Set(threads.map(\.id))
        return Array(files.search(q, limit: 12).filter { $0.file != nil || !shown.contains($0.thread) }.prefix(5))
    }
    private var lessons: [ViggoEvent] {
        guard q.count >= 2 else { return [] }
        let now = Date()
        return Array(state.events.filter { e in
            e.end > now && (e.kind == .lesson || e.kind == .event) &&
            "\(e.title) \(e.rawName) \(e.room) \(e.teachers.joined(separator: " "))".lowercased().contains(q)
        }.sorted { $0.start < $1.start }.prefix(4))
    }

    var body: some View {
        ZStack {
            if let id = person {
                PanelPersonCard(id: id, back: { withAnimation(.viggo) { person = nil } })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if q.isEmpty { suggestions } else { results }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .task(id: query) {
            let n = Directory.normalize(query)
            if !n.isEmpty, n != q { try? await Task.sleep(for: .milliseconds(90)) }
            guard !Task.isCancelled else { return }
            withAnimation(.viggo) { q = n; person = nil }
        }
        .task { await dir.load() }
        .onReceive(NotificationCenter.default.publisher(for: .panelSearchPerson)) { _ in
            if let m = people.first { withAnimation(.viggo) { person = m.id } }
        }
    }

    // MARK: before you type

    @ViewBuilder private var suggestions: some View {
        if !recent.isEmpty {
            SectionHeader(title: "Seneste")
            ForEach(recent.prefix(5), id: \.self) { r in
                row { query = r } content: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).frame(width: 26)
                    Text(r).font(Sz.f(13))
                }
            }
        }
        let soon = dir.members.filter { ($0.kind == .student || $0.kind == .staff) && ($0.nextBirthday?.days ?? 99) <= 3 }
            .sorted { ($0.nextBirthday?.days ?? 0) < ($1.nextBirthday?.days ?? 0) }.prefix(4)
        if !soon.isEmpty {
            SectionHeader(title: "Fødselsdage")
            ForEach(Array(soon)) { m in
                personRow(m, detail: m.nextBirthday.map { $0.days == 0 ? "I dag 🎉" : $0.days == 1 ? "I morgen" : "Om \($0.days) dage" })
            }
        }
        if recent.isEmpty && soon.isEmpty {
            Text("Find elever, lærere, klasser, værelser, beskeder og timer.")
                .font(Sz.f(12)).foregroundStyle(.secondary).padding(.top, 6)
        }
    }

    // MARK: results

    @ViewBuilder private var results: some View {
        let ps = people, gs = groups, ts = threads, ls = lessons, xs = textHits
        if ps.isEmpty && gs.isEmpty && ts.isEmpty && ls.isEmpty && xs.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(.tertiary)
                Text(dir.loading ? "Henter personer…" : "Intet fundet for \"\(query)\"").font(Sz.f(12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.top, 30)
        }
        if !ps.isEmpty {
            SectionHeader(title: "Personer")
            ForEach(ps.prefix(8)) { m in personRow(m) }
            if ps.count > 8 {
                row { remember(); SearchBridge.shared.open(query: query) } content: {
                    Text("Vis alle \(ps.count)").font(Sz.f(12, .medium)).foregroundStyle(Color.accentColor).padding(.leading, 36)
                }
            }
        }
        if !gs.isEmpty {
            SectionHeader(title: "Grupper")
            ForEach(gs) { g in
                row { remember(); SearchBridge.shared.open(query: query, found: .group(g.id)) } content: {
                    Image(systemName: g.kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Circle().fill(g.kind.color.gradient))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(g.name).font(Sz.f(13, .medium)).lineLimit(1)
                        Text("\(g.kind.title) · \(g.members.count) personer").font(Sz.f(10.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !ts.isEmpty {
            SectionHeader(title: "Beskeder")
            ForEach(ts) { t in
                row { remember(); state.openMessages(thread: t.id) } content: {
                    Avatar(url: t.image, size: 26, name: t.sender)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.subject).font(Sz.f(13, .medium)).lineLimit(1)
                        Text("\(t.sender) · \(t.when.shortWhen)").font(Sz.f(10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        if !xs.isEmpty {
            SectionHeader(title: "I beskeder og filer")
            ForEach(xs) { h in
                row { remember(); state.openMessages(thread: h.thread) } content: { TextHitRow(h: h, q: q, compact: true) }
            }
        }
        if !ls.isEmpty {
            SectionHeader(title: "Timer")
            ForEach(ls) { e in
                row { remember(); state.openLesson(e) } content: {
                    Text(DateUtil.hm(e.start)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.title).font(Sz.f(13, .medium)).lineLimit(1)
                        Text([e.start.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "da_DK"))).capFirst, e.room].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Sz.f(10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func personRow(_ m: Member, detail: String? = nil) -> some View {
        row { remember(); withAnimation(.viggo) { person = m.id } } content: {
            Avatar(url: m.image, size: 26, name: m.name)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.name).font(Sz.f(13, .medium)).lineLimit(1)
                let s = detail ?? dir.summary(m)
                if !s.isEmpty { Text(s).font(Sz.f(10.5)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    private func row<C: View>(_ action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { content(); Spacer(minLength: 0) }
                .padding(.vertical, 4).padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelSearchRowStyle())
    }

    private func remember() {
        let t = query.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentRaw = ([t] + recent.filter { $0.lowercased() != t.lowercased() }).prefix(6).joined(separator: "\n")
    }
}

/// A row that lights up under the mouse, like a menu.
private struct PanelSearchRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Hovered(configuration: configuration) }
    private struct Hovered: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.06 : 0)))
                .onHover { hover = $0 }
        }
    }
}

/// A person in the panel: picture, where they are now, the main facts and buttons to reach them.
struct PanelPersonCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var dir = Directory.shared
    @ObservedObject private var premises = Premises.shared
    let id: Int
    let back: () -> Void
    @State private var zoom = false

    var body: some View {
        if let m = dir.member(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: back) { Label("Resultater", systemImage: "chevron.left").font(Sz.f(12, .medium)) }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        .keyboardShortcut("[", modifiers: .command)
                    HStack(spacing: 12) {
                        Avatar(url: m.image ?? m.imageBig, size: 58, name: m.name)
                            .onTapGesture { if m.imageBig ?? m.image != nil { withAnimation(.spring(duration: 0.3)) { zoom = true } } }
                            .help("Vis billedet stort")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(Sz.f(15, .bold)).textSelection(.enabled)
                            Text(dir.summary(m)).font(Sz.f(11)).foregroundStyle(.secondary)
                        }
                    }
                    if m.id != state.profile?.id {
                        HStack(spacing: 8) {
                            Button { state.compose(to: [Person(id: m.id, name: m.name, image: m.image, info: "")]) } label: {
                                Label("Besked", systemImage: "bubble.left.fill")
                            }
                            if !m.anyPhone.isEmpty {
                                Button { open("tel:\(m.anyPhone)") } label: { Label("Ring", systemImage: "phone.fill") }
                                Button { open("sms:\(m.anyPhone)") } label: { Label("SMS", systemImage: "message.fill") }
                            }
                        }
                        .controlSize(.small)
                    }
                    if m.kind == .student || m.kind == .staff, !premises.bookings.isEmpty {
                        let w = premises.whereNow(m.id, at: state.tick)
                        Group {
                            if let c = w.now {
                                Label("\(c.title)\(c.room.isEmpty ? "" : " · \(c.room)") til \(DateUtil.hm(c.end))", systemImage: "mappin.circle.fill")
                                    .foregroundStyle(.orange)
                            } else {
                                Label(w.next.map { "Fri til \(DateUtil.hm($0.start))" } ?? "Ingen flere timer i dag", systemImage: "cup.and.saucer.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(Sz.f(12, .medium))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        if !m.className.isEmpty { fact("Klasse", m.className) }
                        if let l = dir.line(of: m.id) { fact("Linje", l) }
                        if !m.houseRoom.isEmpty { fact("Værelse", m.houseRoom) }
                        if let b = m.birthday { fact("Fødselsdag", b.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "da_DK")))) }
                        if !m.mobile.isEmpty { fact("Mobil", m.mobile) }
                        if !m.initials.isEmpty, m.kind == .staff { fact("Initialer", m.initials) }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    Button { SearchBridge.shared.open(found: .person(m.id)) } label: {
                        Label("Hele profilen i Søg", systemImage: "arrow.up.right.square").font(Sz.f(12))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .overlay {
                if zoom {
                    MacPhotoViewer(url: m.imageBig ?? m.image, fallback: m.image, name: m.name) {
                        withAnimation(.easeOut(duration: 0.2)) { zoom = false }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .task { await premises.load() }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Sz.f(11.5)).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Text(value).font(Sz.f(12)).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func open(_ s: String) { if let u = URL(string: s.replacingOccurrences(of: " ", with: "")) { NSWorkspace.shared.open(u) } }
}

/// A word found inside a message or one of its PDFs: where, and the words around it with the match in bold.
struct TextHitRow: View {
    let h: RosterStore.TextHit
    let q: String
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 10 : 8) {
            Image(systemName: h.file == nil ? "text.bubble" : "doc.text")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: compact ? 26 : 28, height: compact ? 26 : 28)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(h.file.map { ($0 as NSString).deletingPathExtension } ?? h.subject)
                    .font(compact ? Sz.f(13, .medium) : .system(size: 12, weight: .semibold)).lineLimit(1)
                Text(marked).font(compact ? Sz.f(10.5) : .system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                if h.file != nil {
                    Text("I \"\(h.subject)\"").font(compact ? Sz.f(10) : .system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var marked: AttributedString {
        var a = AttributedString(h.snippet)
        if let r = a.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].inlinePresentationIntent = .stronglyEmphasized
            a[r].foregroundColor = .primary
        }
        return a
    }
}

