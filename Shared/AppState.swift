import Foundation
import SwiftUI
import Combine
import Network
import EventKit
import WebKit
#if os(macOS)
import AppKit
import ServiceManagement
#else
import UIKit
#endif

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var events: [ViggoEvent] = [] { didSet { byDay = Dictionary(grouping: events) { DateUtil.startOfDay($0.start) } } }
    /// `events` by the day they start. The whole school year is ~2500 items, and Uge, the panel and
    /// the menubar ask for one day many times per redraw; filtering all of them each time made
    /// switching day in Uge lag by a second.
    private(set) var byDay: [Date: [ViggoEvent]] = [:]

    /// What starts on that day: from the index for your own schedule, filtered for a friend's.
    func onDay(_ d: Date, _ list: [ViggoEvent]? = nil) -> [ViggoEvent] {
        if let list { return list.filter { DateUtil.cal.isDate($0.start, inSameDayAs: d) } }
        return byDay[DateUtil.startOfDay(d)] ?? []
    }
    @Published var homework: [Homework] = []
    @Published var messages: [ViggoMessage] = []
    @Published var lastSync: Date?
    /// No internet (or Viggo can't be reached). Everything shown is from the last sync, and the
    /// app syncs again by itself as soon as the network is back.
    @Published var offline = false
    private let pathMonitor = NWPathMonitor()
    @Published var syncing = false
    /// Finished sync attempts (success or not), so the iPhone launch screen knows when to step aside.
    @Published private(set) var syncAttempts = 0
    @Published var status = ""
    @Published var needsLogin = false
    @Published var loginMessage = ""
    @Published var tick = Date()
    @Published var profile: Profile?
    @Published var friends: [Friend] = []
    @Published var friendEvents: [UUID: [ViggoEvent]] = [:]
    @Published var friendExpired: Set<UUID> = []
    @Published var friendHomework: [UUID: [Homework]] = [:]
    @Published var friendMessage = ""
    @Published var selectedFriend: UUID?
    @Published var unreadCount = 0
    @Published var questionnaireCount = 0
    @Published var bulletins: [Bulletin] = []
    /// Food per day from the kitchen's meal plan posts.
    @Published var meals: [Date: MealDay] = [:]
    #if os(iOS)
    @Published var shownLesson: ViggoEvent?
    /// A thread to open in Beskeder, e.g. from a notification.
    @Published var openThread: Int?
    /// The Søg screen on the iPhone, opened from the magnifier on I dag and Beskeder.
    @Published var showSearch = ProcessInfo.processInfo.environment["VIGGO_SEARCH"] != nil
    #endif
    #if os(macOS)
    private var weekWindow: NSWindow?
    private var messagesWindow: NSWindow?
    private var lessonWindow: NSWindow?
    private var settingsWindow: NSWindow?
    #endif
    private var focusActive: Bool?
    private var focusTimer: Timer?
    private var friendLogin: WebLogin?

    /// Saved passwords are no longer used (SkoleIT/UNI-Login can't take them). Remove any left over.
    private func purgeSavedPasswords() {
        guard !UserDefaults.standard.bool(forKey: "purgedPasswords") else { return }
        if !prefs.username.isEmpty { Keychain.delete(account: prefs.username) }
        for f in friends { Keychain.delete(account: f.keychainAccount) }
        saveFriends()   // rewrites friends.json without the old login fields
        UserDefaults.standard.set(true, forKey: "purgedPasswords")
    }

    let prefs = Prefs.shared
    let client = ViggoClient()
    private let calSync = CalendarSync()
    private var calendarAccess = false
    private var snapshot = Snapshot.load()
    private var lastAttempt = Date.distantPast
    private var lastPing = Date()
    private var timer: Timer?
    private let webLogin = WebLogin()
    private let autoLogin = AutoLogin()
    private var expiryNotified = false
    private var lastAutoLogin = Date.distantPast
    private var lastFriendAutoLogin: [UUID: Date] = [:]
    @Published var friendAutoLoginRunning: Set<UUID> = []
    @Published var autoLoginRunning = false
    /// The sign-in card: where the login is, and whose login it is (nil = yours).
    @Published var loginStage: LoginStage?
    @Published var loginStageName: String?
    /// Logins the app starts by itself (a session ran out). They show as a small badge in a corner
    /// instead of the full sign-in card, so nothing pops up in your face.
    @Published var quietLogins: [QuietLogin] = []
    private var stageClear: Task<Void, Never>?
    private var lastLoginLog: [String] = []

    private init() {
        #if os(macOS)
        if let dir = DocRenderer.outDir {
            Task { @MainActor in await DocRenderer.run(self, dir: dir) }
        } else if CommandLine.arguments.contains("--update-now") {
            // For testing the updater from Terminal: fetch the latest release and install it.
            Task { @MainActor in
                await Updater.shared.check(manual: true)
                if Updater.shared.available != nil { Updater.shared.install() } else { exit(0) }
            }
        } else if CommandLine.arguments.contains("--autologin-dry") {
            // For testing from Terminal: walk the login chain up to the filled-in SkoleIT form, then quit.
            Task { @MainActor in
                let fresh = CommandLine.arguments.contains("--fresh")
                let r = await autoLogin.run(username: "test@cloud.skoleit.dk", password: "x", dryRun: true,
                                            store: fresh ? .nonPersistent() : .default())
                if case .failure(let why) = r { print("[autologin] \(why)") }
                exit(0)
            }
        } else if CommandLine.arguments.contains("--dump-day") {
            // For checking from Terminal: fetch your real schedule and print today's timeline and the menubar text.
            Task { @MainActor in
                CookieJar.restore()
                await sync()
                for e in timeline(Date()) { print("[dag] \(DateUtil.hm(e.start))-\(DateUtil.hm(e.end)) \(e.kind.rawValue) \(e.shortTitle)") }
                if CommandLine.arguments.contains("--far") {
                    await loadFarWeeks()
                    let last = events.filter { $0.kind == .lesson }.map(\.start).max()
                    // What one day switch in Uge costs: 7 strip days, the day itself, duties and birthdays.
                    let t0 = Date()
                    for n in 0..<20 {
                        let d = DateUtil.add(.day, n, DateUtil.startOfDay(Date()))
                        for k in 0..<7 { _ = weekItems(DateUtil.add(.day, k, DateUtil.mondayOf(d)), person: nil) }
                        _ = weekItems(d, person: nil, wholeDay: true); _ = duties(on: d); _ = birthdayNames(on: d)
                    }
                    print("[uge] et dagsskift tager \(Int(Date().timeIntervalSince(t0) * 1000 / 20)) ms")
                    print("[skoleår] \(Config.weeksAhead) uger frem, \(events.count) punkter, sidste time \(last.map(DateUtil.day) ?? "-")")
                }
                if CommandLine.arguments.contains("--bulletin-html") { let c = client
                    for t in [28, 29] {
                        let d = (try? await c.getPublic("/Basic/BulletinBoard/HomeWidget?show=60&userType=\(t)&ajax=1")) ?? Data()
                        try? d.write(to: URL(fileURLWithPath: "/tmp/viggo-board-\(t).html"))
                    }
                    for path in ["/Basic/BulletinBoard/GetOldBulletins/?useTypsId=28", "/Basic/BulletinBoard/GetOldBulletins/?useTypsId=29", "/"] {
                        let d = (try? await c.getPublic(path)) ?? Data()
                        try? d.write(to: URL(fileURLWithPath: "/tmp/viggo-board-\(path.hashValue & 0xffff).html"))
                    }
                }
                // VIGGO_PAGES="/a|/b" VIGGO_OUT=dir saves those pages with your session, for working out new features.
                if let pages = ProcessInfo.processInfo.environment["VIGGO_PAGES"], let out = ProcessInfo.processInfo.environment["VIGGO_OUT"] {
                    for (n, path) in pages.split(separator: "|").enumerated() {
                        let d = (try? await client.getPublic(String(path))) ?? Data("FEJL".utf8)
                        try? d.write(to: URL(fileURLWithPath: out).appendingPathComponent("page\(n).html"))
                    }
                }
                // --messages prints the inbox; VIGGO_THREAD=<id> also opens that thread (it gets marked read).
                if CommandLine.arguments.contains("--messages") {
                    let c = client
                    if let ts = try? await c.fetchThreads() {
                        for t in ts.prefix(8) { print("[tråd] \(t.id) \(t.unread ? "•" : " ") \(t.sender) (+\(t.others)) | \(t.when) | \(t.subject) | \(t.preview.prefix(50)) | \(t.image?.lastPathComponent ?? "-")") }
                    } else { print("[tråd] kunne ikke hente") }
                    if let id = ProcessInfo.processInfo.environment["VIGGO_THREAD"].flatMap(Int.init), let d = try? await c.fetchThread(id) {
                        print("[emne] \(d.subject) fra=\(d.from) til=\(d.to.count) svar-alle=\(d.canReplyAll)")
                        for m in d.messages { print("[besked] \(m.authorID) \(m.author) | \(m.date) | links=\(m.links.count) | filer=\(m.files.map { "\($0.name) \($0.mime) \($0.url.absoluteString)" })\n\(m.text)\n---") }
                    }
                    if let dir = try? await c.fetchDirectory() { print("[folk] \(dir.people.count) personer, \(dir.groups.count) grupper; fx \(dir.people.first.map { "\($0.name) [\($0.info)]" } ?? "-")") }
                }
                // --people "d17" searches the address book like the Søg screen, VIGGO_FIND="text" also searches the inbox.
                if let i = CommandLine.arguments.firstIndex(of: "--people"), i + 1 < CommandLine.arguments.count {
                    let dir = Directory.shared
                    await dir.load(force: true)
                    let q = CommandLine.arguments[i + 1]
                    print("[folk] \(dir.members.count) personer, \(dir.groups.count) grupper, \(dir.relations.count) relationer")
                    for m in dir.search(q).prefix(10) { print("[person] \(m.id) \(m.name) | \(dir.summary(m)) | \(m.age.map { "\($0) år" } ?? "-")") }
                    for g in dir.searchGroups(q).prefix(6) { print("[gruppe] \(g.kind.title): \(g.display) (\(g.members.count))") }
                    if let m = dir.search(q).first {
                        print("[grupper] " + dir.groups(of: m.id).map { "\($0.kind.title): \($0.display)" }.joined(separator: " | "))
                        print("[bor med] " + dir.roommates(of: m).map(\.name).joined(separator: ", "))
                        print("[familie] " + dir.family(of: m.id).map { "\($0.0): \($0.1.name)" }.joined(separator: ", "))
                        print("[kontaktlærer] " + dir.contactTeachers(of: m.id).map(\.name).joined(separator: ", "))
                        print("[kontaktelever] \(dir.contactStudents(of: m.id).count), børn: " + dir.children(of: m.id).map(\.name).joined(separator: ", "))
                        await Premises.shared.load(force: true)
                        let at = CommandLine.arguments.firstIndex(of: "--when").flatMap { i in
                            i + 1 < CommandLine.arguments.count ? ISO8601DateFormatter().date(from: CommandLine.arguments[i + 1]) : nil } ?? Date()
                        let w = Premises.shared.whereNow(m.id, at: at)
                        print("[lokaler] \(Premises.shared.bookings.count) bookinger, \(Premises.shared.schedule(for: m.id).count) til \(m.firstName)")
                        print("[lige nu] \(w.now.map { "\($0.title) i \($0.room) til \(DateUtil.hm($0.end))" } ?? "fri") | næste: \(w.next.map { "\($0.title) \(DateUtil.hm($0.start)) \($0.room)" } ?? "-")")
                        let bd = dir.circle(of: m.id).compactMap { p in p.nextBirthday.map { (p, $0) } }.sorted { $0.1.days < $1.1.days }.prefix(4)
                        print("[fødselsdage] " + bd.map { "\($0.0.firstName) om \($0.1.days) d" }.joined(separator: ", "))
                        if let d = await dir.details(m.id) { print("[profil] \(d.address.joined(separator: ", ")) | " + d.fields.map { "\($0.0)=\($0.1)" }.joined(separator: " | ")) }
                    }
                    if let f = ProcessInfo.processInfo.environment["VIGGO_FIND"], let ts = try? await client.searchThreads(f) {
                        for t in ts.prefix(10) { print("[fundet] \(t.id) \(t.sender) | \(t.when) | \(t.subject)") }
                    }
                }
                // --receipts: who has seen your last message in the newest read threads. With --forget it
                // forgets the readers first, so the next check says "X har set din besked" (a local notification).
                if CommandLine.arguments.contains("--receipts") {
                    let inbox = Inbox.shared
                    await inbox.load()
                    await inbox.prefetch()
                    for t in inbox.threads.prefix(12) {
                        if let r = inbox.receipt(t.id) { print("[set] \(t.id) \(t.subject) | \(r.readers.map(\.name)) af \(r.total)") }
                    }
                    if CommandLine.arguments.contains("--forget") { Receipts.forgetReaders() }
                    print("[set] holder øje med \(Receipts.watched())")
                    await inbox.checkReceipts()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                // --deadlines prints what the Deadline-radar finds in posts, previews and read threads.
                if CommandLine.arguments.contains("--deadlines") {
                    await Inbox.shared.load()
                    for t in Inbox.shared.threads.prefix(12) where !t.unread && Inbox.shared.details[t.id] == nil {
                        if let d = try? await client.fetchThread(t.id) { Deadlines.shared.scan(d) }
                    }
                    let now = Date()
                    var found: [Deadline] = []
                    for b in bulletins { found += Deadlines.find(in: b.body, subject: b.title, posted: Deadlines.postedDate(b.when) ?? now, source: "opslag", from: b.author, now: .distantPast) }
                    for t in Inbox.shared.threads {
                        if let d = Inbox.shared.details[t.id] { found += Deadlines.find(in: d, now: .distantPast) }
                        else { found += Deadlines.find(in: t.preview, subject: t.subject, posted: Deadlines.postedDate(t.when) ?? now, source: "tråd:\(t.id)•", from: t.sender, now: .distantPast) }
                    }
                    for d in found.sorted(by: { $0.due > $1.due }) {
                        print("[deadline] \(d.end > now ? "kommer" : "forbi ") \(d.whenText(now: now)) | \(d.title) | \(d.from) | \(d.source) | \(d.snippet)")
                    }
                    Deadlines.shared.scanAll()
                    for d in Deadlines.shared.upcoming() { print("[liste] \(d.whenText()) | \(d.title)") }
                    for r in Deadlines.shared.reminders() { print("[påmind] \(r.at.formatted(date: .abbreviated, time: .shortened)) | \(r.title) | \(r.body)") }
                }
                if CommandLine.arguments.contains("--meals") {
                    for (d, m) in meals.sorted(by: { $0.key < $1.key }) { print("[mad] \(DateUtil.day(d)): \(m.lunch) | aften: \(m.dinner ?? "-")") }
                }
                if CommandLine.arguments.contains("--bulletins") {
                    for b in bulletins { print("[opslag] \(b.board) | \(b.title) | \(b.when) | img=\(b.images) | av=\(b.authorImage?.absoluteString ?? "-") | links=\(b.links.count)\n\(b.body)\n---") }
                }
                if CommandLine.arguments.contains("--raw") {
                    for e in events.filter({ $0.kind == .routine }).sorted(by: { $0.start < $1.start }) {
                        print("[rå] \(DateUtil.day(e.start)) \(DateUtil.hm(e.start))-\(DateUtil.hm(e.end)) \(e.rawName)")
                    }
                }
                for h in homework where !h.done { print("[lektie] \(DateUtil.day(h.day)) \(h.group) \(h.title)") }
                for n in 0..<14 {
                    let d = DateUtil.add(.day, n, Date())
                    if let r = homeworkReminder(for: d) { print("[påmindelse] \(DateUtil.day(d)) kl. \(prefs.homeworkReminderAt / 60): \(r.0) | \(r.1.replacingOccurrences(of: "\n", with: " / "))") }
                }
                // --week-check prints, for each day this week and next, what Viggo has and the week view leaves out.
                if CommandLine.arguments.contains("--week-check") {
                    let mon = DateUtil.mondayOf(Date())
                    for n in 0..<14 {
                        let d = DateUtil.add(.day, n, mon)
                        let raw = events.filter { DateUtil.cal.isDate($0.start, inSameDayAs: d) }
                        let shown = Set(weekItems(d, person: nil, wholeDay: true).map(\.key))
                        let missing = raw.filter { !shown.contains($0.key) }
                        print("[uge] \(DateUtil.day(d)): viggo \(raw.count), vist \(shown.count), mangler \(missing.count)")
                        for e in missing { print("[mangler]   \(e.kind.rawValue) \(DateUtil.hm(e.start))-\(DateUtil.hm(e.end)) \(e.rawName.prefix(60))") }
                    }
                }
                print("[menubar] \(menuTitle)")
                // --at 09:40 prints the menubar text at that time today.
                if let i = CommandLine.arguments.firstIndex(of: "--at"), i + 1 < CommandLine.arguments.count {
                    let hm = CommandLine.arguments[i + 1].split(separator: ":").compactMap { Int($0) }
                    if hm.count == 2, let t = DateUtil.cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: Date()) {
                        tick = t
                        print("[menubar \(CommandLine.arguments[i + 1])] \(menuTitle)")
                    }
                }
                exit(0)
            }
        } else if CommandLine.arguments.contains("--unfold-test") {
            // For checking the fold-out animation: open the panel, fold out the first note and take pictures meanwhile.
            Task { @MainActor in
                setvbuf(stdout, nil, _IONBF, 0)
                CookieJar.restore()
                await sync()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                PanelController.shared.show()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let e = timeline(Date()).first(where: { $0.hasInfo }), let f = PanelController.shared.frame,
                      let dir = ProcessInfo.processInfo.environment["VIGGO_SHOTS"] else { print("[fold] intet at folde ud"); exit(1) }
                let top = (NSScreen.main?.frame.maxY ?? 0) - f.maxY
                let r = "-R\(Int(f.minX) - 10),\(Int(top) - 10),\(Int(f.width) + 20),\(Int(f.height) + 260)"
                let sh = Process()
                sh.executableURL = URL(fileURLWithPath: "/bin/sh")
                sh.arguments = ["-c", "for i in 0 1 2 3 4 5 6 7 8; do /usr/sbin/screencapture -x \(r) \(dir)/f$i.png; done"]
                try? sh.run()
                try? await Task.sleep(nanoseconds: 120_000_000)
                print("[fold] folder \(e.shortTitle) ud")
                NotificationCenter.default.post(name: .viggoToggleNote, object: e.id)
                sh.waitUntilExit()
                print("[fold] kort efter: \(PanelController.shared.cardSize)")
                exit(0)
            }
        } else if CommandLine.arguments.contains("--window-test") {
            // For checking from Terminal: open the panel, then Indstillinger and a lesson, and print where things end up.
            Task { @MainActor in
                setvbuf(stdout, nil, _IONBF, 0)
                setupHotKey()
                CookieJar.restore()
                await sync()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                HotKey.shared.action?()          // same as pressing the hotkey
                try? await Task.sleep(nanoseconds: 800_000_000)
                print("[vindue] genvejstast åbnede panelet: \(PanelController.shared.frame.map { "\($0)" } ?? "nej")")
                if let out = ProcessInfo.processInfo.environment["VIGGO_PANEL_SHOT"], let f = PanelController.shared.frame {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    let top = (NSScreen.main?.frame.maxY ?? 0) - f.maxY
                    p.arguments = ["-x", "-R\(Int(f.minX) - 20),\(Int(top) - 30),\(Int(f.width) + 40),\(Int(f.height) + 50)", out]
                    try? p.run(); p.waitUntilExit()
                }
                HotKey.shared.action?()
                try? await Task.sleep(nanoseconds: 500_000_000)
                print("[vindue] genvejstast igen lukkede det: \(!PanelController.shared.isShown)")
                PanelController.shared.show()
                try? await Task.sleep(nanoseconds: 800_000_000)
                openSettings()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                print("[vindue] efter indstillinger, panel åbent: \(PanelController.shared.isShown), indstillinger: \(settingsWindow?.frame ?? .zero)")
                settingsWindow?.close()
                PanelController.shared.show()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let e = events.first(where: { $0.kind == .lesson }) { openLesson(e) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                print("[vindue] efter detaljer, panel åbent: \(PanelController.shared.isShown), detaljer: \(lessonWindow?.frame ?? .zero)")
                exit(0)
            }
        } else if CommandLine.arguments.contains("--deadline-parse-test") {
            // Made-up sentences through the Danish deadline reader, written on Tue 10 Nov 2026 12:00.
            let posted = DateUtil.cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
            let cases = [
                "Husk deadline her kl. 13.00. Hilsen Jan",
                "Afleveringen skal afleveres senest fredag kl. 23.59",
                "Tilmelding til turen senest d. 20/11",
                "Frist for betaling er 3. december",
                "Husk at aflevere jeres rapport i morgen inden kl 8",
                "Deadline 15/1 for projektet",
                "Vi ses til timen kl. 10.15 i lokale 4",
                "Blå nætter 15.15 Sunday morning 15.30",
                "Sidste frist for framelding er næste tirsdag",
                "Husk deadline for tilmelding/framelding til weekenden er i dag kl. 13.00",
                "Opgaven skal uploades til Lectio den 24.11 kl. 12:00",
            ]
            for c in cases {
                let f = Deadlines.find(in: c, subject: "Svar", posted: posted, source: "test", from: "", now: posted, readSubject: false)
                print("[parse] \(c)\n   → \(f.map { "\($0.whenText(now: posted)) | \($0.title)" }.joined(separator: " ; ").ifEmpty("ingen"))")
            }
            exit(0)
        } else if CommandLine.arguments.contains("--quiet-login-test") {
            // Runs the automatic login the app does when a session runs out (a friend's if one has a saved
            // login, else your own) and prints what the corner badge shows at each step.
            Task { @MainActor in
                CookieJar.restore()
                var seen: [String] = []
                let watch = $quietLogins.sink { list in
                    for q in list { let t = "\(q.title) · \(q.detail)"; if seen.last != t { seen.append(t); print("[badge] \(t)") } }
                }
                print("[kort] loginStage før: \(String(describing: loginStage))")
                let ok: Bool
                if let f = friends.first(where: { FriendLogin.has($0.id) }) {
                    print("[ven] \(f.firstName)")
                    ok = await tryFriendAutoLogin(f)
                } else {
                    print("[ven] ingen med gemt login, bruger dit eget")
                    ok = await tryAutoLogin()
                }
                print("[resultat] \(ok ? "logget ind" : "fejlede"), kortet blev vist: \(loginStage != nil)")
                try? await Task.sleep(for: .seconds(3))
                print("[badge] tilbage efter 3 s: \(quietLogins.count)")
                watch.cancel()
                exit(ok ? 0 : 1)
            }
        } else if CommandLine.arguments.contains("--friend-autologin-test") {
            // For testing the friend path from Terminal with your own saved login: Keychain round trip,
            // a login in a private store like a friend's, and a Viggo request with those cookies. Adds no friend.
            Task { @MainActor in
                let id = UUID()
                FriendLogin.save(id, username: "test1234", password: "a\nb")
                let back = FriendLogin.get(id)
                FriendLogin.remove(id)
                print("[autologin] lagring: \(back?.user == "test1234@cloud.skoleit.dk" && back?.pass == "a\nb" && !FriendLogin.has(id) ? "ok" : "FEJL")")
                guard let u = SkoleITLogin.username, let p = SkoleITLogin.password else { print("[autologin] intet login gemt"); exit(1) }
                let login = AutoLogin()
                let r = await login.run(username: u, password: p, store: .nonPersistent())
                print(login.log.joined(separator: " > "))
                if case .success(let cookies) = r, let prof = try? await ViggoClient(cookies: cookies).fetchProfile() {
                    print("[autologin] privat session virker: \(prof.name)")
                } else { print("[autologin] privat session virker ikke") }
                exit(0)
            }
        } else if CommandLine.arguments.contains("--autologin-test") {
            // For testing from Terminal with the saved login: log in for real, print the result, then quit.
            Task { @MainActor in
                print(await tryAutoLogin(force: true) ? "[autologin] logget ind" : "[autologin] \(loginMessage)")
                print(lastLoginLog.joined(separator: " > "))
                exit(0)
            }
        } else {
            Task { await start() }
        }
        #else
        Task { await start() }
        #endif
    }

    // MARK: lifecycle

    /// The last schedule, homework and messages, so the app shows them at once and syncs meanwhile.
    /// Everything needed to use the app without internet. The newer fields are optional so an
    /// older cache still loads.
    private struct Cache: Codable {
        var events: [ViggoEvent]; var homework: [Homework]; var messages: [ViggoMessage]
        var profile: Profile?; var friendEvents: [UUID: [ViggoEvent]]
        var friendHomework: [UUID: [Homework]]?
        var bulletins: [Bulletin]?; var meals: [Date: MealDay]?
        var lastSync: Date?; var unread: Int?; var questionnaires: Int?
    }
    private var cacheURL: URL { CookieJar.dir.appendingPathComponent("cache.json") }

    private func loadCache() {
        guard events.isEmpty, let c = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL)) else { return }
        events = c.events
        homework = c.homework
        messages = c.messages
        if profile == nil { profile = c.profile }
        for (k, v) in c.friendEvents where friendEvents[k] == nil { friendEvents[k] = v }
        for (k, v) in c.friendHomework ?? [:] where friendHomework[k] == nil { friendHomework[k] = v }
        bulletins = c.bulletins ?? []
        meals = c.meals ?? [:]
        lastSync = c.lastSync
        unreadCount = c.unread ?? 0
        questionnaireCount = c.questionnaires ?? 0
    }

    private var cacheWrite: Task<Void, Never>?

    /// The whole school year is a few thousand items, so it is encoded and written off the main
    /// thread, one write after the other so an older copy never lands on top of a newer one.
    private func saveCache() {
        let c = Cache(events: events, homework: homework, messages: messages, profile: profile, friendEvents: friendEvents,
                      friendHomework: friendHomework, bulletins: bulletins, meals: meals,
                      lastSync: lastSync, unread: unreadCount, questionnaires: questionnaireCount)
        let url = cacheURL, before = cacheWrite
        cacheWrite = Task.detached(priority: .utility) {
            await before?.value
            guard !Task.isCancelled else { return }
            try? JSONEncoder().encode(c).write(to: url, options: .atomic)
        }
    }

    func start() async {
        Notifier.shared.setup()
        try? FileManager.default.removeItem(at: CookieJar.dir.appendingPathComponent("login.log"))
        CookieJar.restore()
        loadFriends()
        loadCache()
        watchNetwork()
        #if os(iOS)
        importTransfer()          // a login sent from the Mac app, if there is one
        #endif
        purgeSavedPasswords()
        calendarAccess = await calSync.requestAccess()
        if calendarAccess, !prefs.imported, !UserDefaults.standard.bool(forKey: "cleanedAutoImport") {
            for name in Config.allCalendars { try? calSync.remove(named: name) }
            UserDefaults.standard.set(true, forKey: "cleanedAutoImport")
        }
        #if os(macOS)
        setupHotKey()
        #endif
        await sync()
        #if os(macOS)
        if needsLogin { openSettings() }
        Updater.shared.checkIfDue()
        #endif
        // On the minute (plus a moment), so the menubar and the countdown change when the clock does
        // instead of up to 59 seconds late.
        let next = DateUtil.cal.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? Date()
        let t = Timer(fire: next.addingTimeInterval(0.3), interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        #if os(macOS)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.keepAlive(); await self?.sync() }
        }
        #endif
    }

    private func onTick() {
        tick = Date()
        updateFocus()
        if Date().timeIntervalSince(lastAttempt) >= Config.pollInterval {
            Task { await sync() }
        } else if Date().timeIntervalSince(lastPing) >= 4 * 60 {
            lastPing = Date()
            Task { await keepAlive() }
        }
        checkBriefs()
        #if os(macOS)
        Deadlines.shared.tick()
        Updater.shared.checkIfDue()
        #else
        updateLiveActivity()
        #endif
    }

    /// Pings Viggo every few minutes so sessions stay alive as long as possible.
    func keepAlive() async {
        lastPing = Date()
        do { try await client.ping() } catch ViggoError.notLoggedIn {
            if await tryAutoLogin() { await sync() } else { sessionExpired() }
        } catch {}
        for f in friends where f.needsLogin && !friendExpired.contains(f.id) {
            let c = ViggoClient(cookies: CookieJar.read(CookieJar.friendURL(f.id)))
            do {
                try await c.ping()
                CookieJar.write(c.cookies, to: CookieJar.friendURL(f.id))
            } catch ViggoError.notLoggedIn {
                await friendSessionExpired(f)
            } catch {}
        }
    }

    /// Your own session ran out: one notification, and the menubar shows a log-in button.
    private func sessionExpired() {
        needsLogin = true
        #if os(iOS)
        pushWidget()
        #endif
        guard !expiryNotified, snapshot.initialized else { return }
        expiryNotified = true
        Notifier.shared.post("Viggo+: log ind igen", "Din Viggo-session er udløbet. Klik for at logge ind.",
                             url: URL(string: "viggoplus://login"))
    }

    /// A friend's session ran out: log them in again with their saved SkoleIT login, or ask them to.
    private func friendSessionExpired(_ f: Friend) async {
        guard !friendExpired.contains(f.id) else { return }
        if await tryFriendAutoLogin(f) { return }
        friendExpired.insert(f.id)
        Notifier.shared.post("Viggo+: \(f.firstName) skal logge ind igen", "Klik for at åbne login for \(f.firstName).",
                             url: URL(string: "viggoplus://friend/\(f.id.uuidString)"))
    }

    /// Handles clicks on "log ind igen" notifications.
    func handle(_ url: URL) {
        guard url.scheme == "viggoplus" else { Platform.open(url); return }
        if url.host == "login" { loginWithBrowser() }
        if url.host == "thread", let id = Int(url.lastPathComponent) {
            #if os(iOS)
            openThread = id
            #else
            openMessages(thread: id)
            #endif
        }
        if url.host == "friend", let id = UUID(uuidString: url.lastPathComponent),
           let f = friends.first(where: { $0.id == id }) { addFriend(relogin: f) }
    }

    // MARK: login

    func loginWithBrowser() {
        loginMessage = "Log ind i vinduet…"
        webLogin.onClose = { [weak self] in
            if self?.loginMessage == "Log ind i vinduet…" { self?.loginMessage = "" }
        }
        webLogin.show { [weak self] cookies in
            guard let self else { return }
            cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
            CookieJar.save()
            self.needsLogin = false
            self.expiryNotified = false
            self.loginMessage = "Logget ind via Viggo ✓"
            Task { await self.sync() }
        }
    }

    /// Logs in by itself with the saved SkoleIT login. At most once every 10 minutes unless forced,
    /// so a wrong password never hammers SkoleIT.
    @discardableResult
    func tryAutoLogin(force: Bool = false, saving: Bool = false) async -> Bool {
        guard SkoleITLogin.isSet, let user = SkoleITLogin.username, let pass = SkoleITLogin.password,
              !autoLoginRunning, force || Date().timeIntervalSince(lastAutoLogin) > 10 * 60 else { return false }
        lastAutoLogin = Date()
        autoLoginRunning = true
        defer { autoLoginRunning = false }
        loginMessage = "Logger ind automatisk…"
        let quiet = force || saving ? nil : QuietLogin(id: QuietLogin.me, name: profile?.name.components(separatedBy: " ").first ?? "dig", image: profile?.image)
        switch await runWithCard(user, pass, name: nil, saving: saving, quiet: quiet) {
        case .success(let cookies):
            cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
            CookieJar.save()
            needsLogin = false
            expiryNotified = false
            loginMessage = "Logget ind automatisk ✓"
            return true
        case .failure(let why):
            loginMessage = "Automatisk login fejlede: \(why)"
            return false
        }
    }

    /// Saves the SkoleIT login and tries it right away.
    func saveAutoLogin(username: String, password: String) async {
        SkoleITLogin.save(username: username, password: password)
        if await tryAutoLogin(force: true, saving: true) { await sync() }
    }

    /// Runs a login and drives the sign-in card while it goes.
    private func runWithCard(_ user: String, _ pass: String, name: String?, store: WKWebsiteDataStore? = nil,
                             saving: Bool = false, quiet: QuietLogin? = nil) async -> AutoLoginResult {
        if let quiet { return await runQuietly(user, pass, store: store, badge: quiet) }
        stageClear?.cancel()
        loginStageName = name
        if saving {
            loginStage = .saving
            try? await Task.sleep(for: .milliseconds(700))
        }
        let login = AutoLogin()
        login.onStage = { [weak self] st in self?.loginStage = st }
        let r = await login.run(username: user, password: pass, store: store)
        lastLoginLog = login.log
        if case .success = r { loginStage = .success }
        stageClear = Task { [weak self] in
            let ok: Bool = { if case .success = r { return true } else { return false } }()
            try? await Task.sleep(for: .seconds(ok ? 1.6 : 4))
            guard !Task.isCancelled else { return }
            self?.loginStage = nil
        }
        return r
    }

    func dismissLoginCard() { stageClear?.cancel(); loginStage = nil }

    /// Same login, but only the corner badge follows it.
    private func runQuietly(_ user: String, _ pass: String, store: WKWebsiteDataStore?, badge: QuietLogin) async -> AutoLoginResult {
        quietLogins.removeAll { $0.id == badge.id }
        quietLogins.append(badge)
        func set(_ st: LoginStage) {
            if let i = quietLogins.firstIndex(where: { $0.id == badge.id }) { quietLogins[i].stage = st }
        }
        let login = AutoLogin()
        login.onStage = { st in set(st) }
        let r = await login.run(username: user, password: pass, store: store)
        lastLoginLog = login.log
        let ok: Bool
        switch r {
        case .success: set(.success); ok = true
        case .failure(let why): set(.failure(why)); ok = false
        }
        // A success fades after a moment. A failure stays a while so you can tap it to log in by hand.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ok ? 2.2 : 12))
            self?.quietLogins.removeAll { $0.id == badge.id && $0.stage == (ok ? .success : $0.stage) }
        }
        return r
    }

    /// VIGGO_QUIET_DEMO=1: plays the corner badge for your friends without logging anyone in, for screenshots.
    func quietDemo() async {
        let people = friends.prefix(2).map { QuietLogin(id: $0.id, name: $0.firstName, image: $0.image) }
        for q in people { quietLogins.append(q) }
        for st in [LoginStage.unilogin, .skoleit, .verifying] {
            try? await Task.sleep(for: .seconds(2.5))
            for i in quietLogins.indices { quietLogins[i].stage = st }
        }
        try? await Task.sleep(for: .seconds(2.5))
        if quietLogins.count > 0 { quietLogins[0].stage = .success }
        if quietLogins.count > 1 { quietLogins[1].stage = .failure("Forkert kodeord") }
    }

    /// Tapping a failed badge: open the normal login for that person.
    func openQuietLogin(_ q: QuietLogin) {
        quietLogins.removeAll { $0.id == q.id }
        if q.id == QuietLogin.me { loginWithBrowser() }
        else if let f = friends.first(where: { $0.id == q.id }) { addFriend(relogin: f) }
    }

    func removeAutoLogin() {
        SkoleITLogin.clear()
        loginMessage = "Automatisk login er slået fra"
    }

    func logout() {
        // Logging out also forgets the saved SkoleIT login, or the app would log straight back in.
        SkoleITLogin.clear()
        // Every cookie in the login chain (Viggo, UNI-Login, SkoleIT), so the next login can be someone else.
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        events = []; homework = []; messages = []; unreadCount = 0; questionnaireCount = 0
        bulletins = []; meals = [:]; farEvents = []; farLoaded = nil
        CookieJar.clear()
        cacheWrite?.cancel()
        let pending = cacheWrite, url = cacheURL
        cacheWrite = Task.detached { await pending?.value; try? FileManager.default.removeItem(at: url) }
        // Messages, deadlines and the "what did I last see" list belong to the account too. Without
        // this the next person saw the old inbox, and got "Aflyst" for every lesson of the last one.
        Inbox.shared.clear()
        Deadlines.shared.clear()
        snapshot = Snapshot()
        snapshot.save()
        webLogin.clearCookies()
        profile = nil
        lastSync = nil
        needsLogin = true
        loginMessage = "Logget ud"
        #if os(iOS)
        pushWidget()
        #endif
    }

    private func withRelogin<T>(_ op: () async throws -> T) async throws -> T {
        // sync() tries the saved SkoleIT login before it tells you the session ran out.
        try await op()
    }

    // MARK: sync

    func sync() async {
        guard !syncing else { return }
        syncing = true
        lastAttempt = Date()
        defer { syncing = false; syncAttempts += 1 }
        do {
            let c = client
            let (ev, hw, msg) = try await withRelogin { () async throws -> ([ViggoEvent], [Homework], [ViggoMessage]) in
                async let ev = c.fetchEvents(), hw = c.fetchHomework(), msg = c.fetchMessages()
                return (try await ev, try await hw, try await msg)
            }
            events = withFarWeeks(ev)
            homework = hw
            // For testing reminders: VIGGO_FAKE_HOMEWORK=1 adds two made-up homework items for tomorrow.
            if ProcessInfo.processInfo.environment["VIGGO_FAKE_HOMEWORK"] != nil {
                let t = DateUtil.add(.day, 1, DateUtil.startOfDay(Date()))
                homework += [Homework(id: -1, title: "Læs kapitel 3", group: "Engelsk", day: t, start: nil, end: nil, notes: "", author: "", done: false),
                             Homework(id: -2, title: "Opgave 4.1", group: "Matematik", day: t, start: nil, end: nil, notes: "", author: "", done: false)]
            }
            messages = msg
            if let p = c.profile { profile = p }
            async let counts = try? c.fetchCounts()
            async let posts = try? c.fetchBulletins()
            async let mealPosts = try? c.fetchMealPosts()
            if let n = await counts { unreadCount = n.unread; questionnaireCount = n.questionnaires }
            if let b = await posts { bulletins = b }
            if let m = await mealPosts { meals = MealPlan.parse(m) }
            needsLogin = false
            if prefs.imported { applyCalendar() }
            // The address book and the room overview load behind the scenes after the schedule is shown.
            Task {
                async let people: Void = Directory.shared.load()
                async let rooms: Void = Premises.shared.load()
                async let far: Void = loadFarWeeks()
                // Previews for the Deadline-radar, then who has seen your messages.
                async let inbox: Void = Inbox.shared.refresh()
                _ = await (people, rooms, far, inbox)
                await syncFriends()
                saveCache()
            }
            detectChanges()
            Deadlines.shared.scanAll()
            lastSync = Date()
            saveCache()
            #if os(iOS)
            pushWidget()
            scheduleAhead()
            scheduleRefresh()
            #endif
            CookieJar.save()
            offline = false
            if !status.hasPrefix("Kalender") { status = "" }
        } catch ViggoError.notLoggedIn {
            // Try the saved SkoleIT login first. Otherwise the log-in banner in the panel says so.
            if await tryAutoLogin() { syncing = false; await sync() } else { sessionExpired() }
        } catch where Self.isOffline(error) {
            // Keep showing the last sync; the offline banner says so instead of a raw error.
            offline = true
            if !status.hasPrefix("Kalender") { status = "" }
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: offline

    /// Errors that mean "no connection", not "Viggo said no".
    nonisolated static func isOffline(_ error: Error) -> Bool {
        guard let u = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed, .secureConnectionFailed].contains(u.code)
    }

    /// Syncs the moment the network comes back, and marks offline at once when it goes.
    private func watchNetwork() {
        pathMonitor.pathUpdateHandler = { path in
            Task { @MainActor in
                let up = path.status == .satisfied
                if !up { self.offline = true }
                else if self.offline { await self.sync() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "viggo.network"))
    }

    /// "Synket kl. 14.02", "Synket i går kl. 14.02", "Synket 12. nov kl. 14.02".
    var syncedText: String? {
        guard let s = lastSync else { return nil }
        let day = DateUtil.cal.isDateInToday(s) ? "" : DateUtil.cal.isDateInYesterday(s) ? "i går " : "\(DateUtil.day(s)) "
        return "Synket \(day)kl. \(DateUtil.hm(s))"
    }

    // MARK: the rest of the school year

    private var farEvents: [ViggoEvent] = []
    private var farLoaded: Date?
    private var nearEnd: Date { DateUtil.add(.weekOfYear, Config.nearWeeks + 1, DateUtil.mondayOf(Date())) }

    /// The near weeks from this refresh plus the later weeks from the last background fetch (or the
    /// cache, right after launch).
    private func withFarWeeks(_ near: [ViggoEvent]) -> [ViggoEvent] {
        let end = nearEnd
        let far = farEvents.isEmpty ? events.filter { $0.start >= end } : farEvents
        return near.filter { $0.start < end } + far
    }

    /// Weeks after the near ones, to the end of the school year. At most once an hour.
    func loadFarWeeks() async {
        guard Config.weeksAhead > Config.nearWeeks else { return }
        if let t = farLoaded, Date().timeIntervalSince(t) < 3600 { return }
        guard let far = try? await client.fetchEvents(weeks: (Config.nearWeeks + 1)...Config.weeksAhead) else { return }
        farLoaded = Date()
        farEvents = far
        let end = nearEnd
        events = events.filter { $0.start < end } + far
    }

    // MARK: friends

    private var friendsURL: URL { CookieJar.dir.appendingPathComponent("friends.json") }

    private func loadFriends() {
        friends = (try? JSONDecoder().decode([Friend].self, from: Data(contentsOf: friendsURL))) ?? []
    }

    private func saveFriends() {
        try? JSONEncoder().encode(friends).write(to: friendsURL, options: .atomic)
    }

    /// The friend logs in themselves in a private window that never sees your own session.
    func addFriend(relogin existing: Friend? = nil) {
        let login = WebLogin()
        friendLogin = login
        login.onClose = { [weak self] in
            if self?.friendMessage.hasPrefix("Lad ") == true { self?.friendMessage = "" }
            self?.friendLogin = nil
        }
        friendMessage = existing == nil ? "Lad din ven logge ind i vinduet…" : "Lad \(existing!.firstName) logge ind igen…"
        login.show(store: .nonPersistent(), title: existing.map { "\($0.firstName): log ind på Viggo" } ?? "Ven: log ind på Viggo") { [weak self] cookies in
            Task { await self?.finishFriend(cookies: cookies) }
        }
    }

    @discardableResult
    private func finishFriend(cookies: [HTTPCookie], client given: ViggoClient? = nil) async -> Friend? {
        friendLogin = nil
        let client = given ?? ViggoClient(cookies: cookies)
        do {
            let prof = try await client.fetchProfile()
            if prof.id == profile?.id { friendMessage = "Det er din egen konto 🙂"; return nil }
            var f = friends.first { $0.viggoID == prof.id } ?? Friend(id: UUID(), viggoID: prof.id, name: prof.name, image: prof.image)
            f.name = prof.name
            f.image = prof.image
            if let i = friends.firstIndex(where: { $0.id == f.id }) { friends[i] = f } else { friends.append(f) }
            saveFriends()
            friendEvents[f.id] = try await client.fetchEvents(weeksBack: 0, weeksAhead: 1)
            friendHomework[f.id] = (try? await client.fetchHomework()) ?? []
            CookieJar.write(client.cookies, to: CookieJar.friendURL(f.id))
            friendExpired.remove(f.id)
            friendMessage = "\(f.firstName) er tilføjet ✓"
            return f
        } catch {
            friendMessage = "Kunne ikke tilføje: \(error.localizedDescription)"
            return nil
        }
    }

    /// Logs a friend in by themselves with their saved SkoleIT login, in a private browser store
    /// that never sees your own session. At most once every 10 minutes unless forced.
    @discardableResult
    func tryFriendAutoLogin(_ f: Friend, force: Bool = false, saving: Bool = false) async -> Bool {
        guard let login = FriendLogin.get(f.id), !friendAutoLoginRunning.contains(f.id),
              force || Date().timeIntervalSince(lastFriendAutoLogin[f.id] ?? .distantPast) > 10 * 60 else { return false }
        lastFriendAutoLogin[f.id] = Date()
        friendAutoLoginRunning.insert(f.id)
        defer { friendAutoLoginRunning.remove(f.id) }
        friendMessage = "Logger \(f.firstName) ind automatisk…"
        let quiet = force || saving ? nil : QuietLogin(id: f.id, name: f.firstName, image: f.image)
        switch await runWithCard(login.user, login.pass, name: f.firstName, store: .nonPersistent(), saving: saving, quiet: quiet) {
        case .success(let cookies):
            guard let got = await finishFriend(cookies: cookies), got.id == f.id else {
                friendMessage = "Automatisk login for \(f.firstName) gav en anden konto"
                return false
            }
            friendMessage = "\(f.firstName) er logget ind automatisk ✓"
            return true
        case .failure(let why):
            friendMessage = "Automatisk login for \(f.firstName) fejlede: \(why)"
            return false
        }
    }

    /// Saves a friend's SkoleIT login and tries it right away.
    func saveFriendAutoLogin(_ f: Friend, username: String, password: String) async {
        FriendLogin.save(f.id, username: username, password: password)
        await tryFriendAutoLogin(f, force: true, saving: true)
    }

    /// Adds a new friend straight from their SkoleIT login, without the login window.
    func addFriendWithSkoleIT(username: String, password: String) async {
        friendMessage = "Logger ind med SkoleIT…"
        switch await runWithCard(username, password, name: "din ven", store: .nonPersistent(), saving: true) {
        case .success(let cookies):
            if let f = await finishFriend(cookies: cookies) {
                FriendLogin.save(f.id, username: username, password: password)
                friendMessage = "\(f.firstName) er tilføjet med automatisk login ✓"
            }
        case .failure(let why):
            friendMessage = "Kunne ikke logge ind: \(why)"
        }
    }

    /// Adds someone from the address book. Needs no login: their lessons come from Viggo's room overview.
    func addFriend(member m: Member) async {
        guard m.id != profile?.id else { friendMessage = "Det er dig selv 🙂"; return }
        if friends.contains(where: { $0.viggoID == m.id }) { friendMessage = "\(m.firstName) er allerede din ven"; return }
        let f = Friend(id: UUID(), viggoID: m.id, name: m.name, image: m.image, noLogin: true)
        friends.append(f)
        saveFriends()
        await Premises.shared.load()
        friendEvents[f.id] = Premises.shared.schedule(for: m.id)
        friendHomework[f.id] = []
        friendMessage = "\(m.firstName) er tilføjet ✓"
        saveCache()
    }

    func isFriend(_ viggoID: Int) -> Bool { friends.contains { $0.viggoID == viggoID } }

    func removeFriendAutoLogin(_ f: Friend) {
        FriendLogin.remove(f.id)
        friendMessage = "Automatisk login for \(f.firstName) er slået fra"
    }

    func removeFriend(_ f: Friend) {
        FriendLogin.remove(f.id)
        friends.removeAll { $0.id == f.id }
        friendEvents[f.id] = nil
        friendHomework[f.id] = nil
        friendExpired.remove(f.id)
        if selectedFriend == f.id { selectedFriend = nil }
        try? FileManager.default.removeItem(at: CookieJar.friendURL(f.id))
        saveFriends()
    }

    func syncFriends() async {
        if friends.contains(where: { !$0.needsLogin }) { await Premises.shared.load() }
        for f in friends where !f.needsLogin {
            let list = Premises.shared.schedule(for: f.viggoID)
            if !list.isEmpty || friendEvents[f.id] == nil { friendEvents[f.id] = list }
        }
        // Friends with their own login, all at the same time.
        await withTaskGroup(of: Void.self) { group in
            for f in friends where f.needsLogin && !friendExpired.contains(f.id) {
                group.addTask { @MainActor in
                    let c = ViggoClient(cookies: CookieJar.read(CookieJar.friendURL(f.id)))
                    do {
                        async let ev = c.fetchEvents(weeksBack: 0, weeksAhead: 1)
                        async let hw = try? c.fetchHomework()
                        self.friendEvents[f.id] = try await ev
                        self.friendHomework[f.id] = await hw ?? self.friendHomework[f.id] ?? []
                        CookieJar.write(c.cookies, to: CookieJar.friendURL(f.id))
                    } catch ViggoError.notLoggedIn {
                        await self.friendSessionExpired(f)
                    } catch {}
                }
            }
        }
    }

    // MARK: filtering

    func visible(_ e: ViggoEvent) -> Bool {
        switch e.kind {
        case .duty: return false
        case .birthday: return prefs.showBirthdays
        case .routine: return prefs.includedRoutines.contains(e.title)
        default: return true
        }
    }

    /// Distinct everyday items found in the schedule (morgenmad, rengøring …).
    var routineTitles: [String] {
        Array(Set(events.filter { $0.kind == .routine }.map(\.title))).sorted()
    }

    func toggleRoutine(_ t: String, _ on: Bool) {
        var r = Set(prefs.includedRoutines)
        if on { r.insert(t) } else { r.remove(t) }
        prefs.includedRoutines = r.sorted()
    }

    func importToCalendar() {
        prefs.imported = true
        applyCalendar()
        if !status.hasPrefix("Kalender") { status = "Importeret til Kalender ✓" }
    }

    func removeFromCalendar() {
        prefs.imported = false
        do {
            for name in Config.allCalendars { try calSync.remove(named: name) }
            status = "Fjernet fra Kalender"
        } catch {
            status = "Kalender: \(error.localizedDescription)"
        }
    }

    func items(on day: Date, from list: [ViggoEvent]? = nil) -> [ViggoEvent] {
        onDay(day, list).filter { visible($0) && $0.kind != .birthday }
    }

    var dutyTonight: [String] {
        onDay(Date()).filter { $0.kind == .duty && $0.rawName.localizedCaseInsensitiveContains("aftenvagt") }
            .map { $0.rawName.components(separatedBy: " - ").first ?? $0.rawName }
    }

    static let eveningDefaults = ["aftensmad", "stilletime", "fællessamling", "område", "værelse", "godnat"]

    func inMenubar(_ title: String) -> Bool {
        if let picked = prefs.menubarItems { return picked.contains(title) }
        let l = title.lowercased()
        return AppState.eveningDefaults.contains { l.contains($0) } && !l.hasPrefix("tjek") && !l.contains("hovedrengøring")
    }

    func toggleMenubar(_ t: String, _ on: Bool) {
        var cur = Set(routineTitles.filter { inMenubar($0) })
        if on { cur.insert(t) } else { cur.remove(t) }
        prefs.menubarItems = cur.sorted()
    }

    /// Everyday items left today, shown once lessons are over.
    func afterSchool(_ now: Date, from list: [ViggoEvent]? = nil) -> [ViggoEvent] {
        guard prefs.menubarRoutine else { return [] }
        let todays = onDay(now, list)
        let school = todays.filter { $0.kind == .lesson || $0.kind == .event }
        if let lastEnd = school.map(\.end).max(), lastEnd > now { return [] }
        return todays.filter { $0.kind == .routine && $0.end > now && inMenubar($0.title) }
    }

    /// Puts the day's food from the meal plan on Middag and Aftensmad, as the event's notes.
    func withFood(_ e: ViggoEvent) -> ViggoEvent {
        guard prefs.panelMeals, e.kind == .routine, e.notes.isEmpty, let day = meals[DateUtil.startOfDay(e.start)] else { return e }
        let t = e.title.lowercased()
        if t.hasPrefix("middag") { return e.withNotes(day.lunch) }
        if t.hasPrefix("aftensmad"), let d = day.dinner { return e.withNotes(d) }
        return e
    }

    /// Everyday items from Viggo's schedule that fall inside the school day, shown between the lessons
    /// like on Viggo: Middag, Tjek af værelser, Hovedrengøring af værelser, Formiddagspause.
    func lunch(_ now: Date, from list: [ViggoEvent]? = nil) -> [ViggoEvent] {
        guard prefs.panelLunch else { return [] }
        let todays = onDay(now, list)
        let school = todays.filter { $0.kind == .lesson || $0.kind == .event }
        let routines = todays.filter { $0.kind == .routine }
        let first = school.map(\.start).min() ?? .distantFuture, last = school.map(\.end).max() ?? .distantPast
        var picked = routines.filter { $0.title.lowercased().hasPrefix("middag") || ($0.start >= first && $0.start < last) }
        // Also what follows right after (Tjek af værelser after Middag), even when the lessons are over.
        var grew = true
        while grew {
            grew = false
            for r in routines where !picked.contains(where: { $0.id == r.id })
                && picked.contains(where: { r.start >= $0.end && r.start.timeIntervalSince($0.end) <= 5 * 60 }) && (school.isEmpty || r.start < last.addingTimeInterval(2 * 3600)) {
                picked.append(r); grew = true
            }
        }
        return picked.sorted { $0.start < $1.start }.map(withFood)
    }

    /// Breaks between class lessons ("104 Tysk", "104 Dansk"), not between electives or line subjects.
    /// A gap of up to 30 minutes with nothing else in it counts as a break.
    func breaks(_ day: Date, from list: [ViggoEvent]? = nil, menubar: Bool = false) -> [ViggoEvent] {
        guard menubar ? prefs.menubarBreaks : prefs.panelBreaks else { return [] }
        let todays = onDay(day, list).filter { $0.kind != .duty && $0.kind != .birthday }
        let classes = todays.filter { $0.kind == .lesson && $0.rawName.firstMatch("^\\d+\\s") != nil }
            .sorted { $0.start < $1.start }
        var out: [ViggoEvent] = []
        for (a, b) in zip(classes, classes.dropFirst()) {
            let gap = b.start.timeIntervalSince(a.end)
            guard gap > 0, gap <= 30 * 60,
                  !todays.contains(where: { $0.start < b.start && $0.end > a.end && $0.id != a.id && $0.id != b.id }) else { continue }
            out.append(ViggoEvent(id: -(Int(a.end.timeIntervalSince1970) / 60), rawName: "Pause", start: a.end, end: b.start,
                                  room: "", notes: "", kind: .pause, teachers: [], groups: []))
        }
        return out
    }

    /// Your own items (Indstillinger › Egne punkter) on the given day.
    /// What a friend is doing now, and whether they are free.
    func friendStatus(_ f: Friend, now: Date) -> (String, Bool) {
        let today = (friendEvents[f.id] ?? []).filter {
            ($0.kind == .lesson || $0.kind == .event) && DateUtil.cal.isDate($0.start, inSameDayAs: now)
        }.sorted { $0.start < $1.start }
        if let c = today.first(where: { $0.start <= now && $0.end > now }) {
            return ("\(c.shortTitle) til \(DateUtil.hm(c.end))", false)
        }
        if let n = today.first(where: { $0.start > now }) { return ("Fri til \(DateUtil.hm(n.start))", true) }
        return ("Fri", true)
    }

    /// One day in the week view: lessons and events, plus lunch, pauses and (for you) your own items.
    /// `wholeDay` also takes the evening (Aftensmad, Stilletime, Godnat), like Viggo's own schedule.
    func weekItems(_ d: Date, person: UUID?, wholeDay: Bool = false) -> [ViggoEvent] {
        let list = person.flatMap { friendEvents[$0] }
        let day = onDay(d, list)
        let school = day.filter { ($0.kind == .lesson || $0.kind == .event) && (person != nil || visible($0)) }
        var extra = lunch(d, from: list) + breaks(d, from: list) + (person == nil ? customEvents(on: d) : [])
        if wholeDay {
            let have = Set(extra.map(\.id))
            let rest = day.filter { $0.kind == .routine && !have.contains($0.id) }
            extra += rest
        }
        return (school + extra.map(withFood)).sorted { $0.start < $1.start }
    }

    func customEvents(on day: Date) -> [ViggoEvent] {
        prefs.customItems.enumerated().compactMap { $0.element.event(on: day, index: $0.offset) }
    }

    /// Today's lessons/events plus the everyday items after school, as one list.
    func timeline(_ now: Date, from list: [ViggoEvent]? = nil) -> [ViggoEvent] {
        let all = onDay(now, list)
        let school = all.filter { ($0.kind == .lesson || $0.kind == .event) && visibleOrFriend($0, list != nil) }
        let lastEnd = school.map(\.end).max() ?? DateUtil.startOfDay(now)
        let evening = all.filter { $0.kind == .routine
            && $0.start >= lastEnd && inMenubar($0.title) }
        let meal = lunch(now, from: list).filter { e in !evening.contains { $0.id == e.id } }
        let own = list == nil ? customEvents(on: now) : []
        return (school + evening.map(withFood) + meal + breaks(now, from: list) + own).sorted { $0.start < $1.start }
    }

    private func visibleOrFriend(_ e: ViggoEvent, _ friend: Bool) -> Bool { friend || visible(e) }

    /// The school part of a day: the lessons, and events that begin before the last lesson ends.
    /// An evening event (a concert, packing rooms) is not school, so "Efter skole" and "fri kl."
    /// do not wait for it. A day with no lessons counts its events as the school day.
    nonisolated static func schoolDay(_ items: [ViggoEvent]) -> [ViggoEvent] {
        let lessons = items.filter { $0.kind == .lesson }
        guard let last = lessons.map(\.end).max() else { return items.filter { $0.kind == .event } }
        return items.filter { $0.kind == .lesson || ($0.kind == .event && $0.start < last) }
    }

    func tomorrowFirst(_ now: Date, from list: [ViggoEvent]? = nil) -> (ViggoEvent, Int)? {
        let t = items(on: DateUtil.add(.day, 1, now), from: list)
        return t.first.map { ($0, t.count) }
    }

    // MARK: homework, badge, free together, focus, login item

    func toggleHomework(_ h: Homework) {
        guard let i = homework.firstIndex(where: { $0.id == h.id }) else { return }
        let newValue = !homework[i].done
        if newValue { Haptic.success() } else { Haptic.tap() }
        homework[i].done = newValue
        #if os(iOS)
        scheduleAhead()
        #endif
        Task {
            do {
                try await client.setHomework(h.id, done: newValue)
                if prefs.imported { applyCalendar() }
            } catch {
                if let j = homework.firstIndex(where: { $0.id == h.id }) { homework[j].done = !newValue }
                status = "Kunne ikke gemme lektie: \(error.localizedDescription)"
            }
        }
    }

    var badgeCount: Int { prefs.menubarBadge ? unreadCount + questionnaireCount : 0 }

    /// Gaps today where neither you nor the friend has a lesson or event (from now until 18:00).
    func freeTogether(with friendEvents: [ViggoEvent], now: Date) -> [(Date, Date)] {
        freeTogether(withAll: [friendEvents], now: now)
    }

    /// The friends picked for "Fri sammen", all of them until you choose. Logged-out friends are left out.
    var freeGroup: [Friend] {
        let ids = Set(prefs.freeGroup)
        return friends.filter { (ids.isEmpty || ids.contains($0.id.uuidString)) && !friendExpired.contains($0.id) }
    }

    func toggleFreeGroup(_ f: Friend) {
        var ids = prefs.freeGroup.isEmpty ? friends.map(\.id.uuidString) : prefs.freeGroup
        if let i = ids.firstIndex(of: f.id.uuidString) { ids.remove(at: i) } else { ids.append(f.id.uuidString) }
        // Keep at least one; an empty list would mean "all".
        if !ids.isEmpty { prefs.freeGroup = ids }
    }

    /// When you and the picked friends are all free today.
    func groupFree(now: Date) -> [(Date, Date)] {
        freeTogether(withAll: freeGroup.map { friendEvents[$0.id] ?? [] }, now: now)
    }

    /// Gaps today where you and every one of the friends are free at once.
    func freeTogether(withAll lists: [[ViggoEvent]], now: Date) -> [(Date, Date)] {
        let dayStart = DateUtil.cal.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let dayEnd = DateUtil.cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        let from = max(now, dayStart)
        guard from < dayEnd else { return [] }
        func busy(_ list: [ViggoEvent], mine: Bool) -> [(Date, Date)] {
            list.filter { ($0.kind == .lesson || $0.kind == .event) && (!mine || visible($0))
                && DateUtil.cal.isDate($0.start, inSameDayAs: now) && $0.end > from && $0.start < dayEnd }
                .map { (max($0.start, from), min($0.end, dayEnd)) }
        }
        let all = (busy(events, mine: true) + lists.flatMap { busy($0, mine: false) }).sorted { $0.0 < $1.0 }
        var gaps: [(Date, Date)] = []
        var cursor = from
        for (s, e) in all {
            if s > cursor, s.timeIntervalSince(cursor) >= 15 * 60 { gaps.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if dayEnd.timeIntervalSince(cursor) >= 15 * 60 { gaps.append((cursor, dayEnd)) }
        return gaps
    }

    /// Turns the chosen Focus on when a lesson starts and off when it ends, through two shortcuts
    /// Viggo+ makes itself (Sources/FocusShortcuts.swift). Also right away if the app opens mid-lesson.
    func updateFocus() {
        #if os(macOS)
        focusTimer?.invalidate()
        guard prefs.focusEnabled else {
            if focusActive == true { setFocus(false) }
            focusActive = nil
            return
        }
        let now = Date()
        let lessons = events.filter { $0.kind == .lesson && visible($0) && $0.end > now }
        let inLesson = lessons.contains { $0.start <= now }
        if focusActive != inLesson, focusActive != nil || inLesson { setFocus(inLesson) }
        focusActive = inLesson
        // Wake exactly at the next start or end instead of up to a minute late on the minute timer.
        let next = lessons.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
        if let next, next.timeIntervalSince(now) < 3600 {
            focusTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.updateFocus() }
            }
        }
        #endif
    }

    #if os(macOS)
    private func setFocus(_ on: Bool) {
        let fs = FocusShortcuts.shared
        let n = FocusShortcuts.names(for: fs.mode(prefs.focusMode))
        Task {
            if let err = await fs.run(on ? n.on : n.off) {
                fs.message = err
                status = "Fokus: \(err)"
            }
        }
    }
    #endif

    #if os(macOS)
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { status = "Start ved login: \(error.localizedDescription)" }
            objectWillChange.send()
        }
    }
    #endif

    var menuTitle: String {
        let now = tick
        let today = (items(on: now).filter { $0.kind == .lesson || $0.kind == .event } + lunch(now) + breaks(now, menubar: true) + customEvents(on: now))
            .sorted { $0.start < $1.start }
        if let cur = today.first(where: { $0.start <= now && $0.end > now }) {
            return "\(cur.menuBarTitle) → \(DateUtil.hm(cur.end))"
        }
        if let next = today.first(where: { $0.start > now }) {
            return "\(next.menuBarTitle) \(DateUtil.hm(next.start))"
        }
        let evening = afterSchool(now)
        if let cur = evening.first(where: { $0.start <= now }) {
            return "\(cur.menuBarTitle) → \(DateUtil.hm(cur.end))"
        }
        if let next = evening.first {
            return "\(next.menuBarTitle) \(DateUtil.hm(next.start))"
        }
        return ""
    }

    // MARK: calendar

    private func describe(_ e: ViggoEvent) -> String {
        var lines: [String] = []
        if !e.teachers.isEmpty {
            let t = e.teachers.prefix(6).joined(separator: ", ")
            lines.append("Lærere: \(t)\(e.teachers.count > 6 ? " +\(e.teachers.count - 6)" : "")")
        }
        if !e.groups.isEmpty, e.groups.count <= 4 { lines.append("Hold: \(e.groups.joined(separator: ", "))") }
        if !e.notes.isEmpty { lines.append(""); lines.append(e.notes) }
        lines.append("")
        lines.append("Åbn i Viggo: \(e.link.absoluteString)")
        return lines.joined(separator: "\n")
    }

    func applyCalendar() {
        guard calendarAccess else { status = "Kalender: giv Viggo+ adgang i Systemindstillinger › Anonymitet › Kalendere"; return }
        do {
            let from = DateUtil.fetchStart, to = DateUtil.fetchEnd

            var lessonItems: [CalItem] = [], eventItems: [CalItem] = [], routineItems: [CalItem] = []
            for e in events where visible(e) {
                if e.kind == .birthday {
                    eventItems.append(CalItem(key: e.key, title: "🎂 \(e.title)", start: DateUtil.startOfDay(e.start),
                                              end: DateUtil.startOfDay(e.start), allDay: true, location: nil, notes: nil, alarms: []))
                    continue
                }
                var alarms: [EKAlarm] = []
                if e.kind == .lesson, prefs.lessonAlarmMinutes > 0 {
                    alarms.append(EKAlarm(relativeOffset: TimeInterval(-prefs.lessonAlarmMinutes * 60)))
                }
                let item = CalItem(key: e.key, title: e.title, start: e.start, end: e.end, allDay: false,
                                   location: e.room.isEmpty ? nil : e.room, notes: describe(e), alarms: alarms)
                switch e.kind {
                case .lesson: lessonItems.append(item)
                case .routine: routineItems.append(item)
                default: if prefs.importEvents { eventItems.append(item) }
                }
            }

            let hwFrom = DateUtil.mondayOf(Date()), hwTo = DateUtil.add(.day, 28, hwFrom)
            var hwItems: [CalItem] = []
            for h in homework {
                var alarms: [EKAlarm] = []
                if prefs.homeworkAlarm, !h.done,
                   let at = DateUtil.cal.date(bySettingHour: 18, minute: 0, second: 0, of: DateUtil.add(.day, -1, h.day)),
                   at > Date() {
                    alarms.append(EKAlarm(absoluteDate: at))
                }
                var notes: [String] = []
                if !h.group.isEmpty { notes.append("Hold: \(h.group)") }
                if !h.notes.isEmpty { notes.append(h.notes) }
                if !h.author.isEmpty { notes.append(h.author) }
                notes.append("Åbn i Viggo: \(h.link.absoluteString)")
                let title = (h.done ? "✓ " : "📚 ") + h.title
                if let s = h.start, let e = h.end {
                    hwItems.append(CalItem(key: "hw-\(h.id)", title: title, start: s, end: e, allDay: false,
                                           location: nil, notes: notes.joined(separator: "\n"), alarms: alarms))
                } else {
                    hwItems.append(CalItem(key: "hw-\(h.id)", title: title, start: h.day, end: h.day, allDay: true,
                                           location: nil, notes: notes.joined(separator: "\n"), alarms: alarms))
                }
            }

            func put(_ on: Bool, _ name: String, _ color: PlatformColor, _ items: [CalItem], _ f: Date, _ t: Date) throws {
                if on {
                    try calSync.sync(items, into: calSync.calendar(named: name, color: color), from: f, to: t)
                } else {
                    try calSync.remove(named: name)
                }
            }
            try put(prefs.importSchedule, Config.calSchedule, .systemBlue, lessonItems, from, to)
            try put(prefs.importEvents || prefs.showBirthdays, Config.calEvents, .systemPurple, eventItems, from, to)
            try put(!routineItems.isEmpty, Config.calRoutine, .systemGreen, routineItems, from, to)
            try put(prefs.importHomework, Config.calHomework, .systemOrange, hwItems, hwFrom, hwTo)
            if status.hasPrefix("Kalender") { status = "" }
        } catch {
            status = "Kalender: \(error.localizedDescription)"
        }
    }

    // MARK: notifications

    private func when(_ d: Date) -> String {
        DateUtil.cal.isDateInToday(d) ? "i dag \(DateUtil.hm(d))"
            : DateUtil.cal.isDateInTomorrow(d) ? "i morgen \(DateUtil.hm(d))"
            : "\(DateUtil.day(d)) \(DateUtil.hm(d))"
    }

    private func detectChanges() {
        let now = Date(), horizon = DateUtil.add(.day, 7, now)
        let relevant = events.filter { $0.kind == .lesson || $0.kind == .event }
        var newMap: [String: EventSnap] = [:]
        for e in relevant { newMap[e.key] = EventSnap(title: e.title, start: e.start, end: e.end, room: e.room) }

        var notes: [(String, String, URL?)] = []
        if snapshot.initialized {
            if prefs.notifyChanges {
                for e in relevant where e.start > now && e.start < horizon && visible(e) {
                    if let o = snapshot.events[e.key] {
                        if o.start != e.start || o.end != e.end {
                            notes.append(("Flyttet: \(e.title)", "\(when(o.start)) → \(when(e.start))", e.link))
                        } else if o.room != e.room, !e.room.isEmpty {
                            notes.append(("Nyt lokale: \(e.title)", "\(o.room.isEmpty ? "?" : o.room) → \(e.room), \(when(e.start))", e.link))
                        }
                    } else if e.kind == .event {
                        notes.append(("Ny begivenhed: \(e.title)", when(e.start), e.link))
                    }
                }
                for (k, o) in snapshot.events where o.start > now && o.start < horizon && newMap[k] == nil {
                    notes.append(("Aflyst: \(o.title)", when(o.start), nil))
                }
            }
            if prefs.notifyHomework {
                for h in homework where !h.done && !snapshot.homeworkIDs.contains(h.id) {
                    notes.append(("Nye lektier: \(h.title)", "\(h.group.isEmpty ? "" : h.group + " · ")til \(DateUtil.day(h.due))", h.link))
                }
            }
            if prefs.notifyMessages {
                for m in messages where !snapshot.messageIDs.contains(m.id) {
                    notes.append(("Ny besked fra \(m.sender)", m.subject, m.link))
                }
            }
            if prefs.notifyBulletin, let seen = snapshot.bulletinIDs {
                for b in bulletins where !seen.contains(b.id) {
                    notes.append(("Nyt opslag: \(b.title)", String(b.text.prefix(120)), Config.baseURL))
                }
            }
        }
        snapshot.bulletinIDs = (snapshot.bulletinIDs ?? []).union(bulletins.map(\.id))
        if notes.count > 5 {
            Notifier.shared.post("Viggo+: \(notes.count) ændringer", notes.prefix(6).map { "• \($0.0)" }.joined(separator: "\n"))
        } else {
            for n in notes { Notifier.shared.post(n.0, n.1, url: n.2) }
        }
        snapshot.events = newMap
        snapshot.homeworkIDs.formUnion(homework.map(\.id))
        snapshot.messageIDs.formUnion(messages.map(\.id))
        snapshot.initialized = true
        snapshot.save()
    }

    /// People in the schedule with a birthday today.
    var birthdaysToday: [String] {
        onDay(Date()).filter { $0.kind == .birthday }.map(\.birthdayName)
    }

    private func checkBriefs() {
        // The iPhone app hands these to iOS ahead of time (scheduleAhead), so it never sends them twice.
        #if os(iOS)
        return
        #endif
        let now = Date(), today = DateUtil.ymd(now)
        let hour = DateUtil.cal.component(.hour, from: now)
        if prefs.notifyBirthdays, hour >= prefs.morningHour, snapshot.lastBirthdayDay != today, !events.isEmpty {
            snapshot.lastBirthdayDay = today
            snapshot.save()
            let b = birthdaysToday
            if !b.isEmpty {
                Notifier.shared.post("🎂 Fødselsdag i dag", b.joined(separator: ", "))
            }
        }
        let minute = hour * 60 + DateUtil.cal.component(.minute, from: now)
        if prefs.homeworkReminder, minute >= prefs.homeworkReminderAt, snapshot.lastHomeworkReminder != today, lastSync != nil {
            snapshot.lastHomeworkReminder = today
            snapshot.save()
            if let r = homeworkReminder(for: now) { Notifier.shared.post(r.0, r.1) }
        }
        guard prefs.briefs, !events.isEmpty else { return }
        if hour >= prefs.morningHour, hour < 12, snapshot.lastMorningBrief != today {
            snapshot.lastMorningBrief = today
            snapshot.save()
            Notifier.shared.post("God morgen ☀️", brief(for: now, prefix: "I dag"))
        }
        if hour >= prefs.eveningHour, snapshot.lastEveningBrief != today {
            snapshot.lastEveningBrief = today
            snapshot.save()
            Notifier.shared.post("I morgen 🌙", brief(for: DateUtil.add(.day, 1, now), prefix: "I morgen"))
        }
    }

    /// "Du har 2 lektier til i morgen" the evening before, or nil when there are none.
    func homeworkReminder(for evening: Date) -> (String, String)? {
        let tomorrow = DateUtil.add(.day, 1, evening)
        let open = homework.filter { !$0.done && DateUtil.cal.isDate($0.day, inSameDayAs: tomorrow) }
        guard !open.isEmpty else { return nil }
        let title = open.count == 1 ? "Du har 1 lektie til i morgen" : "Du har \(open.count) lektier til i morgen"
        let body = open.prefix(4).map { $0.group.isEmpty ? $0.title : "\($0.group): \($0.title)" }.joined(separator: "\n")
            + (open.count > 4 ? "\n+ \(open.count - 4) mere" : "")
        return ("📚 " + title, body)
    }

    func brief(for day: Date, prefix: String) -> String {
        let list = items(on: day).filter { $0.kind == .lesson || $0.kind == .event }
        var parts: [String] = []
        if let first = list.first {
            parts.append("\(prefix): \(list.count) \(list.count == 1 ? "punkt" : "punkter"). Første: \(first.title) \(DateUtil.hm(first.start))\(first.room.isEmpty ? "" : " (\(first.room))").")
        } else {
            parts.append("\(prefix): ingen timer.")
        }
        let hw = homework.filter { !$0.done && DateUtil.cal.isDate($0.day, inSameDayAs: day) }
        if !hw.isEmpty { parts.append("Lektier: " + hw.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: " ")
    }

    // MARK: windows

    #if os(macOS)
    /// Closes the panel and puts `w` next to where the panel was, under the menu bar,
    /// so a window opened from the panel shows up beside it instead of on top of it.
    private func showBesidePanel(_ w: NSWindow) {
        let panel = PanelController.shared.frame
        PanelController.shared.close()
        w.layoutIfNeeded()
        if let panel, let screen = (NSScreen.screens.first { $0.frame.intersects(panel) } ?? NSScreen.main)?.visibleFrame {
            let size = w.frame.size
            let gap: CGFloat = 12
            var x = panel.minX - gap - size.width                      // left of the panel
            if x < screen.minX + gap { x = panel.maxX + gap }           // else right of it
            if x + size.width > screen.maxX - gap { x = screen.maxX - gap - size.width }
            x = max(screen.minX + gap, x)
            let y = max(screen.minY + gap, panel.maxY - size.height)   // top lines up with the panel
            w.setFrameOrigin(NSPoint(x: x, y: y))
        } else if !w.isVisible {
            w.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(self)))
            w.title = "Viggo+"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        if let w = settingsWindow { showBesidePanel(w) }
    }

    func openViggo(_ url: URL = Config.baseURL) { NSWorkspace.shared.open(url) }

    /// Shows a lesson with the teacher's info and links.
    func openLesson(_ e: ViggoEvent) {
        let host = NSHostingController(rootView: LessonDetailView(e: e))
        if let w = lessonWindow {
            w.contentViewController = host
        } else {
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            lessonWindow = w
        }
        lessonWindow?.title = e.title
        if let w = lessonWindow { showBesidePanel(w) }
    }

    func openWeek() {
        if weekWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WeekView().environmentObject(self)))
            w.title = "Uge-overblik"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 1040, height: 760))
            weekWindow = w
        }
        if let w = weekWindow { showBesidePanel(w) }
    }

    /// The messages window, like Mail: the inbox on the left, the thread on the right.
    func openMessages(thread: Int? = nil) {
        if let thread { Inbox.shared.selected = thread }
        if messagesWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: MessagesWindow().environmentObject(self)))
            w.title = "Beskeder"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 980, height: 680))
            w.setFrameAutosaveName("ViggoMessages")
            messagesWindow = w
        }
        if let w = messagesWindow { showBesidePanel(w) }
    }

    func setupHotKey() {
        HotKey.shared.action = { Task { @MainActor in HotKey.togglePanel() } }
        if prefs.hotkeyEnabled { HotKey.shared.register(choice: prefs.hotkeyChoice) } else { HotKey.shared.unregister() }
    }
    #else
    func openViggo(_ url: URL = Config.baseURL) { Platform.open(url) }
    func openMessages(thread: Int? = nil) { openViggo() }
    /// The iPhone shows a lesson's details as a sheet.
    func openLesson(_ e: ViggoEvent) { shownLesson = e }
    #endif
}
