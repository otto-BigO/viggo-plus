import SwiftUI
import CryptoKit
import ImageIO
#if os(iOS)
import UIKit
#endif

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

    @State private var loaded: Image?

    var body: some View {
        Group {
            if let img = loaded ?? url.flatMap(AvatarCache.image) {
                img.resizable().scaledToFill()
            } else if initials.isEmpty {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            } else {
                Circle().fill(tint.gradient)
                    .overlay(Text(initials).font(.system(size: size * 0.38, weight: .semibold, design: Fomo.design)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            guard let url, AvatarCache.image(url) == nil else { return }
            loaded = await AvatarCache.load(url)
        }
    }
}

/// Pictures of people, kept in memory once loaded and shrunk to a small size, and on disk for a
/// week so the next launch shows them at once. AsyncImage fetched every picture again each time
/// a row came back, which made search lag.
@MainActor
enum AvatarCache {
    private static var images: [URL: Image] = [:]
    private static var running: [URL: Task<Image?, Never>] = [:]

    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ViggoPlus/avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func file(_ url: URL) -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name + ".img")
    }

    static func image(_ url: URL) -> Image? { images[url] }

    static func load(_ url: URL) async -> Image? {
        if let i = images[url] { return i }
        if let t = running[url] { return await t.value }
        let path = file(url)
        let t = Task<Image?, Never> {
            await Task.detached(priority: .utility) { () -> Image? in
                let fm = FileManager.default
                let age = (try? fm.attributesOfItem(atPath: path.path)[.modificationDate] as? Date).map { -$0.timeIntervalSinceNow } ?? .infinity
                if age < 7 * 86400, let d = try? Data(contentsOf: path), let i = decode(d, shrink: false) { return i.0 }
                let fetched = await DownloadGate.shared.run { try? await URLSession.shared.data(from: url).0 }
                guard let data = fetched, let (img, small) = decode(data, shrink: true) else {
                    // Offline: an old picture is better than none.
                    if let d = try? Data(contentsOf: path) { return decode(d, shrink: false)?.0 }
                    return nil
                }
                try? small.write(to: path, options: .atomic)
                return img
            }.value
        }
        running[url] = t
        let i = await t.value
        running[url] = nil
        if let i {
            if images.count > 600 { images.removeAll() }
            images[url] = i
        }
        return i
    }

    /// The picture, plus the bytes to keep on disk. ImageIO decodes straight to a small size, so a
    /// big profile photo never sits in memory at full resolution (the Mac used to keep the original).
    nonisolated private static func decode(_ data: Data, shrink: Bool) -> (Image, Data)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 240]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        #if os(macOS)
        let image = Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        #else
        let image = Image(uiImage: UIImage(cgImage: cg))
        #endif
        guard shrink else { return (image, data) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return (image, data) }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return (image, CGImageDestinationFinalize(dest) ? out as Data : data)
    }
}

/// At most a few picture downloads at a time. Scrolling through everyone used to start hundreds at
/// once, and the ones on screen had to wait behind the ones already scrolled past.
actor DownloadGate {
    static let shared = DownloadGate(limit: 6)
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }

    func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        if active >= limit { await withCheckedContinuation { waiting.append($0) } } else { active += 1 }
        defer { if waiting.isEmpty { active -= 1 } else { waiting.removeLast().resume() } } // newest first: that is the row on screen now
        return await work()
    }
}

struct SectionHeader: View {
    let title: String
    @ObservedObject var p = Prefs.shared
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10 * (p.panelLarge ? 1.15 : 1), weight: .semibold, design: Fomo.design))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}

/// Font sizes that follow the "Stor tekst" setting.
struct Sz {
    static var k: CGFloat { Prefs.shared.panelLarge ? 1.18 : 1 }
    static func f(_ base: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: base * k, weight: w, design: Fomo.design) }
    static func mono(_ base: CGFloat) -> Font { .system(size: base * k, weight: .regular, design: .monospaced) }
}

extension Notification.Name { static let viggoToggleNote = Notification.Name("viggoToggleNote") }

