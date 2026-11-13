import SwiftUI

// MARK: - Uge

/// One day at a time: the week's days in a strip on top, the whole day below as a list in the
/// I dag style, with everything Viggo has for that day (lessons, events, routines, birthdays and
/// the teachers on duty). Swipe sideways to change day. Used by Uge and by a friend's page.
private enum DayTitle {
    static let f: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEEE d. MMMM"; return f
    }()
}

struct WeekBrowser<Header: View>: View {
    @EnvironmentObject var state: AppState
    let person: UUID?
    @Binding var day: Date
    @ViewBuilder var header: Header
    /// Which way the last day change went, so the list slides the same way.
    @State private var forward = true
    @State private var showDuty = false
    @ScaledMetric(relativeTo: .subheadline) private var timeW: CGFloat = 48
    @Namespace private var pill

    private var monday: Date { DateUtil.mondayOf(day) }
    static func weekOffset(_ d: Date) -> Int {
        DateUtil.cal.dateComponents([.weekOfYear], from: DateUtil.mondayOf(Date()), to: DateUtil.mondayOf(d)).weekOfYear ?? 0
    }
    private var range: ClosedRange<Int> { person == nil ? -Config.weeksBack...Config.weeksAhead : 0...1 }
    private var homework: [Homework] {
        (person.flatMap { state.friendHomework[$0] } ?? state.homework).filter { DateUtil.cal.isDate($0.due, inSameDayAs: day) }
    }

    func move(days n: Int) {
        let next = DateUtil.add(.day, n, day)
        guard range.contains(Self.weekOffset(next)) else { return }
        go(to: next)
    }

    private func go(to d: Date) {
        guard !DateUtil.cal.isDate(d, inSameDayAs: day) else { return }
        forward = d > day
        Haptic.select()
        withAnimation(.viggo) { day = d }
    }

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner().padding(.horizontal, 12).padding(.bottom, 6)
            strip.padding(.horizontal, 12).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    agenda
                        .id(day)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
            }
            .clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { g in
                guard abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
                move(days: g.translation.width < 0 ? 1 : -1)
            })
        }
        .background(Color(.systemGroupedBackground))
    }

    private var strip: some View {
        let days = (0..<7).map { DateUtil.add(.day, $0, monday) }
        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { d in
                let sel = DateUtil.cal.isDate(d, inSameDayAs: day)
                let today = DateUtil.cal.isDateInToday(d)
                let busy = state.weekItems(d, person: person).contains { $0.kind == .lesson || $0.kind == .event }
                Button { go(to: d) } label: {
                    VStack(spacing: 3) {
                        Text(DateUtil.weekdayF.string(from: d).prefix(3).capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(sel ? Color.white.opacity(0.85) : .secondary)
                        Text("\(DateUtil.cal.component(.day, from: d))")
                            .font(.system(size: 17, weight: sel || today ? .bold : .regular))
                            .foregroundStyle(sel ? Color.white : today ? Color.accentColor : .primary)
                        Circle().fill(sel ? Color.white : today ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 4, height: 4).opacity(today || busy ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background {
                        if sel { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.gradient).matchedGeometryEffect(id: "pill", in: pill) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.9))
            }
        }
    }

    @ViewBuilder private var agenda: some View {
        let items = state.weekItems(day, person: person, wholeDay: true)
        let school = AppState.schoolDay(items)
        let birthdays = state.birthdayNames(on: day, person: person)
        let duties = state.duties(on: day, person: person)
        let hw = homework
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text({ let t = DayTitle.f.string(from: day); return t.prefix(1).uppercased() + t.dropFirst() }()).font(.title2.weight(.bold))
                Text(summary(school)).font(.subheadline).foregroundStyle(.secondary)
            }
            if !birthdays.isEmpty {
                Banner(icon: "gift.fill", tint: .pink,
                       text: birthdays.count == 1 ? "\(birthdays[0]) har fødselsdag 🎉" : "Fødselsdag: " + birthdays.joined(separator: ", "))
            }
            if items.isEmpty {
                Card(title: "Fri", icon: "sun.max.fill") {
                    Text("Ingen lektioner eller aftaler i Viggo denne dag.").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Card(title: "Dagen", icon: "calendar") {
                    // Only today greys out what is over; other days read in full.
                    DayList(items: items, now: DateUtil.cal.isDateInToday(day) ? state.tick : .distantPast,
                            schoolEnd: school.map(\.end).max())
                }
            }
            if !hw.isEmpty {
                Card(title: "Lektier", icon: "book.closed.fill", badge: hw.filter { !$0.done }.count) {
                    VStack(spacing: 0) { ForEach(hw) { HomeworkRow(h: $0) } }
                }
            }
            if !duties.isEmpty { dutyCard(duties) }
        }
    }

    private func summary(_ school: [ViggoEvent]) -> String {
        let lessons = school.filter { $0.kind == .lesson }.count
        guard let first = school.map(\.start).min(), let last = school.map(\.end).max() else { return "Ingen skole" }
        let what = lessons == 0 ? "\(school.count) aftale\(school.count == 1 ? "" : "r")" : "\(lessons) lektion\(lessons == 1 ? "" : "er")"
        return "\(what) · \(DateUtil.hm(first))–\(DateUtil.hm(last))"
    }

    /// "23:00", "24:00" for midnight, and "lør. 09:00" when the duty runs into the next day.
    static func dutyEnd(_ d: Duty) -> String {
        let cal = DateUtil.cal
        if cal.isDate(d.end, inSameDayAs: d.start) { return DateUtil.hm(d.end) }
        if d.end == cal.startOfDay(for: d.end), cal.isDate(d.end.addingTimeInterval(-60), inSameDayAs: d.start) { return "24:00" }
        return "\(DateUtil.weekdayF.string(from: d.end)) \(DateUtil.hm(d.end))"
    }

    private func dutyCard(_ duties: [Duty]) -> some View {
        Card(title: "Vagter", icon: "person.badge.shield.checkmark.fill") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(showDuty ? duties : Array(duties.prefix(3))) { d in
                    HStack(spacing: 12) {
                        Text(DateUtil.hm(d.start)).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1)
                            .frame(width: timeW, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.who).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(d.shift) · til \(Self.dutyEnd(d))").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if d.start <= state.tick && d.end > state.tick {
                            Text("NU").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(.teal))
                        }
                    }
                    .padding(.vertical, 6)
                    // Over for today: grey like the rest of the day's list.
                    .opacity(d.end <= state.tick && DateUtil.cal.isDateInToday(d.start) ? 0.4 : 1)
                }
                if duties.count > 3 {
                    Button(showDuty ? "Vis færre" : "Vis alle \(duties.count)") { withAnimation(.unfold) { showDuty.toggle() } }
                        .font(.footnote.weight(.medium)).padding(.top, 4)
                }
            }
        }
    }
}

