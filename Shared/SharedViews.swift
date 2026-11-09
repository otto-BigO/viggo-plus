import SwiftUI

// Views shared by the Mac settings window and the iPhone app: the week grid, the
// lesson names and colors, the login, panel, friends and own items pages.

extension View {
    /// A plain text-link button on the Mac, a normal button on the iPhone.
    @ViewBuilder func linkStyle() -> some View {
        #if os(macOS)
        self.buttonStyle(.link)
        #else
        self
        #endif
    }
}

/// Hours down the side, a column per day, and each lesson as tall as it lasts, like on Viggo.
struct WeekGrid: View {
    let days: [Date]
    let items: (Date) -> [ViggoEvent]
    let homework: (Date) -> [Homework]
    var hourHeight: CGFloat = 52
    /// The day name above each column. The iPhone has its own day strip, so it leaves it out.
    var dayNames = true
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
                        if dayNames {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(DateUtil.weekdayF.string(from: d).capitalized).font(.system(size: 13, weight: .semibold))
                            Text("\(DateUtil.cal.component(.day, from: d)).").font(.system(size: 13))
                                .foregroundStyle(today ? Color.white : .secondary)
                                .padding(.horizontal, today ? 6 : 0).padding(.vertical, today ? 1 : 0)
                                .background(Capsule().fill(today ? Color.accentColor : .clear))
                        }
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


struct AccountTab: View {
    @EnvironmentObject var state: AppState
    @State private var saved = SkoleITLogin.isSet

