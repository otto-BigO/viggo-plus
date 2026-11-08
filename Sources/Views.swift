import SwiftUI

@main
struct ViggoPlusApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.badgeCount > 0 ? "graduationcap.circle.fill" : "graduationcap.fill")
                let badge = state.badgeCount > 0 ? "  ✉︎ \(state.badgeCount)" : ""
                if !state.menuTitle.isEmpty || !badge.isEmpty { Text(state.menuTitle + badge) }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Small pieces

/// Apple-style press: the button shrinks a little while pressed and springs back.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension Animation {
    static let viggo = Animation.spring(response: 0.35, dampingFraction: 0.82)
}

/// The refresh arrow spins while syncing.
struct SyncIcon: View {
    let spinning: Bool
    var body: some View {
        if #available(macOS 15, *) {
            Image(systemName: "arrow.clockwise").symbolEffect(.rotate, isActive: spinning)
        } else {
            Image(systemName: "arrow.clockwise").opacity(spinning ? 0.4 : 1)
        }
    }
}

struct Avatar: View {
    let url: URL?
    var size: CGFloat = 28
    var name: String? = nil

    private var initials: String {
        (name ?? "").split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
    private var tint: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
        let h = (name ?? "").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return palette[h % palette.count]
    }

    var body: some View {
        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
            if initials.isEmpty {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            } else {
                Circle().fill(tint.gradient)
                    .overlay(Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct SectionHeader: View {
    let title: String
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10 * (p.panelLarge ? 1.15 : 1), weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}

/// Font sizes that follow the "Stor tekst" setting.
struct Sz {
    static var k: CGFloat { Prefs.shared.panelLarge ? 1.18 : 1 }
    static func f(_ base: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: base * k, weight: w) }
    static func mono(_ base: CGFloat) -> Font { .system(size: base * k, weight: .regular, design: .monospaced) }
}

struct TimelineRow: View {
    let e: ViggoEvent
    let now: Date
    var dividerAbove = false
    var tappable = true
    var body: some View {
        let current = e.start <= now && e.end > now
        let past = e.end <= now
        VStack(alignment: .leading, spacing: 4) {
            if dividerAbove {
                HStack(spacing: 6) {
                    Rectangle().fill(.quaternary).frame(height: 1)
                    Text("Efter skole").font(Sz.f(9, .medium)).foregroundStyle(.tertiary)
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
                .padding(.vertical, 2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(DateUtil.hm(e.start))
                    .font(Sz.mono(12))
                    .foregroundStyle(current ? Color.accentColor : .secondary)
                    .frame(width: 42 * Sz.k, alignment: .leading)
                if let c = e.customColor {
                    RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 3, height: 13 * Sz.k)
                }
                Text(e.shortTitle)
                    .font(Sz.f(13, current ? .semibold : .regular))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if e.hasInfo || !e.links.isEmpty {
                    Image(systemName: "text.alignleft").font(Sz.f(10, .bold)).foregroundStyle(Color.accentColor)
                        .help("Der er info fra læreren")
                }
                if !e.room.isEmpty {
                    Text(e.room).font(Sz.f(11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
            }
            .opacity(past ? 0.35 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { AppState.shared.openLesson(e) }
        .help(e.hasInfo ? "Se info fra læreren" : "Se detaljer")
    }
}

struct NowCard: View {
    let current: ViggoEvent?
    let next: ViggoEvent?
    let now: Date
    let name: String?

    private func mins(_ a: Date, _ b: Date) -> String {
        let m = max(0, Int(b.timeIntervalSince(a) / 60.0 + 0.99))
        return m >= 60 ? "\(m / 60) t \(m % 60) min" : "\(m) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = current {
                Text(name.map { "\($0) har nu" } ?? "Nu").font(Sz.f(10, .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(c.shortTitle).font(Sz.f(19, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("\(mins(now, c.end)) tilbage").font(Sz.f(12, .medium)).foregroundStyle(.secondary).fixedSize()
                        .contentTransition(.numericText(countsDown: true))
                }
                ProgressView(value: min(1, max(0, now.timeIntervalSince(c.start) / max(1, c.end.timeIntervalSince(c.start)))))
                    .progressViewStyle(.linear).tint(.accentColor)
                    .animation(.easeInOut(duration: 0.6), value: now)
                HStack {
                    if !c.room.isEmpty { Label(c.room, systemImage: "mappin").font(Sz.f(11)).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(DateUtil.hm(c.start))–\(DateUtil.hm(c.end))").font(Sz.mono(11)).foregroundStyle(.secondary)
                }
            } else if let n = next {
                Text(name.map { "\($0) er fri" } ?? "Fri").font(Sz.f(10, .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(n.shortTitle).font(Sz.f(19, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("om \(mins(now, n.start))").font(Sz.f(12, .medium)).foregroundStyle(.secondary).fixedSize()
                        .contentTransition(.numericText(countsDown: true))
                }
                if !n.room.isEmpty { Label(n.room, systemImage: "mappin").font(Sz.f(11)).foregroundStyle(.secondary) }
            } else {
                Text(name.map { "\($0) har fri resten af dagen" } ?? "Fri resten af dagen 🎉").font(Sz.f(15, .semibold))
            }
            if let info = (current ?? next).flatMap({ $0.hasInfo ? $0 : nil }) {
                Button { AppState.shared.openLesson(info) } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.alignleft").font(Sz.f(10, .bold)).foregroundStyle(Color.accentColor)
                            .padding(.top, 2)
                        Text(info.notes.replacingOccurrences(of: "\n", with: " "))
                            .font(Sz.f(11)).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Se info fra læreren")
            }
            if current != nil, let n = next {
                Divider().opacity(0.5)
                HStack {
                    Text("Næste").font(Sz.f(11)).foregroundStyle(.secondary)
                    Text(n.shortTitle).font(Sz.f(12, .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(DateUtil.hm(n.start)).font(Sz.mono(12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.06)))
        .animation(.viggo, value: now)
        .animation(.viggo, value: current?.id)
    }
}

struct PersonChip: View {
    var ring: Namespace.ID? = nil
    let url: URL?
    let label: String
    var fullName: String? = nil
    let selected: Bool
    var expired = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Avatar(url: url, size: 30, name: fullName)
                    .overlay {
                        if selected {
                            if let ring {
                                Circle().stroke(Color.accentColor, lineWidth: 2).padding(-2.5)
                                    .matchedGeometryEffect(id: "ring", in: ring)
                            } else {
                                Circle().stroke(Color.accentColor, lineWidth: 2).padding(-2.5)
                            }
                        }
                    }
                    .opacity(expired ? 0.4 : 1)
                    .overlay(alignment: .topTrailing) {
                        if expired { Circle().fill(.orange).frame(width: 9, height: 9).overlay(Circle().stroke(.background, lineWidth: 1.5)) }
                    }
                Text(label).font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
            }
            .frame(width: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Menubar panel

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject var updater = Updater.shared
    @Namespace private var ring

    var body: some View {
        let now = state.tick
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let prof = state.profile { Avatar(url: prof.image, size: 30, name: prof.name) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.profile.map { "Hej \($0.name.components(separatedBy: " ").first ?? $0.name)" } ?? "Viggo+")
                        .font(Sz.f(15, .bold))
                    Text(DateUtil.longDayF.string(from: now).capitalized).font(Sz.f(11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let r = updater.available {
                    Button { updater.show() } label: {
                        Label("Ny version \(r.version)", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            if state.needsLogin {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("Du er logget ud af Viggo").font(Sz.f(12))
                    Spacer()
                    Button("Log ind") { state.loginWithBrowser() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !state.status.isEmpty {
                Text(state.status).font(Sz.f(11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if !state.friends.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        PersonChip(ring: ring, url: state.profile?.image, label: "Mig", fullName: state.profile?.name, selected: state.selectedFriend == nil) {
                            withAnimation(.viggo) { state.selectedFriend = nil }
                        }
                        ForEach(state.friends) { f in
                            PersonChip(ring: ring, url: f.image, label: f.firstName, fullName: f.name, selected: state.selectedFriend == f.id,
                                       expired: state.friendExpired.contains(f.id)) { withAnimation(.viggo) { state.selectedFriend = f.id } }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }

            if let fid = state.selectedFriend, let f = state.friends.first(where: { $0.id == fid }) {
                if state.friendExpired.contains(f.id) {
                    HStack {
                        Text("\(f.firstName) skal logge ind igen").font(Sz.f(11)).foregroundStyle(.orange)
                        Spacer()
                        Button("Log ind igen") { state.addFriend(relogin: f) }.controlSize(.small)
                    }
                }
                DayPanel(name: f.firstName, events: state.friendEvents[f.id] ?? [],
                         homework: state.friendHomework[f.id] ?? [], now: now)
                    .id(f.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            } else {
                DayPanel(name: nil, events: state.events, homework: state.homework, now: now)
                    .id("me")
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }

            HStack(spacing: 14) {
                if let s = state.lastSync {
                    Text("Synket \(DateUtil.hm(s))").font(.system(size: 10)).foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { Task { await state.sync() } } label: { SyncIcon(spinning: state.syncing) }.help("Synk nu")
                Button { state.openWeek() } label: { Image(systemName: "calendar") }.help("Uge-overblik")
                Button { state.openViggo() } label: { Image(systemName: "safari") }.help("Åbn Viggo")
                Button { state.openSettings() } label: { Image(systemName: "gearshape") }.help("Indstillinger")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Afslut")
            }
            .buttonStyle(PressScale(scale: 0.82))
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
            .padding(.top, 2)
        }
        .animation(.viggo, value: state.needsLogin)
        .animation(.viggo, value: updater.available?.version)
        .animation(.viggo, value: state.lastSync)
        .padding(14)
        .frame(width: 320 * (p.panelLarge ? 1.12 : 1))
    }
}

/// Same layout for you and your friends.
struct DayPanel: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    let name: String?
    let events: [ViggoEvent]
    let homework: [Homework]
    let now: Date

    var body: some View {
        let isMe = name == nil
        let all = state.timeline(now, from: isMe ? nil : events)
        let current = all.first { $0.start <= now && $0.end > now }
        let next = all.first { $0.start > now }
        let shown = p.panelHidePast ? all.filter { $0.end > now } : all
        let firstEvening = shown.first { $0.kind == .routine }?.id
        let hasSchool = shown.contains { $0.kind != .routine }
        let hw = homework.filter { $0.day >= DateUtil.startOfDay(now) }

        VStack(alignment: .leading, spacing: 12) {
            if p.panelNow, !events.isEmpty {
                NowCard(current: current, next: next, now: now, name: name)
            }

            if let name, p.friendsFreeTogether {
                let gaps = state.freeTogether(with: events, now: now)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.2.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fri sammen med \(name)").font(Sz.f(12, .semibold))
                        Text(gaps.isEmpty ? "Ingen fælles fritid resten af skoledagen"
                             : gaps.map { "\(DateUtil.hm($0.0))–\(DateUtil.hm($0.1))" }.joined(separator: " · "))
                            .font(Sz.mono(11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.green.opacity(0.08)))
            }

            if isMe, p.panelBirthdays, !state.birthdaysToday.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("🎂").font(Sz.f(14))
                    Text("Fødselsdag i dag: \(state.birthdaysToday.joined(separator: ", "))")
                        .font(Sz.f(12)).fixedSize(horizontal: false, vertical: true)
                }
            }

            if p.panelTimeline, !shown.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeader(title: name.map { "\($0)s dag" } ?? "Resten af dagen")
                    ForEach(shown) { e in
                        TimelineRow(e: e, now: now, dividerAbove: hasSchool && e.id == firstEvening, tappable: isMe)
                    }
                }
            }

            if p.panelTomorrow, let (first, count) = state.tomorrowFirst(now, from: isMe ? nil : events) {
                HStack {
                    Image(systemName: "sunrise").foregroundStyle(.secondary)
                    Text("I morgen: \(first.shortTitle) kl. \(DateUtil.hm(first.start))").font(Sz.f(12))
                    Spacer()
                    Text("\(count) \(count == 1 ? "punkt" : "punkter")").font(Sz.f(11)).foregroundStyle(.tertiary)
                }
            }

            if isMe, p.panelDuty, !state.dutyTonight.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "person.badge.shield.checkmark").foregroundStyle(.secondary)
                    Text("Aftenvagt: \(state.dutyTonight.joined(separator: ", "))").font(Sz.f(12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if p.panelHomework, !hw.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeader(title: "Lektier")
                    ForEach(hw.prefix(5)) { h in
                        HStack(spacing: 8) {
                            Button {
                                if isMe && p.panelHomeworkTick { state.toggleHomework(h) }
                            } label: {
                                Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(h.done ? .green : .secondary)
                                    .font(Sz.f(14))
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.bounce, value: h.done)
                            }
                            .buttonStyle(PressScale(scale: 0.8))
                            .help(isMe && p.panelHomeworkTick ? (h.done ? "Markér som ikke færdig" : "Markér som færdig") : "")
                            Text(h.title).font(Sz.f(13)).strikethrough(h.done).foregroundStyle(h.done ? .secondary : .primary).lineLimit(1)
                                .onTapGesture { if isMe { NSWorkspace.shared.open(h.link) } }
                            Spacer()
                            Text(DateUtil.day(h.due)).font(Sz.f(11)).foregroundStyle(.tertiary)
                        }
                        .animation(.viggo, value: h.done)
                    }
                }
            }

            if isMe, p.panelFriendsNow, !state.friends.isEmpty {
                FriendsNow(now: now)
            }

            if isMe, p.panelBulletin, !state.bulletins.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeader(title: "Opslag")
                    ForEach(state.bulletins.prefix(3)) { b in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(b.title).font(Sz.f(12, .semibold)).lineLimit(1)
                                Spacer()
                                Text(b.when).font(Sz.f(10)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Text(b.text).font(Sz.f(11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.openViggo() }
                    }
                }
            }

            if isMe, state.questionnaireCount > 0 {
                Button { state.openViggo(URL(string: "/Shared/Questionnaire/Questionnaires", relativeTo: Config.baseURL)!.absoluteURL) } label: {
                    HStack {
                        Image(systemName: "list.clipboard.fill").foregroundStyle(.orange)
                        Text("\(state.questionnaireCount) spørgeskema\(state.questionnaireCount == 1 ? "" : "er") venter på dig").font(Sz.f(12))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isMe, p.panelMessages, !state.messages.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeader(title: "Beskeder")
                    ForEach(state.messages.prefix(p.panelMsgCount)) { m in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(m.sender).font(Sz.f(12, .semibold)).lineLimit(1)
                                Spacer()
                                Text(m.when).font(Sz.f(10)).foregroundStyle(.tertiary)
                            }
                            Text(m.subject).font(Sz.f(12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.openViggo(m.link) }
                    }
                }
            }
        }
    }
}

// MARK: - Settings (tabs)

enum SettingsPage: String, CaseIterable, Identifiable {
    case konto = "Konto", generelt = "Generelt", panel = "Panel", menubar = "Menubar", timer = "Timer", kalender = "Kalender", notifikationer = "Notifikationer", venner = "Venner"
    var id: String { rawValue }
    var slug: String {
        rawValue.lowercased().replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "æ", with: "ae")
    }
    var icon: String {
        switch self {
        case .konto: return "person.fill"
        case .generelt: return "gearshape.fill"
        case .panel: return "rectangle.grid.1x2.fill"
        case .menubar: return "menubar.rectangle"
        case .timer: return "paintpalette.fill"
        case .kalender: return "calendar"
        case .notifikationer: return "bell.badge.fill"
        case .venner: return "person.2.fill"
        }
    }
    var color: Color {
        switch self {
        case .konto: return .blue
        case .generelt: return .gray
        case .panel: return .teal
        case .menubar: return .indigo
        case .timer: return .pink
        case .kalender: return .orange
        case .notifikationer: return .red
        case .venner: return .blue
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(color.gradient))
    }
}

/// A sidebar row like in System Settings: accent background when selected.
struct SidebarRow<Content: View>: View {
    var highlight: Namespace.ID? = nil
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content() }
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected {
                        // The blue highlight slides to the page you pick.
                        if let highlight {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                                .matchedGeometryEffect(id: "sel", in: highlight)
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var page: SettingsPage?
    @Namespace private var highlight

    init(initial: SettingsPage = .konto) { _page = State(initialValue: initial) }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let prof = state.profile, !state.needsLogin {
                        SidebarRow(highlight: highlight, selected: page == .konto) { withAnimation(.viggo) { page = .konto } } content: {
                            Avatar(url: prof.image, size: 34, name: prof.name)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(prof.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text("Viggo-konto").font(.system(size: 10)).opacity(0.7)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    ForEach(SettingsPage.allCases) { pg in
                        SidebarRow(highlight: highlight, selected: page == pg) { withAnimation(.viggo) { page = pg } } content: {
                            SettingsIcon(symbol: pg.icon, color: pg.color)
                            Text(pg.rawValue).font(.system(size: 13)).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 34)    // room for the window buttons
                .padding(.bottom, 10)
            }
            .frame(width: 210)
            .background(Color.primary.opacity(0.04))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text((page ?? .konto).rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 2)
                Group {
                switch page ?? .konto {
                case .konto: AccountTab()
                case .generelt: GeneralTab()
                case .panel: PanelTab()
                case .menubar: MenubarTab()
                case .timer: LessonsTab()
                case .kalender: CalendarTab()
                case .notifikationer: NotificationsTab()
                case .venner: FriendsTab()
                }
                }
                .id(page ?? .konto)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 680, height: 500)
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
                    Button("Log ind på Viggos side i stedet…") { state.loginWithBrowser() }.buttonStyle(.link)
                }
                if !state.loginMessage.isEmpty { Text(state.loginMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text(state.needsLogin ? "Log ind med SkoleIT" : "Automatisk login")
            } footer: {
                Text("Viggo+ logger selv ind, når sessionen udløber. Koden gemmes kun på din Mac.")
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

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject var updater = Updater.shared
    var body: some View {
        Form {
            Section {
                Toggle("Start Viggo+ når Mac'en starter", isOn: Binding(get: { state.launchAtLogin },
                                                                       set: { state.launchAtLogin = $0 }))
                Toggle("Vis antal ulæste beskeder og spørgeskemaer i menubaren", isOn: $p.menubarBadge)
            }
            Section("Opdateringer") {
                Toggle("Tjek automatisk for nye versioner", isOn: $p.autoUpdate)
                HStack {
                    Text("Version \(Updater.shared.current)").foregroundStyle(.secondary)
                    Spacer()
                    Text(updater.lastResult).font(.caption).foregroundStyle(.secondary)
                    Button("Tjek nu") { Task { await updater.check(manual: true) } }
                }
            }
            Section("Genvejstast") {
                Toggle("Åbn panelet med en genvejstast", isOn: $p.hotkeyEnabled)
                Picker("Tast", selection: $p.hotkeyChoice) {
                    ForEach(0..<HotKey.choices.count, id: \.self) { i in Text(HotKey.choices[i].label).tag(i) }
                }
                .disabled(!p.hotkeyEnabled)
            }
            Section("Fokus i timerne") {
                Toggle("Slå fokus til når en time starter, og fra når den slutter", isOn: $p.focusEnabled)
                TextField("Genvej når timen starter", text: $p.focusOnShortcut)
                TextField("Genvej når timen slutter", text: $p.focusOffShortcut)
                HStack {
                    Button("Test start") { state.runShortcut(p.focusOnShortcut) }
                    Button("Test slut") { state.runShortcut(p.focusOffShortcut) }
                    Spacer()
                    Button("Åbn Genveje") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                }
                Text("macOS lader ikke apps slå fokus til direkte. Lav to genveje i Genveje-appen med handlingen \"Indstil fokus\" (fx Forstyr ikke til og fra), og giv dem navnene ovenfor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: p.hotkeyEnabled) { state.setupHotKey() }
        .onChange(of: p.hotkeyChoice) { state.setupHotKey() }
    }
}

struct PanelTab: View {
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Form {
            Section("Vis i panelet") {
                Toggle("Nu-kort (hvad sker der lige nu)", isOn: $p.panelNow)
                Toggle("Resten af dagen", isOn: $p.panelTimeline)
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

struct MenubarTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $p.menubarRoutine) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis hverdag efter skoletid").font(.headline)
                        Text("Når dagens sidste time er slut, viser menubaren fx \"Aftensmad 18:00\" og \"Godnat 22:15\".")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            Section("Hvad skal vises") {
                if state.routineTitles.isEmpty {
                    Text("Log ind for at se listen").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(state.routineTitles, id: \.self) { t in
                    Toggle(t, isOn: Binding(get: { state.inMenubar(t) }, set: { state.toggleMenubar(t, $0) }))
                }
            }
            .disabled(!p.menubarRoutine)
        }
        .formStyle(.grouped)
    }
}

struct CalendarTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @State private var confirmRemove = false

    private var signature: String {
        "\(p.importSchedule)\(p.importHomework)\(p.importEvents)\(p.showBirthdays)\(p.includedRoutines)\(p.lessonAlarmMinutes)\(p.homeworkAlarm)"
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { p.imported },
                                     set: { on in if on { state.importToCalendar() } else { confirmRemove = true } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis Viggo i Apple Kalender").font(.headline)
                        Text(p.imported ? "Holdes opdateret automatisk" : "Slå til for at importere. Slå fra for at fjerne igen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Hvad skal med") {
                CalRow(title: "Skema", color: .blue, on: $p.importSchedule)
                CalRow(title: "Lektier", color: .orange, on: $p.importHomework)
                CalRow(title: "Begivenheder", color: .purple, on: $p.importEvents)
                CalRow(title: "Fødselsdage", color: .pink, on: $p.showBirthdays)
                DisclosureGroup {
                    if state.routineTitles.isEmpty {
                        Text("Log ind for at se listen").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(state.routineTitles, id: \.self) { t in
                        Toggle(t, isOn: Binding(get: { p.includedRoutines.contains(t) }, set: { state.toggleRoutine(t, $0) }))
                    }
                } label: {
                    HStack {
                        Circle().fill(.green).frame(width: 9, height: 9)
                        Text("Hverdag")
                        Spacer()
                        Text(p.includedRoutines.isEmpty ? "Ingen" : "\(p.includedRoutines.count) valgt")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!p.imported)

            Section("Påmindelser") {
                Picker("Før hver time", selection: $p.lessonAlarmMinutes) {
                    Text("Ingen").tag(0); Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15)
                }
                Toggle("Lektier dagen før kl. 18", isOn: $p.homeworkAlarm)
            }
            .disabled(!p.imported)
        }
        .formStyle(.grouped)
        .onChange(of: signature) { if p.imported { state.applyCalendar() } }
        .confirmationDialog("Fjern Viggo fra Kalender?", isPresented: $confirmRemove) {
            Button("Fjern", role: .destructive) { state.removeFromCalendar() }
        } message: {
            Text("Sletter kun de kalendere Viggo+ har lavet. Du kan slå det til igen når som helst.")
        }
    }
}

struct CalRow: View {
    let title: String
    let color: Color
    @Binding var on: Bool
    var body: some View {
        Toggle(isOn: $on) {
            HStack {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title)
            }
        }
    }
}

struct NotificationsTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Form {
            Section("Giv besked om") {
                Toggle("Flyttede eller aflyste timer", isOn: $p.notifyChanges)
                Toggle("Nye lektier", isOn: $p.notifyHomework)
                Toggle("Nye beskeder", isOn: $p.notifyMessages)
                Toggle("Nye opslag på opslagstavlen", isOn: $p.notifyBulletin)
                Toggle("Fødselsdage om morgenen", isOn: $p.notifyBirthdays)
            }
            Section("Daglig brief") {
                Toggle("Slået til", isOn: $p.briefs)
                Stepper("Morgen kl. \(p.morningHour)", value: $p.morningHour, in: 5...11).disabled(!p.briefs)
                Stepper("Aften kl. \(p.eveningHour)", value: $p.eveningHour, in: 16...23).disabled(!p.briefs)
            }
            Section {
                Button("Send test-notifikation") {
                    Notifier.shared.post("Viggo+ test", state.brief(for: Date(), prefix: "I dag"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Username and password fields. "otto1161" is shown as "otto1161@cloud.skoleit.dk".
struct SkoleITFields: View {
    let button: String
    let onSave: (String, String) -> Void
    @State private var user = ""
    @State private var pass = ""

    var body: some View {
        TextField("Brugernavn", text: $user, prompt: Text("navn1234"))
            .help(user.isEmpty || user.contains("@") ? "" : SkoleITLogin.normalize(user))
        SecureField("Adgangskode", text: $pass)
            .onSubmit(save)
        Button(button, action: save)
            .buttonStyle(.borderedProminent)
            .disabled(user.trimmingCharacters(in: .whitespaces).isEmpty || pass.isEmpty)
    }

    private func save() {
        guard !user.trimmingCharacters(in: .whitespaces).isEmpty, !pass.isEmpty else { return }
        let u = SkoleITLogin.normalize(user), p = pass
        user = ""; pass = ""
        onSave(u, p)
    }
}

/// The key next to a friend: save or remove their SkoleIT login.
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
                Button("Log ind på Viggos side i stedet…") { state.addFriend() }.buttonStyle(.link)
                if !state.friendMessage.isEmpty { Text(state.friendMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Tilføj ven")
            } footer: {
                Text("Med vennens SkoleIT-login logger Viggo+ selv vennen ind igen. Koden gemmes kun på din Mac.")
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
