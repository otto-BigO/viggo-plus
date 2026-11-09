import SwiftUI

// The panel's building blocks, used by the Mac menubar panel and the iPhone app's I dag screen.

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
    /// Calmer spring for things that fold out (a note, a dish), so the panel grows smoothly.
    static let unfold = Animation.spring(response: 0.42, dampingFraction: 0.94)
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

extension Notification.Name { static let viggoToggleNote = Notification.Name("viggoToggleNote") }

struct TimelineRow: View {
    let e: ViggoEvent
    let now: Date
    var dividerAbove = false
    var tappable = true
    /// Rows with a note from the teacher open in place, so you can read it right in the panel.
    @State private var expanded = ProcessInfo.processInfo.environment["VIGGO_EXPAND_NOTES"] != nil
    private var hasNote: Bool { e.hasInfo || !e.links.isEmpty }
    /// Middag and Aftensmad carry the day's food as their note.
    private var isFood: Bool {
        let t = e.title.lowercased()
        return e.kind == .routine && e.hasInfo && (t.hasPrefix("middag") || t.hasPrefix("aftensmad"))
    }
    var body: some View {
        if e.kind == .pause { pauseRow } else { row }
    }

    /// A break between lessons: quiet, just the time and how long.
    private var pauseRow: some View {
        let current = e.start <= now && e.end > now
        let mins = Int(e.end.timeIntervalSince(e.start) / 60)
        return HStack(spacing: 10) {
            Text(DateUtil.hm(e.start)).font(Sz.mono(10.5))
                .foregroundStyle(current ? Color.accentColor : Color.secondary.opacity(0.6))
                .frame(width: 42 * Sz.k, alignment: .leading)
            Text("Pause · \(mins) min").font(Sz.f(10.5, current ? .semibold : .regular)).foregroundStyle(current ? .secondary : .tertiary)
            Spacer()
        }
        .opacity(e.end <= now ? 0.35 : 1)
    }

    private func linkLabel(_ u: URL) -> String {
        let host = (u.host ?? u.absoluteString).replacingOccurrences(of: "www.", with: "")
        if host.contains("youtube") || host.contains("youtu.be") { return "YouTube" }
        if host.contains("drive.google") || host.contains("docs.google") { return "Drev" }
        return host
    }