#if os(macOS)
// The menubar panel's rows: the iPhone draws its own (DayList in TodayScreen).
struct TimelineRow: View {
    let e: ViggoEvent
    let now: Date
    var dividerAbove = false
    var tappable = true
    /// Rows with a note from the teacher open in place, so you can read it right in the panel.
    @State private var expanded = ProcessInfo.processInfo.environment["VIGGO_EXPAND_NOTES"] != nil
    private var hasNote: Bool { !e.isTraining && (e.hasInfo || !e.links.isEmpty) }
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
                .foregroundStyle(current ? Color.primary : Fomo.text2.opacity(0.7))
                .frame(width: 42 * Sz.k, alignment: .leading)
            Color.clear.frame(width: 3, height: 1)
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
                    .background(Capsule().fill(Fomo.accent.opacity(0.16)))
                    .foregroundStyle(Fomo.accent)
                }
                Spacer(minLength: 0)
                Button("Detaljer") { AppState.shared.openLesson(e) }
                    .buttonStyle(.plain).font(Sz.f(10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(10)
        .padding(.leading, TimelineRow.titleInset)
        .padding(.bottom, 2)
    }

    /// Where every title starts: time column, colour bar and the gaps between them.
    static var titleInset: CGFloat { 42 * Sz.k + 23 }

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
                    .foregroundStyle(current ? e.subjectColor : .secondary)
                    .frame(width: 42 * Sz.k, alignment: .leading)
                // Routines get an empty slot where lessons have their colour bar, so every title
                // starts at the same line instead of two ragged columns.
                RoundedRectangle(cornerRadius: 1.5).fill(quiet ? Color.clear : e.subjectColor).frame(width: 3, height: 13 * Sz.k)
                Text(e.shortTitle)
                    .font(Sz.f(quiet ? 12 : 13, current ? .semibold : .regular))
                    .foregroundStyle(quiet && !current ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if hasNote && !isFood {
                    Image(systemName: expanded ? "chevron.up" : "text.alignleft").font(Sz.f(10, .bold)).foregroundStyle(Fomo.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .help(expanded ? "Skjul info" : "Der er info fra læreren")
                }
                if e.isTraining {
                    Image(systemName: expanded ? "chevron.up" : "dumbbell.fill").font(Sz.f(10, .bold))
                        .foregroundStyle(expanded ? Fomo.accent : Fomo.green)
                        .contentTransition(.symbolEffect(.replace))
                }
                if LessonNotes.shared.hasNote(e) {
                    Image(systemName: "note.text").font(Sz.f(10, .semibold)).foregroundStyle(.secondary).help("Du har noter til timen")
                }
                if !e.room.isEmpty {
                    Text(e.room).font(Sz.f(11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
            }
            .opacity(past ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if e.isTraining || hasNote { withAnimation(.unfold) { expanded.toggle() } }
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
                .padding(.leading, TimelineRow.titleInset)
                .opacity(past ? 0.35 : 1)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.unfold) { expanded.toggle() } }
            } else if expanded && e.isTraining {
                // The workout's exercises, so you can see what to do without opening Træning.
                TrainingEventBox(e: e)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(10)
                    .padding(.leading, TimelineRow.titleInset)
                    .padding(.bottom, 2)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                                            removal: .opacity.animation(.easeIn(duration: 0.1))))
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
        .help(e.isTraining ? (expanded ? "" : "Se øvelserne") : e.kind == .custom ? "Dit eget punkt" : isFood ? "Dagens mad fra madplanen" : hasNote ? (expanded ? "" : "Læs info fra læreren") : "Se detaljer")
    }
}

struct NowCard: View {
    let current: ViggoEvent?
    let next: ViggoEvent?
    let now: Date
    let name: String?

    /// The big number and the small word under it: "35" over "min tilbage", "1:05" over "timer tilbage".
    private func count(_ a: Date, _ b: Date) -> (String, String) {
        let m = max(0, Int(b.timeIntervalSince(a) / 60.0 + 0.99))
        return m >= 60 ? ("\(m / 60):" + String(format: "%02d", m % 60), "timer") : ("\(m)", "min")
    }

