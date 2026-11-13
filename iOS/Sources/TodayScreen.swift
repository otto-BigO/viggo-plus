import SwiftUI

/// The "I dag" screen on the iPhone: a big card for what is happening now, then the day,
/// tomorrow, homework, messages and friends, each in its own card.
struct TodayScreen: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared

    private var now: Date { AppState.testNow(state.tick) }

    private var firstName: String? {
        state.profile.map { $0.name.components(separatedBy: " ").first ?? $0.name }
    }

    private var greeting: String {
        let h = DateUtil.cal.component(.hour, from: now)
        let hi = h < 5 ? "Godnat" : h < 10 ? "Godmorgen" : h < 18 ? "Hej" : "Godaften"
        return firstName.map { "\(hi) \($0)" } ?? "I dag"
    }

    private static let dateF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEEE d. MMMM"; return f
    }()

    @State private var showMe = false

    var body: some View {
        let all = state.timeline(now)
        let current = all.first { $0.start <= now && $0.end > now && $0.kind != .pause }
        let next = all.first { $0.start > now && $0.kind != .pause }
        let school = all.filter { $0.kind == .lesson || $0.kind == .event }
        let shown = p.panelHidePast ? all.filter { $0.end > now } : all
        let hw = state.homework.filter { $0.day >= DateUtil.startOfDay(now) }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Self.dateF.string(from: now).capitalized)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, -8)

                    if state.needsLogin { loggedOut }
                    UpdateCard()
                    if !state.status.isEmpty {
                        Label(state.status, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                    }

                    // Until the first schedule arrives, show grey placeholders instead of
                    // "Fri resten af dagen" and zeros that would be wrong a second later.
                    let loading = state.events.isEmpty && state.lastSync == nil && !state.needsLogin
                    Group {
                        if p.panelNow {
                            HeroCard(current: current, next: next, now: now,
                                     tomorrow: state.tomorrowFirst(now)?.0)
                        }

                        let lessons = all.filter { $0.kind == .lesson }
                        StatRow(lessonsLeft: lessons.filter { $0.end > now }.count,
                                schoolEnd: lessons.map(\.end).max(),
                                homework: hw.filter { !$0.done }.count,
                                unread: state.unreadCount, now: now)
                    }
                    .redacted(reason: loading ? .placeholder : [])
                    .saturation(loading ? 0 : 1)
                    .opacity(loading ? 0.5 : 1)
                    .animation(.viggo, value: loading)

                    if p.panelBirthdays, !state.birthdaysToday.isEmpty {
                        Banner(icon: "birthday.cake.fill", tint: .pink,
                               text: "Fødselsdag i dag: \(state.birthdaysToday.joined(separator: ", "))")
                    }
                    if state.questionnaireCount > 0 {
                        Button { state.openViggo(URL(string: "/Shared/Questionnaire/Questionnaires", relativeTo: Config.baseURL)!.absoluteURL) } label: {
                            Banner(icon: "list.clipboard.fill", tint: .orange, chevron: true,
                                   text: "\(state.questionnaireCount) spørgeskema\(state.questionnaireCount == 1 ? "" : "er") venter på dig")
                        }
                        .buttonStyle(PressScale(scale: 0.98))
                    }

                    if p.panelTimeline, !shown.isEmpty {
                        Card(title: "Dagen", icon: "clock") {
                            DayList(items: shown, now: now, schoolEnd: school.map(\.end).max())
                        }
                    }

                    if let meal = state.meals[DateUtil.startOfDay(now)] {
                        Card(title: "Mad i dag", icon: "fork.knife") {
                            VStack(alignment: .leading, spacing: 10) {
                                MealLine(when: "Middag", text: meal.lunch, icon: "sun.max.fill", tint: .orange)
                                if let d = meal.dinner {
                                    Divider()
                                    MealLine(when: "Aftensmad", text: d, icon: "moon.fill", tint: .indigo)
                                }
                            }
                        }
                    }

                    if p.panelTomorrow, let (first, count) = state.tomorrowFirst(now) {
                        TomorrowCard(first: first, count: count, now: now)
                    }

                    if p.panelDuty, !state.dutyTonight.isEmpty {
                        Banner(icon: "person.badge.shield.checkmark.fill", tint: .indigo,
                               text: "Aftenvagt: \(state.dutyTonight.joined(separator: ", "))")
                    }

                    if p.panelHomework, !hw.isEmpty {
                        Card(title: "Lektier", icon: "book.fill") {
                            VStack(spacing: 0) {
                                ForEach(Array(hw.prefix(6).enumerated()), id: \.element.id) { i, h in
                                    if i > 0 { Divider().padding(.leading, 40) }
                                    HomeworkRow(h: h)
                                }
                            }
                        }
                    }

                    if p.panelMessages, !state.messages.isEmpty {
                        Card(title: "Beskeder", icon: "envelope.fill", badge: state.unreadCount) {
                            VStack(spacing: 0) {
                                ForEach(Array(state.messages.prefix(p.panelMsgCount).enumerated()), id: \.element.id) { i, m in
                                    if i > 0 { Divider() }
                                    NavigationLink(value: m.id) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack {
                                                    Text(m.sender).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                    Spacer()
                                                    Text(m.when).font(.caption).foregroundStyle(.secondary)
                                                }
                                                Text(m.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 9)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if p.panelFriendsNow, !state.friends.isEmpty {
                        Card(title: "Venner nu", icon: "person.2.fill") {
                            VStack(spacing: 0) {
                                ForEach(Array(state.friends.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { Divider().padding(.leading, 44) }
                                    let (text, free) = state.friendStatus(f, now: now)
                                    let expired = state.friendExpired.contains(f.id)
                                    let gaps = expired ? [] : state.freeTogether(with: state.friendEvents[f.id] ?? [], now: now)
                                    NavigationLink(value: Found.person(f.viggoID)) {
                                    HStack(spacing: 12) {
                                        Avatar(url: f.image, size: 36, name: f.name).opacity(expired ? 0.4 : 1)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.firstName).font(.body.weight(.medium))
                                            Text(expired ? "Skal logge ind" : text).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if let g = gaps.first {
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text("Fri sammen").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                                                Text("\(DateUtil.hm(g.0))-\(DateUtil.hm(g.1))").font(.footnote.monospacedDigit().weight(.semibold))
                                            }
                                        } else {
                                            Circle().fill(free ? Color.green : Color.orange).frame(width: 9, height: 9)
                                        }
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if p.panelBulletin, !state.bulletins.isEmpty {
                        Card(title: "Opslag", icon: "megaphone.fill") {
                            VStack(spacing: 0) {
                                ForEach(Array(state.bulletins.prefix(3).enumerated()), id: \.element.id) { i, b in
                                    if i > 0 { Divider() }
                                    NavigationLink(value: b) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(b.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                Spacer()
                                                Text(b.when).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                            }
                                            Text(b.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .padding(.vertical, 9)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let s = state.lastSync {
                        Text("Synket kl. \(DateUtil.hm(s))").font(.footnote).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .animation(.viggo, value: current?.id)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await state.sync() }
            .navigationDestination(for: Int.self) { ThreadScreen(id: $0) }
            .navigationDestination(for: Bulletin.self) { BulletinScreen(b: $0) }
            .navigationDestination(for: Found.self) { FoundScreen(found: $0) }
            .navigationDestination(isPresented: $showMe) { if let id = state.profile?.id { PersonScreen(id: id) } }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SearchButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if state.profile != nil {
                            Button { showMe = true } label: { Label("Se din profil", systemImage: "person.crop.circle") }
                        }
                        Button { state.openViggo() } label: { Label("Åbn Viggo", systemImage: "safari") }
                        Button(role: .destructive) { state.logout() } label: { Label("Log ud", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: {
                        if let p = state.profile { Avatar(url: p.image, size: 32, name: p.name) }
                        else { Image(systemName: "person.crop.circle") }
                    }
                }
            }
        }
    }

    private var loggedOut: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(.orange)
            Text("Du er logget ud af Viggo").font(.body.weight(.medium))
            Spacer()
            Button("Log ind") { state.loginWithBrowser() }.buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - Tomorrow

/// The first thing tomorrow. Tap it and the whole of tomorrow folds out underneath.
private struct TomorrowCard: View {
    @EnvironmentObject var state: AppState
    let first: ViggoEvent
    let count: Int
    let now: Date
    @State private var open = false

    var body: some View {
        let day = DateUtil.add(.day, 1, DateUtil.startOfDay(now))
        let items = state.timeline(day)
        let school = items.filter { $0.kind == .lesson || $0.kind == .event }
        Card(title: "I morgen", icon: "sunrise.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Haptic.tap()
                    withAnimation(.unfold) { open.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(first.shortTitle).font(.headline)
                            Text(open ? "Første punkt" : "Tryk for hele dagen").font(.subheadline).foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(DateUtil.hm(first.start)).font(.title3.monospacedDigit().weight(.semibold))
                            HStack(spacing: 4) {
                                Text("\(count) \(count == 1 ? "punkt" : "punkter")")
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                                    .rotationEffect(.degrees(open ? 180 : 0))
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.98))
                if open {
                    Divider()
                    DayList(items: items, now: day, schoolEnd: school.map(\.end).max())
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.08)),
                                                removal: .opacity.animation(.easeIn(duration: 0.12))))
                }
            }
        }
    }
}

// MARK: - Now card

private struct HeroCard: View {
    @EnvironmentObject var state: AppState
    let current: ViggoEvent?
    let next: ViggoEvent?
    let now: Date
    let tomorrow: ViggoEvent?

    private func mins(_ a: Date, _ b: Date) -> String {
        let m = max(0, Int(b.timeIntervalSince(a) / 60.0 + 0.99))
        return m >= 60 ? "\(m / 60) t \(m % 60) min" : "\(m) min"
    }

    private var tint: Color { (current ?? next)?.subjectColor ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let c = current {
                label("NU", icon: "dot.radiowaves.left.and.right")
                title(c)
                let frac = min(1, max(0, now.timeIntervalSince(c.start) / max(1, c.end.timeIntervalSince(c.start))))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(mins(now, c.end)).font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                        Text("tilbage").font(.headline).opacity(0.8)
                        Spacer()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(.white).frame(width: max(8, g.size.width * frac))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(DateUtil.hm(c.start)); Spacer(); Text(DateUtil.hm(c.end))
                    }
                    .font(.footnote.monospacedDigit().weight(.medium)).opacity(0.8)
                }
                info(c)
                if let n = next {
                    Divider().overlay(.white.opacity(0.35))
                    HStack {
                        Text("Bagefter").font(.subheadline).opacity(0.8)
                        Text(n.shortTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(DateUtil.hm(n.start)).font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
            } else if let n = next {
                label("NÆSTE", icon: "arrow.forward.circle.fill")
                title(n)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("om").font(.headline).opacity(0.8)
                    Text(mins(now, n.start)).font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    Spacer()
                    Text("kl. \(DateUtil.hm(n.start))").font(.headline.monospacedDigit()).opacity(0.85)
                }
                info(n)
            } else {
                label("FRI", icon: "moon.stars.fill")
                Text("Fri resten af dagen").font(.system(size: 30, weight: .bold, design: .rounded))
                if let t = tomorrow {
                    Text("I morgen starter du med \(t.shortTitle) kl. \(DateUtil.hm(t.start))")
                        .font(.headline).opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: tint.opacity(0.35), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .onTapGesture { if let e = current ?? next, e.kind != .custom { state.openLesson(e) } }
        .animation(.viggo, value: now)
    }

    private func label(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon).font(.caption.weight(.bold)).tracking(1).opacity(0.85)
    }

    private func title(_ e: ViggoEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(e.shortTitle).font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.7)
            HStack(spacing: 14) {
                if !e.room.isEmpty { Label(e.room, systemImage: "mappin.and.ellipse") }
                if let t = e.teachers.first { Label(t, systemImage: "person.fill").lineLimit(1) }
            }
            .font(.subheadline.weight(.medium)).opacity(0.9)
        }
    }

    @ViewBuilder private func info(_ e: ViggoEvent) -> some View {
        if e.hasInfo {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.alignleft").font(.footnote.weight(.bold)).padding(.top, 2)
                Text(e.notes.replacingOccurrences(of: "\n", with: " ")).font(.subheadline).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.18)))
        }
    }
}

// MARK: - Quick numbers

private struct StatRow: View {
    let lessonsLeft: Int
    let schoolEnd: Date?
    let homework: Int
    let unread: Int
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Stat(value: "\(lessonsLeft)", label: lessonsLeft == 1 ? "time tilbage" : "timer tilbage", icon: "graduationcap.fill", tint: .blue)
            if let e = schoolEnd, e > now {
                Stat(value: DateUtil.hm(e), label: "fri kl.", icon: "figure.walk", tint: .green)
            } else {
                Stat(value: "Fri", label: "i dag", icon: "figure.walk", tint: .green)
            }
            Stat(value: "\(homework)", label: "lektier", icon: "book.fill", tint: .orange)
            if unread > 0 {
                Stat(value: "\(unread)", label: "ulæste", icon: "envelope.fill", tint: .red)
            }
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Cards

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    var badge = 0
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                Text(title).font(.title3.weight(.bold))
                if badge > 0 {
                    Text("\(badge)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                }
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct Banner: View {
    let icon: String
    let tint: Color
    var chevron = false
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.15)))
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - The day

private struct DayList: View {
    let items: [ViggoEvent]
    let now: Date
    let schoolEnd: Date?

    var body: some View {
        let afterSchool = items.first { ($0.kind == .routine || $0.kind == .custom) && $0.start >= (schoolEnd ?? .distantFuture) }?.id
        VStack(spacing: 0) {
            ForEach(items) { e in
                if e.id == afterSchool, items.contains(where: { $0.kind == .lesson }) {
                    HStack(spacing: 8) {
                        Rectangle().fill(.quaternary).frame(height: 1)
                        Text("Efter skole").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Rectangle().fill(.quaternary).frame(height: 1)
                    }
                    .padding(.vertical, 8)
                }
                if e.kind == .pause { PauseRow(e: e, now: now) } else { DayRow(e: e, now: now) }
            }
        }
    }
}

private struct PauseRow: View {
    let e: ViggoEvent
    let now: Date
    var body: some View {
        let current = e.start <= now && e.end > now
        let mins = Int(e.end.timeIntervalSince(e.start) / 60)
        HStack(spacing: 12) {
            Text(DateUtil.hm(e.start)).font(.footnote.monospacedDigit()).frame(width: 48, alignment: .leading)
            Image(systemName: "cup.and.saucer.fill").font(.caption)
            Text("Pause, \(mins) min").font(.footnote.weight(current ? .semibold : .regular))
            Spacer()
            if current { Text("Nu").font(.caption.weight(.bold)).foregroundStyle(.tint) }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .opacity(e.end <= now ? 0.4 : 1)
    }
}

private struct DayRow: View {
    @EnvironmentObject var state: AppState
    let e: ViggoEvent
    let now: Date
    @State private var open = false

    private var isFood: Bool {
        let t = e.title.lowercased()
        return e.kind == .routine && e.hasInfo && (t.hasPrefix("middag") || t.hasPrefix("aftensmad"))
    }

    var body: some View {
        let current = e.start <= now && e.end > now
        let past = e.end <= now
        let quiet = e.kind == .routine
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DateUtil.hm(e.start)).font(.subheadline.monospacedDigit().weight(.semibold))
                    if !quiet { Text(DateUtil.hm(e.end)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .frame(width: 48, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(e.subjectColor.opacity(quiet ? 0.5 : 1))
                    .frame(width: 4, height: quiet ? 22 : 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.shortTitle).font(quiet ? .subheadline : .body.weight(.semibold))
                        .foregroundStyle(quiet && !current ? .secondary : .primary)
                        .lineLimit(2)
                    let sub = [e.room, e.teachers.first ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !quiet, !sub.isEmpty {
                        Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if isFood {
                        Label(e.notes, systemImage: "fork.knife").font(.footnote).foregroundStyle(.secondary)
                            .lineLimit(open ? nil : 1)
                    }
                }
                Spacer(minLength: 4)
                if current {
                    Text("NU").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(e.subjectColor))
                } else if e.hasInfo && !isFood {
                    Image(systemName: open ? "chevron.up" : "text.alignleft").font(.footnote.weight(.bold)).foregroundStyle(.tint)
                }
            }
            if open && e.hasInfo && !isFood {
                VStack(alignment: .leading, spacing: 10) {
                    Text(e.notes).font(.subheadline).textSelection(.enabled)
                    HStack(spacing: 8) {
                        ForEach(e.links, id: \.self) { u in
                            Link(destination: u) {
                                Label(u.host?.replacingOccurrences(of: "www.", with: "") ?? "Link", systemImage: "arrow.up.right")
                                    .font(.footnote.weight(.medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        }
                        Spacer(minLength: 0)
                        Button("Detaljer") { state.openLesson(e) }.font(.footnote.weight(.medium))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
                .padding(.leading, 64)
                .transition(.opacity)
            }
        }
        .padding(.vertical, quiet ? 6 : 8)
        .padding(.horizontal, current ? 10 : 0)
        .background {
            if current { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(e.subjectColor.opacity(0.12)) }
        }
        .padding(.horizontal, current ? -10 : 0)
        .opacity(past ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if e.hasInfo { Haptic.tap(); withAnimation(.unfold) { open.toggle() } }
            else if e.kind != .custom { state.openLesson(e) }
        }
    }
}

private struct MealLine: View {
    let when: String
    let text: String
    let icon: String
    let tint: Color
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(when).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct HomeworkRow: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    let h: Homework
    var body: some View {
        HStack(spacing: 12) {
            Button { if p.panelHomeworkTick { state.toggleHomework(h) } } label: {
                Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(h.done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressScale(scale: 0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).font(.body).strikethrough(h.done).foregroundStyle(h.done ? .secondary : .primary).lineLimit(2)
                if !h.group.isEmpty { Text(h.group).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            .contentShape(Rectangle())
            .onTapGesture { Platform.open(h.link) }
            Spacer()
            Text(DateUtil.day(h.due)).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .animation(.viggo, value: h.done)
    }
}