    var body: some View {
        Form {
            if let prof = state.profile, !state.needsLogin {
                Section {
                    HStack(spacing: 12) {
                        Avatar(url: prof.image, size: 48, name: prof.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prof.name).font(.headline)
                            Text(Config.baseURL.host ?? "Viggo").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Log ud", role: .destructive) { state.logout() }
                    }
                }
            }
            Section {
                if saved {
                    HStack {
                        Label(SkoleITLogin.username ?? "", systemImage: "key.fill")
                            .symbolEffect(.bounce, value: saved)
                        Spacer()
                        if state.autoLoginRunning { ProgressView().controlSize(.small) }
                        if state.needsLogin {
                            Button("Log ind") { Task { if await state.tryAutoLogin(force: true) { await state.sync() } } }
                                .buttonStyle(.borderedProminent).disabled(state.autoLoginRunning)
                        }
                        Button("Fjern") { state.removeAutoLogin(); saved = false }
                    }
                } else {
                    SkoleITFields(button: state.needsLogin ? "Log ind" : "Gem") { u, p in
                        saved = true
                        Task { await state.saveAutoLogin(username: u, password: p) }
                    }
                }
                if state.needsLogin {
                    Button("Log ind på Viggos side i stedet…") { state.loginWithBrowser() }.linkStyle()
                }
                if !state.loginMessage.isEmpty { Text(state.loginMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text(state.needsLogin ? "Log ind med SkoleIT" : "Automatisk login")
            } footer: {
                Text("Viggo+ logger selv ind, når sessionen udløber. Koden gemmes kun på \(Platform.deviceName).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(.viggo, value: saved)
        .animation(.viggo, value: state.loginMessage)
        .animation(.viggo, value: state.needsLogin)
        .onReceive(state.$loginMessage) { _ in saved = SkoleITLogin.isSet }
    }
}


struct PanelTab: View {
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Form {
            Section("Vis i panelet") {
                Toggle("Nu-kort (hvad sker der lige nu)", isOn: $p.panelNow)
                Toggle("Resten af dagen", isOn: $p.panelTimeline)
                Toggle("Middag og værelsestjek mellem timerne", isOn: $p.panelLunch)
                Toggle("Pauser mellem klassens timer", isOn: $p.panelBreaks)
                Toggle("Dagens mad fra madplanen under Middag og Aftensmad", isOn: $p.panelMeals)
                Toggle("I morgen", isOn: $p.panelTomorrow)
                Toggle("Lektier", isOn: $p.panelHomework)
                if p.panelHomework {
                    Toggle("Afkryds lektier direkte i panelet", isOn: $p.panelHomeworkTick)
                }
                Toggle("Aftenvagt", isOn: $p.panelDuty)
                Toggle("Fødselsdage", isOn: $p.panelBirthdays)
                Toggle("Venner nu (hvem har fri)", isOn: $p.panelFriendsNow)
                Toggle("Opslag fra opslagstavlen", isOn: $p.panelBulletin)
                Toggle("Beskeder", isOn: $p.panelMessages)
                if p.panelMessages {
                    Stepper("Antal beskeder: \(p.panelMsgCount)", value: $p.panelMsgCount, in: 1...5)
                }
            }
            Section("Udseende") {
                Toggle("Skjul det der er overstået", isOn: $p.panelHidePast)
                Toggle("Stor tekst", isOn: $p.panelLarge)
            }
            Section {
                Text("Hvilke hverdags-punkter (aftensmad, godnat …) der vises, vælger du under Menubar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}


struct FriendAutoLoginButton: View {
    @EnvironmentObject var state: AppState
    let friend: Friend
    @State private var open = false

    var body: some View {
        let saved = FriendLogin.has(friend.id)
        Button { open = true } label: {
            Image(systemName: saved ? "key.fill" : "key")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: saved)
        }
            .buttonStyle(.borderless)
            .help(saved ? "Automatisk login er slået til" : "Slå automatisk login til")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Form {
                    Section("Automatisk login for \(friend.firstName)") {
                        if saved, let u = FriendLogin.get(friend.id)?.user {
                            HStack {
                                Text(u)
                                Spacer()
                                Button("Fjern") { state.removeFriendAutoLogin(friend); open = false }
                            }
                        } else {
                            SkoleITFields(button: "Gem") { u, p in
                                open = false
                                Task { await state.saveFriendAutoLogin(friend, username: u, password: p) }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 300)
            }
    }
}

struct FriendsTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared

    var body: some View {
        Form {
            if !state.friends.isEmpty {
                Section {
                    ForEach(state.friends) { f in
                        let expired = state.friendExpired.contains(f.id)
                        HStack(spacing: 10) {
                            Avatar(url: f.image, size: 32, name: f.name).opacity(expired ? 0.5 : 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.name)
                                Text(expired ? "Skal logge ind igen" : "Logget ind")
                                    .font(.caption).foregroundStyle(expired ? .orange : .green)
                            }
                            Spacer()
                            if state.friendAutoLoginRunning.contains(f.id) {
                                ProgressView().controlSize(.small)
                            } else if expired {
                                Button("Log ind") {
                                    if FriendLogin.has(f.id) {
                                        Task { if await !state.tryFriendAutoLogin(f, force: true) { state.addFriend(relogin: f) } }
                                    } else { state.addFriend(relogin: f) }
                                }.buttonStyle(.borderedProminent)
                            }
                            FriendAutoLoginButton(friend: f)
                            Button(role: .destructive) { state.removeFriend(f) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Toggle("Vis hvornår I har fri samtidig", isOn: $p.friendsFreeTogether)
                }
            }
            Section {
                SkoleITFields(button: "Tilføj") { u, p in
                    Task { await state.addFriendWithSkoleIT(username: u, password: p) }
                }
                Button("Log ind på Viggos side i stedet…") { state.addFriend() }.linkStyle()
                if !state.friendMessage.isEmpty { Text(state.friendMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Tilføj ven")
            } footer: {
                Text("Med vennens SkoleIT-login logger Viggo+ selv vennen ind igen. Koden gemmes kun på \(Platform.deviceName).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(.viggo, value: state.friends)
        .animation(.viggo, value: state.friendExpired)
        .animation(.viggo, value: state.friendMessage)
        .animation(.viggo, value: state.friendAutoLoginRunning)
    }
}


/// Your own everyday items: lunch, dinner, breaks. They show up in the panel and the menubar.
struct CustomItemsTab: View {
    @ObservedObject var p = Prefs.shared

    var body: some View {
        Form {
            if !p.customItems.isEmpty {
                Section {
                    ForEach($p.customItems) { $item in
                        CustomItemRow(item: $item) {
                            withAnimation(.viggo) { p.customItems.removeAll { $0.id == item.id } }
                        }
                    }
                }
            }
            Section {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CustomItem.suggestions.filter { s in !p.customItems.contains { $0.title == s.title } }, id: \.title) { s in
                                Button { add(s) } label: { Label(s.title, systemImage: "plus").fixedSize() }
                                    .buttonStyle(PressScale(scale: 0.94))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.green.opacity(0.15)))
                            }
                        }
                    }
                    Button("Andet…") { add(CustomItem(title: "", start: 15 * 60, end: 15 * 60 + 30)) }
                        .buttonStyle(.borderless).fixedSize()
                }
            } header: {
                Text("Tilføj")
            } footer: {
                Text("Punkterne står i panelet og i menubaren på de dage du vælger, fx \"Frokost 12:00\".")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(.viggo, value: p.customItems)
    }

    private func add(_ item: CustomItem) {
        var i = item
        i.id = UUID()
        withAnimation(.viggo) { p.customItems.append(i) }
    }
}

struct CustomItemRow: View {
    @Binding var item: CustomItem
    let onDelete: () -> Void
    private static let dayNames = ["M", "T", "O", "T", "F", "L", "S"]

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { DateUtil.startOfDay(Date()).addingTimeInterval(Double(minutes.wrappedValue * 60)) },
            set: { d in
                let c = DateUtil.cal.dateComponents([.hour, .minute], from: d)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private var title: some View {
        TextField("", text: $item.title, prompt: Text("Navn, fx Frokost"))
            .labelsHidden()
            .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var times: some View {
        DatePicker("", selection: time($item.start), displayedComponents: .hourAndMinute).labelsHidden()
        Text("til").foregroundStyle(.secondary)
        DatePicker("", selection: time($item.end), displayedComponents: .hourAndMinute).labelsHidden()
    }
    private var delete: some View {
        Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
            .buttonStyle(.borderless)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(macOS)
            HStack(spacing: 8) {
                title
                times
                delete
            }
            #else
            HStack(spacing: 8) { title; delete }
            HStack(spacing: 8) { times; Spacer() }
            #endif
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { d in
                    let on = item.days.contains(d)
                    Button {
                        withAnimation(.viggo) { if on { item.days.remove(d) } else { item.days.insert(d) } }
                    } label: {
                        Text(Self.dayNames[d - 1])
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(on ? Color.white : Color.secondary)
                            .background(Circle().fill(on ? Color.green : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(PressScale(scale: 0.85))
                }
                if item.end <= item.start {
                    Text("Slut skal være efter start").font(.caption).foregroundStyle(.orange).padding(.leading, 6)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
