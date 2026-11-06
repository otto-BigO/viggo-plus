import AppKit
import SwiftUI
import Carbon

// MARK: - Bulletin board (opslagstavle)

struct Bulletin: Identifiable, Hashable {
    let board: String
    let author: String
    let when: String
    let title: String
    let text: String
    /// Viggo gives posts no id, so author + title + start of the text identifies one.
    var id: String { "\(board)|\(author)|\(title)|\(text.prefix(120))" }
}

extension Parser {
    static func bulletins(_ html: String) -> [Bulletin] {
        let board = html.firstMatch("<h4>.*?</i>(.*?)<small>")?[1].strippedHTML ?? "Opslagstavle"
        return html.components(separatedBy: "class=\"hinted\">").dropFirst().compactMap { c in
            let author = c.firstMatch("^(.*?)<small>")?[1].strippedHTML ?? ""
            let when = c.firstMatch("<small>(.*?)</small>")?[1].strippedHTML ?? ""
            guard let title = c.firstMatch("<p class=\"h\"><strong>(.*?)</strong>")?[1].strippedHTML else { return nil }
            let text = c.firstMatch("<div class=\"content\">(.*?)</div></div>")?[1].strippedHTML ?? ""
            return Bulletin(board: board, author: author, when: when, title: title, text: text)
        }
    }
}

extension ViggoClient {
    /// The student and parent boards shown on Viggo's front page.
    func fetchBulletins() async throws -> [Bulletin] {
        var all: [Bulletin] = []
        for type in [28, 29] {
            let html = String(decoding: try await getPublic("/Basic/BulletinBoard/HomeWidget?show=9&userType=\(type)&ajax=1"), as: UTF8.self)
            all += Parser.bulletins(html)
        }
        return all
    }
}

// MARK: - Birthdays