    private func bigNumber(_ v: (String, String), suffix: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(v.0).font(.system(size: 26 * Sz.k, weight: .semibold, design: Fomo.design)).monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.viggo, value: v.0)
            Text("\(v.1) \(suffix)").font(Sz.f(10, .medium)).foregroundStyle(Fomo.text2)
        }
        .fixedSize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = current {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.map { "\($0) har nu" } ?? "Nu").font(Sz.f(10, .semibold)).foregroundStyle(Fomo.text2)
                        Text(c.shortTitle).font(Sz.f(17, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        if !c.room.isEmpty { Text(c.room).font(Sz.f(11)).foregroundStyle(Fomo.text2) }
                    }
                    Spacer(minLength: 8)
                    bigNumber(count(now, c.end), suffix: "tilbage")
                }
                GlideBar(start: c.start, end: c.end, now: now, color: c.subjectColor)
                HStack {
                    Text(DateUtil.hm(c.start)); Spacer(); Text(DateUtil.hm(c.end))
                }
                .font(Sz.f(10, .medium)).monospacedDigit().foregroundStyle(Fomo.text2)
            } else if let n = next {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.map { "\($0) er fri" } ?? "Fri").font(Sz.f(10, .semibold)).foregroundStyle(Fomo.text2)
                        Text(n.shortTitle).font(Sz.f(17, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        Text(n.room.isEmpty ? "kl. \(DateUtil.hm(n.start))" : "kl. \(DateUtil.hm(n.start)) · \(n.room)")
                            .font(Sz.f(11)).monospacedDigit().foregroundStyle(Fomo.text2)
                    }
                    Spacer(minLength: 8)
                    bigNumber(count(now, n.start), suffix: "til start")
                }
            } else {
                Text(name.map { "\($0) har fri resten af dagen" } ?? "Fri resten af dagen").font(Sz.f(15, .semibold))
            }
            if let info = (current ?? next).flatMap({ $0.hasInfo ? $0 : nil }) {
                Button { AppState.shared.openLesson(info) } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.alignleft").font(Sz.f(10, .bold)).foregroundStyle(Fomo.accent)
                            .padding(.top, 2)
                        Text(info.notes.replacingOccurrences(of: "\n", with: " "))
                            .font(Sz.f(11)).foregroundStyle(Fomo.text2).lineLimit(1)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Se info fra læreren")
            }
            if current != nil, let n = next {
                HStack {
                    Text("Næste").font(Sz.f(11)).foregroundStyle(Fomo.text2)
                    Text(n.shortTitle).font(Sz.f(12, .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(DateUtil.hm(n.start)).font(Sz.f(12, .medium)).monospacedDigit().foregroundStyle(Fomo.text2)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .surface(12)
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
                                Circle().stroke(Fomo.accent, lineWidth: 2).padding(-2.5)
                                    .matchedGeometryEffect(id: "ring", in: ring)
                            } else {
                                Circle().stroke(Fomo.accent, lineWidth: 2).padding(-2.5)
                            }
                        }
                    }
                    .opacity(expired ? 0.4 : 1)
                    .overlay(alignment: .topTrailing) {
                        if expired { Circle().fill(Fomo.warn).frame(width: 8, height: 8).overlay(Circle().stroke(.background, lineWidth: 1.5)) }
                    }
                    .padding(3)
                    .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .help(fullName ?? label)
    }
}

/// You and your friends as one fixed group: overlapping faces in a capsule.
/// The size never changes, so nothing moves when you pick someone.
struct FriendGroup: View {
    struct Person { let id: UUID?; let url: URL?; let name: String?; let label: String; var expired = false }
    let people: [Person]
    let selected: UUID?
    var size: CGFloat = 24
    var maxWidth: CGFloat = 150
    let pick: (UUID?) -> Void
    @State private var hover: UUID??

    private var step: CGFloat {
        guard people.count > 1 else { return size }
        return min(size * 0.78, (maxWidth - 8 - size) / CGFloat(people.count - 1))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(people.enumerated()), id: \.offset) { i, p in
                let on = p.id == selected
                Button { pick(p.id) } label: {
                    Avatar(url: p.url, size: size, name: p.name)
                        .opacity(p.expired && !on ? 0.45 : 1)
                        .overlay(Circle().stroke(on ? Fomo.accent : Fomo.surface, lineWidth: on ? 2 : 1.5))
                        .overlay(alignment: .topTrailing) {
                            if p.expired { Circle().fill(Fomo.warn).frame(width: 7, height: 7).overlay(Circle().stroke(Fomo.surface, lineWidth: 1.5)) }
                        }
                        .scaleEffect(hover == .some(p.id) && !on ? 1.08 : 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(p.label)
                .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h ? .some(p.id) : (hover == .some(p.id) ? nil : hover) } }
                .offset(x: CGFloat(i) * step)
                .zIndex(on ? 100 : hover == .some(p.id) ? 50 : Double(people.count - i))
            }
        }
        .frame(width: size + CGFloat(max(people.count - 1, 0)) * step, height: size, alignment: .leading)
        .padding(4)
        .background(Capsule().fill(Fomo.surface))
        .animation(.viggo, value: selected)
    }
}

