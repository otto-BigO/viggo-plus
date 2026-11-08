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
        let shown = days   // always the whole week, weekend included
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

            WeekGrid(days: shown, items: dayItems,
                     homework: { d in homework.filter { DateUtil.cal.isDate($0.due, inSameDayAs: d) } })
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

/// Hours down the side, a column per day, and each lesson as tall as it lasts, like on Viggo.
struct WeekGrid: View {
    let days: [Date]
    let items: (Date) -> [ViggoEvent]
    let homework: (Date) -> [Homework]
    var hourHeight: CGFloat = 52
    private let gutter: CGFloat = 44

    private var hours: ClosedRange<Int> {
        let all = days.flatMap(items)
        let first = all.map { DateUtil.cal.component(.hour, from: $0.start) }.min() ?? 8
        let last = all.map { e -> Int in
            let sameDay = DateUtil.cal.isDate(e.end, inSameDayAs: e.start)
            let h = DateUtil.cal.component(.hour, from: e.end), m = DateUtil.cal.component(.minute, from: e.end)
            return sameDay ? h + (m > 0 ? 1 : 0) : 24
        }.max() ?? 16
        return min(first, 8)...max(min(last, 24), 16)
    }

    var body: some View {
        let h = hours
        VStack(spacing: 0) {
            // Day names and homework
            HStack(alignment: .top, spacing: 6) {
                Color.clear.frame(width: gutter, height: 1)
                ForEach(days, id: \.self) { d in
                    let today = DateUtil.cal.isDateInToday(d)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(DateUtil.weekdayF.string(from: d).capitalized).font(.system(size: 13, weight: .semibold))
                            Text("\(DateUtil.cal.component(.day, from: d)).").font(.system(size: 13))
                                .foregroundStyle(today ? Color.white : .secondary)
                                .padding(.horizontal, today ? 6 : 0).padding(.vertical, today ? 1 : 0)
                                .background(Capsule().fill(today ? Color.accentColor : .clear))
                        }
                        ForEach(homework(d)) { hw in
                            Label(hw.title, systemImage: hw.done ? "checkmark.circle.fill" : "book.closed")
                                .font(.system(size: 11)).foregroundStyle(hw.done ? .secondary : .primary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.bottom, 6)
                }
            }
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 6) {
                    // Hour labels
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(h), id: \.self) { hr in
                            Text(String(format: "%02d:00", hr)).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(height: hourHeight, alignment: .top)
                                .offset(y: -6)
                        }
                    }
                    .frame(width: gutter, alignment: .trailing)
                    ForEach(days, id: \.self) { d in
                        DayGridColumn(day: d, items: items(d), hours: h, hourHeight: hourHeight)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

struct DayGridColumn: View {
    let day: Date
    let items: [ViggoEvent]
    let hours: ClosedRange<Int>
    let hourHeight: CGFloat

    private var top: Date { DateUtil.cal.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: day)! }
    private var bottom: Date {
        hours.upperBound >= 24 ? DateUtil.add(.day, 1, DateUtil.startOfDay(day))
            : DateUtil.cal.date(bySettingHour: hours.upperBound, minute: 0, second: 0, of: day)!
    }
    private func y(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(top) / 3600) * hourHeight }

    /// Side by side lanes for lessons that overlap.
    private var laid: [(e: ViggoEvent, lane: Int, lanes: Int)] {
        let sorted = items.sorted { ($0.start, $1.end) < ($1.start, $0.end) }
        var out: [(ViggoEvent, Int, Int)] = []
        var cluster: [(ViggoEvent, Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast
        func flush() {
            let n = max(1, laneEnds.count)
            out += cluster.map { ($0.0, $0.1, n) }
            cluster = []; laneEnds = []
        }
        for e in sorted {
            if e.start >= clusterEnd { flush(); clusterEnd = .distantPast }
            if let free = laneEnds.firstIndex(where: { $0 <= e.start }) {
                laneEnds[free] = e.end; cluster.append((e, free))
            } else {
                laneEnds.append(e.end); cluster.append((e, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, e.end)
        }
        flush()
        return out.map { (e: $0.0, lane: $0.1, lanes: $0.2) }
    }

    var body: some View {
        let height = CGFloat(hours.count - 1) * hourHeight + hourHeight
        let today = DateUtil.cal.isDateInToday(day)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Hour lines
                ForEach(Array(hours), id: \.self) { hr in
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
                        .offset(y: CGFloat(hr - hours.lowerBound) * hourHeight)
                }
                ForEach(laid, id: \.e.id) { item in
                    let s = max(item.e.start, top), en = min(item.e.end, bottom)
                    let w = (geo.size.width - CGFloat(item.lanes - 1) * 3) / CGFloat(item.lanes)
                    GridBlock(e: item.e, height: max(20, y(en) - y(s) - 2))
                        .frame(width: w)
                        .offset(x: CGFloat(item.lane) * (w + 3), y: y(s) + 1)
                }
                // Now line
                if today, Date() > top, Date() < bottom {
                    HStack(spacing: 0) {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Rectangle().fill(.red).frame(height: 1.5)
                    }
                    .offset(x: -3, y: y(Date()) - 3.5)
                }
            }
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(today ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.025)))
        .frame(maxWidth: .infinity)
    }
}

struct GridBlock: View {
    let e: ViggoEvent
    let height: CGFloat