struct WeekScreen: View {
    @EnvironmentObject var state: AppState
    @State private var day = DateUtil.startOfDay(Date())
    @State private var person: UUID?

    private var weekOffset: Int { WeekBrowser<EmptyView>.weekOffset(day) }
    private var range: ClosedRange<Int> { person == nil ? -Config.weeksBack...Config.weeksAhead : 0...1 }

    private func jump(_ n: Int) {
        let next = DateUtil.add(.day, n, day)
        guard range.contains(WeekBrowser<EmptyView>.weekOffset(next)) else { return }
        Haptic.select()
        withAnimation(.viggo) { day = next }
    }

    var body: some View {
        NavigationStack {
            WeekBrowser(person: person, day: $day) {
                if let p = person, let f = state.friends.first(where: { $0.id == p }) {
                    HStack(spacing: 8) {
                        Avatar(url: f.image, size: 24, name: f.name)
                        Text("\(f.firstName)s skema").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Mit skema") { withAnimation(.viggo) { person = nil } }.font(.subheadline)
                    }
                }
            }
            .navigationTitle("Uge \(DateUtil.cal.component(.weekOfYear, from: DateUtil.mondayOf(day)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { jump(-7) } label: { Image(systemName: "chevron.left") }
                        .disabled(weekOffset <= range.lowerBound)
                    Button { jump(7) } label: { Image(systemName: "chevron.right") }
                        .disabled(weekOffset >= range.upperBound)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !DateUtil.cal.isDateInToday(day) {
                        Button("I dag") { withAnimation(.viggo) { day = DateUtil.startOfDay(Date()) } }
                    }
                    if !state.friends.isEmpty {
                        Menu {
                            Picker("Person", selection: $person) {
                                Text("Mig").tag(UUID?.none)
                                ForEach(state.friends) { f in Text(f.firstName).tag(UUID?.some(f.id)) }
                            }
                        } label: {
                            Image(systemName: person == nil ? "person.crop.circle" : "person.crop.circle.fill")
                        }
                    }
                }
            }
            .onChange(of: person) {
                if !range.contains(weekOffset) { day = DateUtil.startOfDay(Date()) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .viggoTabAgain)) { n in
                guard n.object as? Int == 1, !DateUtil.cal.isDateInToday(day) else { return }
                Haptic.select()
                withAnimation(.viggo) { day = DateUtil.startOfDay(Date()) }
            }
        }
    }
}

extension Notification.Name { static let viggoTabAgain = Notification.Name("viggoTabAgain") }

// MARK: - Venner

