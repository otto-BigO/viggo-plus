import AppKit
import SwiftUI
import Carbon

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

    /// Opens or closes the panel.
    @MainActor static func togglePanel() { PanelController.shared.toggle() }
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
        let school = events.filter { ($0.kind == .lesson || $0.kind == .event) && (person != nil || state.visible($0))
            && DateUtil.cal.isDate($0.start, inSameDayAs: d) }
        // Lunch from Viggo, like on Viggo's own schedule, and your own items (only in your own week).
        let extra = state.lunch(d, from: person == nil ? nil : events) + state.breaks(d, from: person == nil ? nil : events)
            + (person == nil ? state.customEvents(on: d) : [])
        return (school + extra).sorted { $0.start < $1.start }
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
                    GridBlock(e: item.e, height: max(item.e.kind == .pause ? 6 : item.e.kind == .routine ? 13 : 20, y(en) - y(s) - 2))
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
        if e.kind == .pause { pauseBody } else { block }
    }

    /// A pause is only a thin gray strip, so it never covers the lessons around it.
    private var pauseBody: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.gray.opacity(0.14))
            .overlay(alignment: .leading) {
                if height >= 14 {
                    Text("Pause").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).padding(.leading, 7)
                }
            }
            .frame(height: height)
            .opacity(e.end < Date() ? 0.55 : 1)
            .help("Pause \(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))")
    }

    private var block: some View {
        let tint = e.customColor ?? (e.kind == .lesson ? Color.accentColor : e.kind == .custom ? .green : e.kind == .routine || e.kind == .pause ? .gray : .purple)
        let roomy = height >= 44
        return VStack(alignment: .leading, spacing: 1) {
            Text(e.shortTitle).font(.system(size: height < 18 ? 9.5 : 11, weight: .semibold))
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
        .padding(.leading, 7).padding(.trailing, 4).padding(.vertical, roomy ? 4 : height < 18 ? 0 : 2)
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
        .onTapGesture { if e.kind != .custom { AppState.shared.openLesson(e) } }
    }
}