/// Same layout for you and your friends.
struct DayPanel: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @ObservedObject private var deadlines = Deadlines.shared
    /// So the pack list shows up as soon as there is something to pack.
    @ObservedObject private var packStore = PackStore.shared
    let name: String?
    let events: [ViggoEvent]
    let homework: [Homework]
    let now: Date
    var friend: Friend? = nil

    var body: some View {
        let isMe = name == nil
        let all = state.timeline(now, from: isMe ? nil : events)
        let current = all.first { $0.start <= now && $0.end > now }
        let next = all.first { $0.start > now && $0.kind != .pause }
        let shown = p.panelHidePast ? all.filter { $0.end > now } : all
        let schoolEnd = AppState.schoolDay(all).map(\.end).max() ?? .distantPast
        let firstEvening = shown.first { ($0.kind == .routine || $0.kind == .custom) && $0.start >= schoolEnd }?.id
        let hasSchool = shown.contains { $0.kind == .lesson || $0.kind == .event }
        let hw = homework.filter { $0.day >= DateUtil.startOfDay(now) }

        VStack(alignment: .leading, spacing: 10) {
            if p.panelNow, !events.isEmpty {
                NowCard(current: current, next: next, now: now, name: name)
            }

            if let name, p.friendsFreeTogether {
                let gaps = state.freeTogether(with: events, now: now)
                HStack(alignment: .center, spacing: 10) {
                    AvatarStack(faces: [state.profile.map { AvatarStack.Face(id: "me", url: $0.image, name: $0.name) },
                                        friend.map { AvatarStack.Face(id: $0.id.uuidString, url: $0.image, name: $0.name) }].compactMap { $0 },
                                size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fri sammen med \(name)").font(Sz.f(12, .semibold))
                        Text(gaps.isEmpty ? "Ingen fælles fritid resten af skoledagen" : gapText(gaps))
                            .font(Sz.f(11, gaps.isEmpty ? .regular : .medium)).monospacedDigit()
                            .foregroundStyle(gaps.isEmpty ? Fomo.text2 : Fomo.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .surface(12)
            }

            if isMe, p.panelBirthdays, !state.birthdaysToday.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("🎂").font(Sz.f(14))
                    Text("Fødselsdag i dag: \(state.birthdaysToday.joined(separator: ", "))")
                        .font(Sz.f(12)).fixedSize(horizontal: false, vertical: true)
                }
            }

            let pack = isMe && p.panelPacking ? MacPackSection.day(now: now) : nil
            if let (d, title) = pack, DateUtil.cal.component(.hour, from: now) < 12 {
                MacPackSection(day: d, title: title)
            }

            if p.panelTimeline, !shown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: name.map { "\($0)s dag" } ?? "Resten af dagen")
                    ForEach(shown) { e in
                        TimelineRow(e: e, now: now, dividerAbove: hasSchool && e.id == firstEvening, tappable: isMe)
                    }
                }
            }

            if let (d, title) = pack, DateUtil.cal.component(.hour, from: now) >= 12 {
                MacPackSection(day: d, title: title)
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
                                    .foregroundStyle(h.done ? Fomo.green : Fomo.text2)
                                    .font(Sz.f(14))
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.bounce, value: h.done)
                            }
                            .buttonStyle(PressScale(scale: 0.8))
                            .help(isMe && p.panelHomeworkTick ? (h.done ? "Markér som ikke færdig" : "Markér som færdig") : "")
                            Text(h.title).font(Sz.f(13)).strikethrough(h.done).foregroundStyle(h.done ? .secondary : .primary).lineLimit(1)
                                .onTapGesture { if isMe { Platform.open(h.link) } }
                            Spacer()
                            Text(DateUtil.day(h.due)).font(Sz.f(11)).monospacedDigit().foregroundStyle(Fomo.text2)
                        }
                        .animation(.viggo, value: h.done)
                    }
                }
            }

            if isMe, p.deadlineRadar, !deadlines.upcoming(now: now).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Deadlines")
                    ForEach(deadlines.upcoming(now: now).prefix(4)) { d in
                        DeadlineRow(d: d, compact: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let t = d.threadID { state.openMessages(thread: t) } else { state.openViggo() }
                            }
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
                        Image(systemName: "list.clipboard.fill").foregroundStyle(Fomo.accent)
                        Text("\(state.questionnaireCount) spørgeskema\(state.questionnaireCount == 1 ? "" : "er") venter på dig").font(Sz.f(12))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, design: Fomo.design)).foregroundStyle(.tertiary)
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
                        .onTapGesture { state.openMessages(thread: m.id) }
                    }
                }
            }
        }
    }
}