    var body: some View {
        let tint = e.customColor ?? (e.kind == .lesson ? Color.accentColor : .purple)
        let roomy = height >= 44
        VStack(alignment: .leading, spacing: 1) {
            Text(e.shortTitle).font(.system(size: 11, weight: .semibold))
                .lineLimit(height >= 70 ? 3 : (roomy ? 2 : 1))
                .minimumScaleFactor(0.75)
            if roomy {
                Text("\(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))").font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            if height >= 58, !e.room.isEmpty {
                Text(e.room).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.leading, 7).padding(.trailing, 4).padding(.vertical, roomy ? 4 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.22)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(e.end < Date() ? 0.55 : 1)
        .help("\(e.title)\n\(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))\(e.room.isEmpty ? "" : " · \(e.room)")")
        .overlay(alignment: .topTrailing) {
            if e.hasInfo || !e.links.isEmpty {
                Image(systemName: "text.alignleft").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { AppState.shared.openLesson(e) }
    }
}

// MARK: - Lesson details

struct LessonDetailView: View {
    let e: ViggoEvent

    private func linkLabel(_ u: URL) -> String {
        let host = (u.host ?? u.absoluteString).replacingOccurrences(of: "www.", with: "")
        if host.contains("youtube") || host.contains("youtu.be") { return "YouTube" }
        if host.contains("drive.google") || host.contains("docs.google") { return "Google Drev" }
        return host
    }
    private func linkIcon(_ u: URL) -> String {
        let h = u.host ?? ""
        if h.contains("youtube") || h.contains("youtu.be") { return "play.rectangle.fill" }
        if h.contains("google") { return "doc.fill" }
        return "link"
    }

    var body: some View {
        let tint = e.customColor ?? (e.kind == .lesson ? Color.accentColor : .purple)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.title).font(.system(size: 20, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Text("\(DateUtil.longDayF.string(from: e.start).capitalized) · \(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !e.room.isEmpty { Label(e.room, systemImage: "mappin.and.ellipse") }
                    if !e.teachers.isEmpty {
                        Label(e.teachers.prefix(4).joined(separator: ", ") + (e.teachers.count > 4 ? " +\(e.teachers.count - 4)" : ""),
                              systemImage: "person")
                    }
                    if !e.groups.isEmpty, e.groups.count <= 3 { Label(e.groups.joined(separator: ", "), systemImage: "person.3") }
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)

                if e.hasInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Info fra læreren").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text(e.notes).font(.system(size: 13)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                } else {
                    Text("Ingen info fra læreren til denne time.").font(.system(size: 12)).foregroundStyle(.tertiary)
                }

                if !e.links.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Links").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(e.links, id: \.self) { u in
                            Link(destination: u) {
                                HStack(spacing: 8) {
                                    Image(systemName: linkIcon(u)).frame(width: 16)
                                    Text(linkLabel(u)).font(.system(size: 12, weight: .medium))
                                    Text(u.path.count > 1 ? u.path : "").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Åbn i Viggo") { NSWorkspace.shared.open(e.link) }
                }
            }
            .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 18)
        }
        .frame(width: 420)
        .frame(minHeight: 240, maxHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
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
                .onTapGesture { withAnimation(.viggo) { state.selectedFriend = f.id } }
            }
        }
    }
}