struct FriendsScreen: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            List {
                if state.friends.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen venner endnu", systemImage: "person.2")
                    } description: {
                        Text("Tilføj en ven for at se deres skema, og hvornår I har fri samtidig. Vælg dem fra Viggo, så skal de ikke logge ind.")
                    } actions: {
                        NavigationLink("Tilføj ven") { FriendsTab().navigationTitle("Venner") }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(state.friends) { f in
                            let (text, free) = state.friendStatus(f, now: state.tick)
                            let expired = state.friendExpired.contains(f.id)
                            NavigationLink(value: FriendRoute(id: f.id)) {
                                HStack(spacing: 12) {
                                    Avatar(url: f.image, size: 40, name: f.name).opacity(expired ? 0.4 : 1)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.name).font(.body.weight(.medium))
                                        HStack(spacing: 5) {
                                            Circle().fill(expired ? Color.gray : free ? .green : .orange).frame(width: 7, height: 7)
                                            Text(expired ? "Skal logge ind igen" : text)
                                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("Lige nu")
                    }
                    Section {
                        NavigationLink { FriendsTab().navigationTitle("Administrer venner") } label: {
                            Label("Tilføj eller fjern venner", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Venner")
            .navigationDestination(for: Found.self) { FoundScreen(found: $0) }
            .navigationDestination(for: FriendRoute.self) { r in
                if let f = state.friends.first(where: { $0.id == r.id }) { FriendDayScreen(friend: f) }
            }
            .refreshable { await state.syncFriends() }
        }
    }
}

/// A friend's day, as a value so it stacks with person and group pages in the same path.
struct FriendRoute: Hashable { let id: UUID }

struct FriendDayScreen: View {
    @EnvironmentObject var state: AppState
    let friend: Friend
    @State private var day = DateUtil.startOfDay(Date())

    var body: some View {
        WeekBrowser(person: friend.id, day: $day) {
            let (text, free) = state.friendStatus(friend, now: state.tick)
            let expired = state.friendExpired.contains(friend.id)
            NavigationLink(value: Found.person(friend.viggoID)) {
                HStack(spacing: 12) {
                    Avatar(url: friend.image, size: 52, name: friend.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.name).font(.headline).foregroundStyle(.primary)
                        HStack(spacing: 5) {
                            Circle().fill(expired ? Color.gray : free ? .green : .orange).frame(width: 7, height: 7)
                            Text(expired ? "Skal logge ind igen" : text).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(PressScale(scale: 0.97))
            if expired {
                HStack {
                    Text("\(friend.firstName) skal logge ind igen").font(.subheadline).foregroundStyle(.orange)
                    Spacer()
                    Button("Log ind igen") { state.addFriend(relogin: friend) }.controlSize(.small)
                }
            }
        }
        .navigationTitle(friend.firstName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await state.syncFriends() }
    }
}

// MARK: - Indstillinger

struct SettingsScreen: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @State private var showGuide = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func row(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let p = state.profile {
                    Section {
                        NavigationLink { AccountTab().navigationTitle("Konto") } label: {
                            HStack(spacing: 12) {
                                Avatar(url: p.image, size: 52, name: p.name)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.title3.weight(.semibold))
                                    Text(Config.baseURL.host ?? "Viggo").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section {
                    NavigationLink { PanelTab().navigationTitle("I dag") } label: { row("I dag-skærmen", "sun.max.fill", .teal) }
                    NavigationLink { NotificationsTab().navigationTitle("Notifikationer") } label: { row("Notifikationer", "bell.badge.fill", .red) }
                    NavigationLink { LessonsTab().navigationTitle("Timer") } label: { row("Timer", "paintpalette.fill", .pink) }
                    NavigationLink { CustomItemsTab().navigationTitle("Egne punkter") } label: { row("Egne punkter", "checklist", .green) }
                    NavigationLink { FriendsTab().navigationTitle("Venner") } label: { row("Venner", "person.2.fill", .blue) }
                }
                Section {
                    NavigationLink { IconPicker().navigationTitle("App-ikon") } label: {
                        Label {
                            Text("App-ikon")
                        } icon: {
                            IconArt(style: IconStyle.current, size: 28)
                        }
                    }
                }
                Section {
                    Toggle(isOn: $p.liveActivity) { row("Live Activity i skoletiden", "clock.badge.fill", .orange) }
                        .onChange(of: p.liveActivity) { state.updateLiveActivity() }
                } footer: {
                    Text("Timen der er i gang og nedtællingen står på låseskærmen og i Dynamic Island, fra en halv time før første time til sidste time slutter. Den starter når du åbner Viggo+. Vil du have den uden at åbne appen, så lav en automatisering i Genveje (fx kl. 7.45 på hverdage) med \"Vis skoledagen\" fra Viggo+, eller læg knappen \"Vis skoledagen\" i Kontrolcenter.")
                }
                Section {
                    NavigationLink { UpdateTab().navigationTitle("Opdateringer") } label: { row("Opdateringer", "arrow.down.circle.fill", .blue) }
                    Button { showGuide = true } label: { row("Introduktion", "questionmark.circle.fill", .gray) }
                        .foregroundStyle(.primary)
                    Button { state.openViggo() } label: { row("Åbn Viggo", "safari.fill", .indigo) }
                        .foregroundStyle(.primary)
                } footer: {
                    Text("Viggo+ \(version)").frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .navigationTitle("Indstillinger")
            .sheet(isPresented: $showGuide) { GuideSheet() }
        }
    }
}