// MARK: - Lesson details

#endif

#if os(iOS)
/// Which lesson the iPhone shows as a sheet.
@MainActor final class LessonPresenter: ObservableObject {
    static let shared = LessonPresenter()
    @Published var shown: ViggoEvent?
}
#endif

struct LessonDetailView: View {
    let e: ViggoEvent
    #if os(macOS)
    /// How tall the page is, so the window fits it (up to 640 pt, then it scrolls).
    @State private var height: CGFloat = 420
    #endif

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LessonDetailContent(e: e)
                if e.kind == .lesson || e.kind == .event {
                    MacLessonNotes(e: e).padding(.horizontal, 22).padding(.bottom, 18)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                if abs(h - height) > 0.5 { height = h }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 420, height: min(max(height, 240), 640))
        .background(Fomo.bg.ignoresSafeArea())
        #else
        ScrollView { LessonDetailContent(e: e) }
        #endif
    }
}

/// What the lesson page says, without the scroll view, so the iPhone can measure it before the sheet opens.
struct LessonDetailContent: View {
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
        let tint = e.subjectColor
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.title).font(.system(size: 20, weight: .bold, design: Fomo.design)).fixedSize(horizontal: false, vertical: true)
                    Text("\(DateUtil.longDayF.string(from: e.start).capFirst) · \(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))")
                        .font(.system(size: 12, design: Fomo.design)).foregroundStyle(.secondary)
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
            .font(.system(size: 12, design: Fomo.design)).foregroundStyle(.secondary)

            if e.hasInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text(e.kind == .routine && ["middag", "aftensmad"].contains(where: { e.title.lowercased().hasPrefix($0) }) ? "Dagens mad" : "Info fra læreren").font(.system(size: 11, weight: .semibold, design: Fomo.design)).foregroundStyle(.secondary)
                    Text(e.notes).font(.system(size: 13, design: Fomo.design)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            } else {
                Text("Ingen info fra læreren til denne time.").font(.system(size: 12, design: Fomo.design)).foregroundStyle(.tertiary)
            }

            if !e.links.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Links").font(.system(size: 11, weight: .semibold, design: Fomo.design)).foregroundStyle(.secondary)
                    ForEach(e.links, id: \.self) { u in
                        Link(destination: u) {
                            HStack(spacing: 8) {
                                Image(systemName: linkIcon(u)).frame(width: 16)
                                Text(linkLabel(u)).font(.system(size: 12, weight: .medium, design: Fomo.design))
                                Text(u.path.count > 1 ? u.path : "").font(.system(size: 11, design: Fomo.design)).foregroundStyle(.tertiary).lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 10, design: Fomo.design)).foregroundStyle(.tertiary)
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
        #if os(macOS)
        .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 18)
        #else
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 18)
        #endif
    }
}

// MARK: - Friends right now

#if os(macOS)
// Mac only; the iPhone's I dag has its own friends card.
struct FriendsNow: View {
    @EnvironmentObject var state: AppState
    let now: Date

    private func status(_ f: Friend) -> (String, Bool) { state.friendStatus(f, now: now) }
    private func face(_ f: Friend) -> AvatarStack.Face { .init(id: f.id.uuidString, url: f.image, name: f.name) }