    /// The teacher's note, shown under the row.
    private var noteBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if e.hasInfo {
                Text(e.notes).font(Sz.f(11.5)).foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(e.links, id: \.self) { u in
                    Link(destination: u) {
                        Label(linkLabel(u), systemImage: "arrow.up.right").font(Sz.f(10.5, .medium)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                Button("Detaljer") { AppState.shared.openLesson(e) }
                    .buttonStyle(.plain).font(Sz.f(10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.05)))
        .padding(.leading, 52 * Sz.k)
        .padding(.bottom, 2)
    }

    /// Everyday routines (aftensmad, godnat) are shown a little smaller, so the lessons stand out.
    private var quiet: Bool { e.kind == .routine }

    private var row: some View {
        let current = e.start <= now && e.end > now
        let past = e.end <= now
        return VStack(alignment: .leading, spacing: 4) {
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
                    .font(Sz.mono(quiet ? 11 : 12))
                    .foregroundStyle(current ? Color.accentColor : .secondary)
                    .frame(width: 42 * Sz.k, alignment: .leading)
                if let c = e.customColor ?? (e.kind == .custom ? Color.green : nil) {
                    RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 3, height: 13 * Sz.k)
                }
                Text(e.shortTitle)
                    .font(Sz.f(quiet ? 12 : 13, current ? .semibold : .regular))
                    .foregroundStyle(quiet && !current ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if hasNote && !isFood {
                    Image(systemName: expanded ? "chevron.up" : "text.alignleft").font(Sz.f(10, .bold)).foregroundStyle(Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                        .help(expanded ? "Skjul info" : "Der er info fra læreren")
                }
                if !e.room.isEmpty {
                    Text(e.room).font(Sz.f(11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
            }
            .opacity(past ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if hasNote { withAnimation(.unfold) { expanded.toggle() } }
                else if e.kind != .custom { AppState.shared.openLesson(e) }
            }
            if isFood {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "fork.knife").font(Sz.f(9)).foregroundStyle(.tertiary)
                    Text(e.notes).font(Sz.f(11)).foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.leading, 52 * Sz.k)
                .opacity(past ? 0.35 : 1)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.unfold) { expanded.toggle() } }
            } else if expanded && hasNote {
                // The room opens first, then the text fades in, so it never slides over the rows below.
                noteBox.transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                                               removal: .opacity.animation(.easeIn(duration: 0.1))))
            }
        }
        // Test hook for --unfold-test: fold this row's note out or in.
        .onReceive(NotificationCenter.default.publisher(for: .viggoToggleNote)) { n in
            if (n.object as? Int) == e.id, hasNote { withAnimation(.unfold) { expanded.toggle() } }
        }
        .help(e.kind == .custom ? "Dit eget punkt" : isFood ? "Dagens mad fra madplanen" : hasNote ? (expanded ? "" : "Læs info fra læreren") : "Se detaljer")
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
        VStack(alignment: .leading, spacing: 6) {
            if let c = current {
                Text(name.map { "\($0) har nu" } ?? "Nu").font(Sz.f(10, .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(c.shortTitle).font(Sz.f(17, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("\(mins(now, c.end)) tilbage").font(Sz.f(12, .medium)).foregroundStyle(.secondary).fixedSize()
                        .contentTransition(.numericText(countsDown: true))
                }
                let frac = min(1, max(0, now.timeIntervalSince(c.start) / max(1, c.end.timeIntervalSince(c.start))))
                Capsule().fill(.primary.opacity(0.1)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(Color.accentColor).frame(width: g.size.width * frac) }
                    }
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.6), value: now)
                HStack {
                    if !c.room.isEmpty { Label(c.room, systemImage: "mappin").font(Sz.f(11)).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(DateUtil.hm(c.start))–\(DateUtil.hm(c.end))").font(Sz.mono(11)).foregroundStyle(.secondary)
                }
            } else if let n = next {
                Text(name.map { "\($0) er fri" } ?? "Fri").font(Sz.f(10, .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(n.shortTitle).font(Sz.f(17, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
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
                            .font(Sz.f(11)).foregroundStyle(.secondary).lineLimit(1)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Se info fra læreren")
            }
            if current != nil, let n = next {
                Divider().opacity(0.5).padding(.vertical, 1)
                HStack {
                    Text("Næste").font(Sz.f(11)).foregroundStyle(.secondary)
                    Text(n.shortTitle).font(Sz.f(12, .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(DateUtil.hm(n.start)).font(Sz.mono(12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
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
            Avatar(url: url, size: 24, name: fullName)
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
                        if expired { Circle().fill(.orange).frame(width: 8, height: 8).overlay(Circle().stroke(.background, lineWidth: 1.5)) }
                    }
                    .padding(3)
                    .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .help(fullName ?? label)
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
        let next = all.first { $0.start > now && $0.kind != .pause }
        let shown = p.panelHidePast ? all.filter { $0.end > now } : all
        let schoolEnd = all.filter { $0.kind == .lesson || $0.kind == .event }.map(\.end).max() ?? .distantPast
        let firstEvening = shown.first { ($0.kind == .routine || $0.kind == .custom) && $0.start >= schoolEnd }?.id
        let hasSchool = shown.contains { $0.kind == .lesson || $0.kind == .event }
        let hw = homework.filter { $0.day >= DateUtil.startOfDay(now) }

        VStack(alignment: .leading, spacing: 10) {
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
                VStack(alignment: .leading, spacing: 6) {
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
                VStack(alignment: .leading, spacing: 6) {
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
                                .onTapGesture { if isMe { Platform.open(h.link) } }
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
                        Text(e.kind == .routine && ["middag", "aftensmad"].contains(where: { e.title.lowercased().hasPrefix($0) }) ? "Dagens mad" : "Info fra læreren").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
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
                    Button("Åbn i Viggo") { Platform.open(e.link) }
                }
            }
            .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 18)
        }
        #if os(macOS)
        .frame(width: 420)
        .frame(minHeight: 240, maxHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        #endif
    }
}

// MARK: - Friends right now

struct FriendsNow: View {
    @EnvironmentObject var state: AppState
    let now: Date

    private func status(_ f: Friend) -> (String, Bool) { state.friendStatus(f, now: now) }

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

struct SkoleITFields: View {
    let button: String
    let onSave: (String, String) -> Void
    @State private var user = ""
    @State private var pass = ""

    var body: some View {
        TextField("Brugernavn", text: $user, prompt: Text("navn1234"))
            .help(user.isEmpty || user.contains("@") ? "" : SkoleITLogin.normalize(user))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.username)
            #endif
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


/// Apple-style sign-in sheet: a lock that pulses while it works, steps that fill in as the
/// login moves through Viggo, UNI-Login and SkoleIT, and a shield that checks off when it is done.
struct LoginCard: View {
    @EnvironmentObject var state: AppState
    let stage: LoginStage

    private var done: Bool { stage == .success }
    private var failed: Bool { if case .failure = stage { return true } else { return false } }
    private var symbol: String {
        done ? "checkmark.shield.fill" : failed ? "exclamationmark.shield.fill" : stage == .saving ? "lock.fill" : "lock.shield.fill"
    }
    private var tint: Color { done ? .green : failed ? .orange : .accentColor }
    private var title: String {
        let who = state.loginStageName
        if done { return who.map { "\($0.prefix(1).uppercased() + $0.dropFirst()) er logget ind" } ?? "Du er logget ind" }
        if failed { return "Kunne ikke logge ind" }
        if stage == .saving { return "Gemmer login" }
        return who.map { "Logger \($0) ind" } ?? "Logger ind"
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 76, height: 76)
                    .scaleEffect(done ? 1.08 : 1)
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: !done && !failed)
                    .symbolEffect(.bounce, value: done)
                    .symbolEffect(.bounce, value: failed)
            }
            VStack(spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(stage.text)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .id(stage.text)
                    .transition(.opacity.combined(with: .offset(y: 3)))
            }
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(i <= stage.step ? tint : Color.primary.opacity(0.12))
                        .frame(width: i == stage.step && !done && !failed ? 18 : 6, height: 6)
                }
            }
            if failed {
                Button("OK") { state.dismissLoginCard() }.keyboardShortcut(.defaultAction)
            } else {
                Label("Krypteret forbindelse til SkoleIT", systemImage: "lock.fill")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 22)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .animation(.viggo, value: stage)
    }
}

/// Dims the settings page and shows the sign-in card on top while a login runs.
struct LoginCardOverlay: ViewModifier {
    @EnvironmentObject var state: AppState
    func body(content: Content) -> some View {
        content.overlay {
            if let st = state.loginStage {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                        .onTapGesture { if case .failure = st { state.dismissLoginCard() } }
                    LoginCard(stage: st)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .animation(.viggo, value: state.loginStage)
    }
}
