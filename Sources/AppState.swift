import Foundation
import AppKit
import SwiftUI
import EventKit
import WebKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var events: [ViggoEvent] = []
    @Published var homework: [Homework] = []
    @Published var messages: [ViggoMessage] = []
    @Published var lastSync: Date?
    @Published var syncing = false
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
    private var friendLogin: WebLogin?
    /// Unlocked once per app run with Touch ID or the Mac password.
    private var vaultUnlocked = false

    func unlockVault(_ reason: String) async -> Bool {
        if vaultUnlocked { return true }
        vaultUnlocked = await Biometrics.unlock(reason: reason)
        return vaultUnlocked
    }

    let prefs = Prefs.shared
    private let client = ViggoClient()
    private let calSync = CalendarSync()
    private var calendarAccess = false
    private var password: String?
    private var snapshot = Snapshot.load()
    private var lastAttempt = Date.distantPast
    private var lastPing = Date()
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private let webLogin = WebLogin()
    private var expiryNotified = false

    private init() {
        Task { await start() }
    }

    // MARK: lifecycle

    func start() async {
        Notifier.shared.setup()
        CookieJar.restore()
        loadFriends()
        calendarAccess = await calSync.requestAccess()
        if calendarAccess, !prefs.imported, !UserDefaults.standard.bool(forKey: "cleanedAutoImport") {
            for name in Config.allCalendars { try? calSync.remove(named: name) }
            UserDefaults.standard.set(true, forKey: "cleanedAutoImport")
        }
        if prefs.hasPassword && !prefs.username.isEmpty { await unlockPassword() }
        await sync()
        if needsLogin { openSettings() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
    }

    private func onTick() {
        tick = Date()
        if Date().timeIntervalSince(lastAttempt) >= Config.pollInterval {
            Task { await sync() }
        } else if Date().timeIntervalSince(lastPing) >= 4 * 60 {
            lastPing = Date()
            Task { await keepAlive() }
        }
        checkBriefs()
    }

    /// Pings Viggo every few minutes so sessions don't time out; logs in again if they did.
    func keepAlive() async {
        do { try await client.ping() } catch ViggoError.notLoggedIn { await sync() } catch {}
        for f in friends where !friendExpired.contains(f.id) {
            let c = ViggoClient(cookies: CookieJar.read(CookieJar.friendURL(f.id)))
            if (try? await c.ping()) != nil { CookieJar.write(c.cookies, to: CookieJar.friendURL(f.id)) }
        }
    }

    func forgetSavedLogin() {
        Keychain.delete(account: prefs.username)
        prefs.hasPassword = false
        password = nil
        loginMessage = ""
    }

    func unlockPassword() async {
        if prefs.useTouchID {
            guard await Biometrics.unlock(reason: "låse dit Viggo-login op") else {
                status = "Touch ID afbrudt, bruger gemt session"
                return
            }
        }
        password = Keychain.load(account: prefs.username)
    }

    // MARK: login

    static func normalize(_ u: String) -> String {
        let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.contains("@") ? t : t + Config.loginDomain
    }

    func saveLogin(username raw: String, password pw: String) async {
        let username = AppState.normalize(raw)
        loginMessage = "Logger ind…"
        do {
            try await client.login(username: username, password: pw)
            prefs.username = username
            Keychain.save(pw, account: username)
            prefs.hasPassword = true
            password = pw
            needsLogin = false
            loginMessage = "Logget ind ✓"
            await sync()
        } catch {
            loginMessage = error.localizedDescription
        }
    }

    func loginWithBrowser() {
        loginMessage = "Log ind i vinduet…"
        webLogin.show { [weak self] cookies in
            guard let self else { return }
            cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
            self.needsLogin = false
            self.expiryNotified = false
            self.loginMessage = "Logget ind via Viggo ✓"
            Task { await self.sync() }
        }
    }

    func logout() {
        Keychain.delete(account: prefs.username)
        prefs.hasPassword = false
        password = nil
        HTTPCookieStorage.shared.cookies(for: Config.baseURL)?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        CookieJar.clear()
        webLogin.clearCookies()
        profile = nil
        lastSync = nil
        needsLogin = true
        loginMessage = "Logget ud"
    }

    private func withRelogin<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() } catch ViggoError.notLoggedIn {
            if password == nil && prefs.hasPassword { await unlockPassword() }
            guard let pw = password, !prefs.username.isEmpty else {
                needsLogin = true
                if !expiryNotified && snapshot.initialized {
                    expiryNotified = true
                    Notifier.shared.post("Viggo+: log ind igen", "Din Viggo-session er udløbet. Åbn Viggo+ i menubaren.")
                }
                throw ViggoError.notLoggedIn
            }
            try await client.login(username: prefs.username, password: pw)
            return try await op()
        }
    }

    // MARK: sync

    func sync() async {
        guard !syncing else { return }
        syncing = true
        lastAttempt = Date()
        defer { syncing = false }
        do {
            let c = client
            let (ev, hw, msg) = try await withRelogin { () async throws -> ([ViggoEvent], [Homework], [ViggoMessage]) in
                (try await c.fetchEvents(), try await c.fetchHomework(), try await c.fetchMessages())
            }
            events = ev
            homework = hw
            messages = msg
            if let p = c.profile { profile = p }
            needsLogin = false
            if prefs.imported { applyCalendar() }
            Task { await syncFriends() }
            detectChanges()
            lastSync = Date()
            CookieJar.save()
            if !status.hasPrefix("Kalender") { status = "" }
        } catch {
            status = error.localizedDescription
        }
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
        friendMessage = existing == nil ? "Lad din ven logge ind i vinduet…" : "Lad \(existing!.firstName) logge ind igen…"
        login.show(store: .nonPersistent(), title: existing.map { "\($0.firstName): log ind på Viggo" } ?? "Ven: log ind på Viggo") { [weak self] cookies in
            Task { await self?.finishFriend(cookies: cookies) }
        }
    }

    private func finishFriend(cookies: [HTTPCookie]) async {
        friendLogin = nil
        let client = ViggoClient(cookies: cookies)
        do {
            let prof = try await client.fetchProfile()
            if prof.id == profile?.id { friendMessage = "Det er din egen konto 🙂"; return }
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
        } catch {
            friendMessage = "Kunne ikke tilføje: \(error.localizedDescription)"
        }
    }

    /// The friend types their own SkoleIT login so Viggo+ can log them in again by itself.
    /// Saves the login (Touch ID / Mac password protected) whether or not it works yet.
    func saveFriendLogin(_ f: Friend, username raw: String, password pw: String) async -> Bool {
        let username = AppState.normalize(raw)
        guard await unlockVault("gemme \(f.firstName)s login i nøgleringen") else {
            friendMessage = "Ikke gemt: Touch ID / kode blev afbrudt"
            return false
        }
        Keychain.save(pw, account: f.keychainAccount)
        if let i = friends.firstIndex(where: { $0.id == f.id }) {
            friends[i].savedUsername = username
            friends[i].loginVerified = nil
        }
        saveFriends()
        friendMessage = "Login gemt i nøgleringen. Tryk Verificér for at teste det."
        return true
    }

    /// Tests the saved login against Viggo.
    func verifyFriendLogin(_ f: Friend) async {
        guard let user = f.savedUsername else { return }
        guard await unlockVault("teste \(f.firstName)s gemte login"),
              let pw = Keychain.load(account: f.keychainAccount) else {
            friendMessage = "Afbrudt"
            return
        }
        friendMessage = "Tester \(f.firstName)s login…"
        let client = ViggoClient(cookies: [])
        var ok = false
        do {
            try await client.login(username: user, password: pw)
            let prof = try await client.fetchProfile()
            if prof.id == f.viggoID {
                ok = true
                CookieJar.write(client.cookies, to: CookieJar.friendURL(f.id))
                friendExpired.remove(f.id)
                friendMessage = "\(f.firstName)s login virker ✓"
            } else {
                friendMessage = "Login virker, men hører til \(prof.name), ikke \(f.firstName)"
            }
        } catch {
            friendMessage = "\(f.firstName): \(error.localizedDescription)"
        }
        if let i = friends.firstIndex(where: { $0.id == f.id }) { friends[i].loginVerified = ok }
        saveFriends()
        if ok { await syncFriends() }
    }

    func forgetFriendLogin(_ f: Friend) {
        Keychain.delete(account: f.keychainAccount)
        if let i = friends.firstIndex(where: { $0.id == f.id }) {
            friends[i].savedUsername = nil
            friends[i].loginVerified = nil
        }
        saveFriends()
    }

    func removeFriend(_ f: Friend) {
        Keychain.delete(account: f.keychainAccount)
        friends.removeAll { $0.id == f.id }
        friendEvents[f.id] = nil
        friendHomework[f.id] = nil
        friendExpired.remove(f.id)
        if selectedFriend == f.id { selectedFriend = nil }
        try? FileManager.default.removeItem(at: CookieJar.friendURL(f.id))
        saveFriends()
    }

    func syncFriends() async {
        for f in friends {
            let client = ViggoClient(cookies: CookieJar.read(CookieJar.friendURL(f.id)))
            do {
                friendEvents[f.id] = try await client.fetchEvents(weeksBack: 0, weeksAhead: 1)
                friendHomework[f.id] = (try? await client.fetchHomework()) ?? friendHomework[f.id] ?? []
                CookieJar.write(client.cookies, to: CookieJar.friendURL(f.id))
                friendExpired.remove(f.id)
            } catch ViggoError.notLoggedIn {
                if let user = f.savedUsername, await unlockVault("logge dine venner ind på Viggo igen"),
                   let pw = Keychain.load(account: f.keychainAccount) {
                    do {
                        try await client.login(username: user, password: pw)
                        friendEvents[f.id] = try await client.fetchEvents(weeksBack: 0, weeksAhead: 1)
                        friendHomework[f.id] = (try? await client.fetchHomework()) ?? friendHomework[f.id] ?? []
                        CookieJar.write(client.cookies, to: CookieJar.friendURL(f.id))
                        friendExpired.remove(f.id)
                        continue
                    } catch {}
                }
                friendExpired.insert(f.id)
            } catch {}
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

    var importPreview: String {
        let from = DateUtil.fetchStart
        let ev = events.filter { visible($0) && $0.start >= from }
        var n = 0
        if prefs.importSchedule { n += ev.filter { $0.kind == .lesson }.count }
        if prefs.importEvents { n += ev.filter { $0.kind == .event || $0.kind == .birthday }.count }
        n += ev.filter { $0.kind == .routine }.count
        if prefs.importHomework { n += homework.count }
        return "\(n) punkter fra \(DateUtil.day(from)) til \(DateUtil.day(DateUtil.add(.day, -1, DateUtil.fetchEnd)))"
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
        (list ?? events).filter { visible($0) && $0.kind != .birthday && DateUtil.cal.isDate($0.start, inSameDayAs: day) }
    }

    var dutyTonight: [String] {
        events.filter { $0.kind == .duty && DateUtil.cal.isDateInToday($0.start) && $0.rawName.localizedCaseInsensitiveContains("aftenvagt") }
            .map { $0.rawName.components(separatedBy: " - ").first ?? $0.rawName }
    }

    var upcomingHomework: [Homework] {
        let today = DateUtil.startOfDay(Date())
        return homework.filter { $0.day >= today }
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
        let events = list ?? self.events
        let school = events.filter { ($0.kind == .lesson || $0.kind == .event) && DateUtil.cal.isDate($0.start, inSameDayAs: now) }
        if let lastEnd = school.map(\.end).max(), lastEnd > now { return [] }
        return events.filter {
            $0.kind == .routine && DateUtil.cal.isDate($0.start, inSameDayAs: now) && $0.end > now && inMenubar($0.title)
        }
    }

    var menuTitle: String {
        let now = tick
        let today = items(on: now).filter { $0.kind == .lesson || $0.kind == .event }
        if let cur = today.first(where: { $0.start <= now && $0.end > now }) {
            return "\(cur.shortTitle) → \(DateUtil.hm(cur.end))"
        }
        if let next = today.first(where: { $0.start > now }) {
            return "\(next.shortTitle) \(DateUtil.hm(next.start))"
        }
        let evening = afterSchool(now)
        if let cur = evening.first(where: { $0.start <= now }) {
            return "\(cur.shortTitle) → \(DateUtil.hm(cur.end))"
        }
        if let next = evening.first {
            return "\(next.shortTitle) \(DateUtil.hm(next.start))"
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

            func put(_ on: Bool, _ name: String, _ color: NSColor, _ items: [CalItem], _ f: Date, _ t: Date) throws {
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
        }
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

    private func checkBriefs() {
        guard prefs.briefs, !events.isEmpty else { return }
        let now = Date(), today = DateUtil.ymd(now)
        let hour = DateUtil.cal.component(.hour, from: now)
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

    func brief(for day: Date, prefix: String) -> String {
        let list = items(on: day).filter { $0.kind == .lesson || $0.kind == .event }
        var parts: [String] = []
        if let first = list.first {
            parts.append("\(prefix): \(list.count) punkter. Første: \(first.title) \(DateUtil.hm(first.start))\(first.room.isEmpty ? "" : " (\(first.room))").")
        } else {
            parts.append("\(prefix): ingen timer.")
        }
        let hw = homework.filter { !$0.done && DateUtil.cal.isDate($0.day, inSameDayAs: day) }
        if !hw.isEmpty { parts.append("Lektier: " + hw.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: " ")
    }

    // MARK: windows

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(self)))
            w.title = "Viggo+"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openViggo(_ url: URL = Config.baseURL) { NSWorkspace.shared.open(url) }
}