    var body: some View {
        let freeNow = state.friends.filter { !state.friendExpired.contains($0.id) && status($0).1 }
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                SectionHeader(title: "Venner nu")
                Spacer()
                if !freeNow.isEmpty {
                    HStack(spacing: 5) {
                        Text("\(freeNow.count) fri").font(Sz.f(10, .semibold)).monospacedDigit().foregroundStyle(Fomo.green)
                        AvatarStack(faces: freeNow.map(face), size: 16, ring: Fomo.bg)
                    }
                }
            }
            ForEach(state.friends) { f in
                let (text, free) = status(f)
                let expired = state.friendExpired.contains(f.id)
                HStack(spacing: 8) {
                    Avatar(url: f.image, size: 20, name: f.name).opacity(expired ? 0.4 : 1)
                    Text(f.firstName).font(Sz.f(12, .medium))
                    Spacer()
                    Circle().fill(expired ? Fomo.red : free ? Fomo.green : Fomo.text2.opacity(0.5)).frame(width: 6, height: 6)
                    Text(expired ? "Skal logge ind" : text).font(Sz.f(11)).foregroundStyle(Fomo.text2).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.viggo) { state.selectedFriend = f.id } }
            }
            // Only while there is school day left; in the evening it would just say "ingen fælles fritid".
            if state.friends.count >= 2, Prefs.shared.friendsFreeTogether, DateUtil.cal.component(.hour, from: now) < 18 {
                let group = state.freeGroup
                let gaps = state.groupFree(now: now)
                HStack(alignment: .center, spacing: 10) {
                    AvatarStack(faces: group.map(face), size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alle fri: \(group.map(\.firstName).joined(separator: ", "))").font(Sz.f(11, .semibold)).lineLimit(1)
                        Text(gaps.isEmpty ? "Ingen fælles fritid resten af skoledagen" : gapText(gaps))
                            .font(Sz.f(10.5, gaps.isEmpty ? .regular : .medium)).monospacedDigit()
                            .foregroundStyle(gaps.isEmpty ? Fomo.text2 : Fomo.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(state.friends) { f in
                            Toggle(f.name, isOn: Binding(get: { group.contains { $0.id == f.id } },
                                                         set: { _ in state.toggleFreeGroup(f) }))
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help("Vælg hvem der tæller med")
                }
                .padding(9)
                .surface(12)
            }
        }
    }
}

#endif

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
        // When it can't be pressed, the button says what is missing.
        let noUser = user.trimmingCharacters(in: .whitespaces).isEmpty
        Button(noUser ? "Skriv dit brugernavn" : pass.isEmpty ? "Skriv din adgangskode" : button, action: save)
            .buttonStyle(.borderedProminent)
            .disabled(noUser || pass.isEmpty)
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
    private var tint: Color { done ? Fomo.green : failed ? Fomo.warn : Fomo.accent }
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
                    .font(.system(size: 36, weight: .semibold, design: Fomo.design))
                    .foregroundStyle(tint.gradient)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: !done && !failed)
                    .symbolEffect(.bounce, value: done)
                    .symbolEffect(.bounce, value: failed)
            }
            VStack(spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold, design: Fomo.design))
                Text(stage.text)
                    .font(.system(size: 12, design: Fomo.design)).foregroundStyle(.secondary)
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
                    .font(.system(size: 10, design: Fomo.design)).foregroundStyle(.tertiary)
            }
        }
        #if os(macOS)
        .padding(.horizontal, 26).padding(.vertical, 22)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        #else
        // On the iPhone it sits in the middle of the screen, like on the Mac.
        .padding(.horizontal, 26).padding(.top, 28).padding(.bottom, 22)
        .frame(maxWidth: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 8)
        .padding(.horizontal, 24)
        #endif
        .animation(.viggo, value: stage)
        // A tap for every step, and a clear success or error at the end.
        .onChange(of: stage.step) { Haptic.soft() }
        .onChange(of: done) { if done { Haptic.success() } }
        .onChange(of: failed) { if failed { Haptic.error() } }
        .onAppear { Haptic.firm() }
    }
}

/// Dims the settings page and shows the sign-in card on top while a login runs.
struct LoginCardOverlay: ViewModifier {
    @EnvironmentObject var state: AppState
    func body(content: Content) -> some View {
        content.overlay {
            if let st = state.loginStage {
                #if os(macOS)
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                        .onTapGesture { if case .failure = st { state.dismissLoginCard() } }
                    LoginCard(stage: st)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .transition(.opacity)
                #else
                ZStack {
                    Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()
                        .onTapGesture { if case .failure = st { state.dismissLoginCard() } }
                        .transition(.opacity)
                    LoginCard(stage: st)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.keyboard)
                .onAppear {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                #endif
            }
        }
        .animation(.viggo, value: state.loginStage)
    }
}

/// "14:15–14:30 · 16:00–16:15" with word joiners around the dash, so a line never breaks inside a range.
func gapText(_ gaps: [(Date, Date)]) -> String {
    gaps.map { "\(DateUtil.hm($0.0))\u{2060}–\u{2060}\(DateUtil.hm($0.1))" }.joined(separator: " · ")
}