extension ViggoEvent {
    /// "Anders Lemming Borgensgaard (06/11)" → "Anders Lemming Borgensgaard"
    var birthdayName: String {
        rawName.replacingOccurrences(of: "\\s*\\(\\d{1,2}/\\d{1,2}\\)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Own names and colours for lessons

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

extension ViggoEvent {
    var customColor: Color? { Prefs.shared.lessonColors[baseTitle].flatMap { Color(hex: $0) } }
}

struct LessonsTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared

    private var titles: [String] {
        let all = state.events + state.friendEvents.values.flatMap { $0 }
        return Array(Set(all.filter { $0.kind == .lesson || $0.kind == .event }.map(\.baseTitle))).sorted()
    }

    var body: some View {
        Form {
            Section {
                Text("Giv timer dine egne navne og farver. Navnet bruges i menubaren, panelet, uge-overblikket og kalenderen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Timer") {
                if titles.isEmpty { Text("Log ind for at se dine timer").font(.caption).foregroundStyle(.secondary) }
                ForEach(titles, id: \.self) { t in
                    HStack(spacing: 10) {
                        ColorPicker("", selection: Binding(
                            get: { p.lessonColors[t].flatMap { Color(hex: $0) } ?? .gray.opacity(0.4) },
                            set: { p.lessonColors[t] = $0.hex }), supportsOpacity: false)
                            .labelsHidden()
                        Text(t).frame(width: 130, alignment: .leading).lineLimit(1).foregroundStyle(.secondary)
                        TextField("Eget navn", text: Binding(
                            get: { p.lessonNames[t] ?? "" },
                            set: { p.lessonNames[t] = $0.isEmpty ? nil : $0 }))
                        if p.lessonNames[t] != nil || p.lessonColors[t] != nil {
                            Button { p.lessonNames[t] = nil; p.lessonColors[t] = nil } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                            }
                            .buttonStyle(.borderless).help("Nulstil")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: p.lessonNames) { if p.imported { state.applyCalendar() } }
    }
}

// MARK: - Global hotkey

final class HotKey {
    static let shared = HotKey()
    static let choices: [(label: String, mods: UInt32)] = [
        ("⌥ V", UInt32(optionKey)), ("⌃ ⌥ V", UInt32(controlKey | optionKey)), ("⌥ ⇧ V", UInt32(optionKey | shiftKey)),
    ]
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    func register(choice: Int) {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let mods = HotKey.choices[max(0, min(choice, HotKey.choices.count - 1))].mods
        RegisterEventHotKey(UInt32(kVK_ANSI_V), mods, EventHotKeyID(signature: OSType(0x5650_4C53), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }

    /// Clicks Viggo+'s own menu bar item, which opens or closes the panel.
    @MainActor static func togglePanel() {
        func find(_ v: NSView) -> NSButton? {
            if String(describing: type(of: v)).contains("StatusBarButton"), let b = v as? NSButton { return b }
            for s in v.subviews { if let b = find(s) { return b } }
            return nil
        }
        for w in NSApp.windows where String(describing: type(of: w)).contains("StatusBar") {
            if let root = w.contentView, let b = find(root) {
                NSApp.activate(ignoringOtherApps: true)
                b.performClick(nil)
                return
            }
        }
    }
}

// MARK: - Week overview

struct WeekView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @State private var offset = 0
    @State private var person: UUID?

    private var monday: Date { DateUtil.add(.weekOfYear, offset, DateUtil.mondayOf(Date())) }
    private var events: [ViggoEvent] { person.flatMap { state.friendEvents[$0] } ?? state.events }
    private var homework: [Homework] { person.flatMap { state.friendHomework[$0] } ?? state.homework }
    private var range: ClosedRange<Int> { person == nil ? -Config.weeksBack...Config.weeksAhead : 0...1 }

    private func dayItems(_ d: Date) -> [ViggoEvent] {
        events.filter { ($0.kind == .lesson || $0.kind == .event) && (person != nil || state.visible($0))
            && DateUtil.cal.isDate($0.start, inSameDayAs: d) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        let days = (0..<7).map { DateUtil.add(.day, $0, monday) }
        let shown = days.enumerated().filter { $0.offset < 5 || !dayItems($0.element).isEmpty }.map(\.element)
        let week = DateUtil.cal.component(.weekOfYear, from: monday)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Uge \(week)").font(.system(size: 20, weight: .bold))
                Text("\(DateUtil.day(monday)) – \(DateUtil.day(DateUtil.add(.day, 6, monday)))")
                    .foregroundStyle(.secondary)
                Spacer()
                if !state.friends.isEmpty {
                    Picker("", selection: $person) {
                        Text("Mig").tag(UUID?.none)
                        ForEach(state.friends) { f in Text(f.firstName).tag(UUID?.some(f.id)) }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: person) { offset = max(range.lowerBound, min(offset, range.upperBound)) }
                }
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }.disabled(offset <= range.lowerBound)
                Button("I dag") { offset = 0 }.disabled(offset == 0)
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= range.upperBound)
            }
            .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 14)

            HStack(alignment: .top, spacing: 10) {
                ForEach(shown, id: \.self) { d in
                    DayColumn(day: d, items: dayItems(d),
                              homework: homework.filter { DateUtil.cal.isDate($0.due, inSameDayAs: d) })
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

struct DayColumn: View {
    let day: Date
    let items: [ViggoEvent]
    let homework: [Homework]

    var body: some View {
        let today = DateUtil.cal.isDateInToday(day)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(DateUtil.weekdayF.string(from: day).capitalized).font(.system(size: 13, weight: .semibold))
                Text("\(DateUtil.cal.component(.day, from: day)).").font(.system(size: 13))
                    .foregroundStyle(today ? Color.white : .secondary)
                    .padding(.horizontal, today ? 6 : 0).padding(.vertical, today ? 1 : 0)
                    .background(Capsule().fill(today ? Color.accentColor : .clear))
            }
            .padding(.bottom, 2)
            ForEach(homework) { h in
                Label(h.title, systemImage: h.done ? "checkmark.circle.fill" : "book.closed")
                    .font(.system(size: 11)).foregroundStyle(h.done ? .secondary : .primary).lineLimit(2)
            }
            if items.isEmpty {
                Text("Fri").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            ForEach(items) { e in
                let tint = e.customColor ?? .accentColor
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Text(e.shortTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    if !e.room.isEmpty { Text(e.room).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.18)))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 5)
                }
                .opacity(e.end < Date() ? 0.5 : 1)
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.open(e.link) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(today ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.04)))
    }
}

// MARK: - Friends right now

struct FriendsNow: View {
    @EnvironmentObject var state: AppState
    let now: Date

    private func status(_ f: Friend) -> (String, Bool) {
        let today = (state.friendEvents[f.id] ?? []).filter {
            ($0.kind == .lesson || $0.kind == .event) && DateUtil.cal.isDate($0.start, inSameDayAs: now)
        }.sorted { $0.start < $1.start }
        if let c = today.first(where: { $0.start <= now && $0.end > now }) {
            return ("\(c.shortTitle) til \(DateUtil.hm(c.end))", false)
        }
        if let n = today.first(where: { $0.start > now }) { return ("Fri til \(DateUtil.hm(n.start))", true) }
        return ("Fri", true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Venner nu")
            ForEach(state.friends) { f in
                let (text, free) = status(f)
                let expired = state.friendExpired.contains(f.id)
                HStack(spacing: 8) {
                    Avatar(url: f.image, size: 20, name: f.name).opacity(expired ? 0.4 : 1)
                    Text(f.firstName).font(Sz.f(12, .medium))
                    Spacer()
                    Circle().fill(free ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(expired ? "Skal logge ind" : text).font(Sz.f(11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { state.selectedFriend = f.id }
            }
        }
    }
}
