import Foundation
import AppKit
import SwiftUI
import EventKit
import WebKit
import ServiceManagement

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
    @Published var unreadCount = 0
    @Published var questionnaireCount = 0
    @Published var bulletins: [Bulletin] = []
    private var weekWindow: NSWindow?
    private var lessonWindow: NSWindow?
    private var focusActive: Bool?
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
    private let client = ViggoClient()
    private let calSync = CalendarSync()
    private var calendarAccess = false
    private var snapshot = Snapshot.load()
    private var lastAttempt = Date.distantPast
    private var lastPing = Date()
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private let webLogin = WebLogin()
    private let autoLogin = AutoLogin()
    private var expiryNotified = false
    private var lastAutoLogin = Date.distantPast
    private var lastFriendAutoLogin: [UUID: Date] = [:]
    @Published var friendAutoLoginRunning: Set<UUID> = []
    @Published var autoLoginRunning = false

    private init() {
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
                print(autoLogin.log.joined(separator: " > "))
                exit(0)
            }
        } else {
            Task { await start() }
        }
    }

    // MARK: lifecycle

    func start() async {
        Notifier.shared.setup()
        try? FileManager.default.removeItem(at: CookieJar.dir.appendingPathComponent("login.log"))
        CookieJar.restore()
        loadFriends()
        purgeSavedPasswords()
        calendarAccess = await calSync.requestAccess()
        if calendarAccess, !prefs.imported, !UserDefaults.standard.bool(forKey: "cleanedAutoImport") {
            for name in Config.allCalendars { try? calSync.remove(named: name) }
            UserDefaults.standard.set(true, forKey: "cleanedAutoImport")
        }
        setupHotKey()
        await sync()
        if needsLogin { openSettings() }
        Updater.shared.checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.keepAlive(); await self?.sync() }
        }
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
        Updater.shared.checkIfDue()
    }

    /// Pings Viggo every few minutes so sessions stay alive as long as possible.
    func keepAlive() async {
        lastPing = Date()
        do { try await client.ping() } catch ViggoError.notLoggedIn {
            if await tryAutoLogin() { await sync() } else { sessionExpired() }
        } catch {}
        for f in friends where !friendExpired.contains(f.id) {
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
        guard url.scheme == "viggoplus" else { NSWorkspace.shared.open(url); return }
        if url.host == "login" { loginWithBrowser() }
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
    func tryAutoLogin(force: Bool = false) async -> Bool {
        guard SkoleITLogin.isSet, let user = SkoleITLogin.username, let pass = SkoleITLogin.password,
              !autoLoginRunning, force || Date().timeIntervalSince(lastAutoLogin) > 10 * 60 else { return false }
        lastAutoLogin = Date()
        autoLoginRunning = true
        defer { autoLoginRunning = false }
        loginMessage = "Logger ind automatisk…"
        switch await autoLogin.run(username: user, password: pass) {
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
        if await tryAutoLogin(force: true) { await sync() }
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
        CookieJar.clear()
        webLogin.clearCookies()
        profile = nil
        lastSync = nil
        needsLogin = true
        loginMessage = "Logget ud"
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
            if let n = try? await c.fetchCounts() { unreadCount = n.unread; questionnaireCount = n.questionnaires }
            if let b = try? await c.fetchBulletins() { bulletins = b }
            needsLogin = false
            if prefs.imported { applyCalendar() }
            Task { await syncFriends() }
            detectChanges()
            lastSync = Date()
            CookieJar.save()
            if !status.hasPrefix("Kalender") { status = "" }
        } catch ViggoError.notLoggedIn {
            // Try the saved SkoleIT login first. Otherwise the log-in banner in the panel says so.
            if await tryAutoLogin() { syncing = false; await sync() } else { sessionExpired() }
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
    func tryFriendAutoLogin(_ f: Friend, force: Bool = false) async -> Bool {
        guard let login = FriendLogin.get(f.id), !friendAutoLoginRunning.contains(f.id),
              force || Date().timeIntervalSince(lastFriendAutoLogin[f.id] ?? .distantPast) > 10 * 60 else { return false }
        lastFriendAutoLogin[f.id] = Date()
        friendAutoLoginRunning.insert(f.id)
        defer { friendAutoLoginRunning.remove(f.id) }
        friendMessage = "Logger \(f.firstName) ind automatisk…"
        switch await AutoLogin().run(username: login.user, password: login.pass, store: .nonPersistent()) {
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
        await tryFriendAutoLogin(f, force: true)
    }

    /// Adds a new friend straight from their SkoleIT login, without the login window.
    func addFriendWithSkoleIT(username: String, password: String) async {
        friendMessage = "Logger ind med SkoleIT…"
        switch await AutoLogin().run(username: username, password: password, store: .nonPersistent()) {
        case .success(let cookies):
            if let f = await finishFriend(cookies: cookies) {
                FriendLogin.save(f.id, username: username, password: password)
                friendMessage = "\(f.firstName) er tilføjet med automatisk login ✓"
            }
        case .failure(let why):
            friendMessage = "Kunne ikke logge ind: \(why)"
        }
    }

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
        for f in friends where !friendExpired.contains(f.id) {
            let c = ViggoClient(cookies: CookieJar.read(CookieJar.friendURL(f.id)))
            do {
                friendEvents[f.id] = try await c.fetchEvents(weeksBack: 0, weeksAhead: 1)
                friendHomework[f.id] = (try? await c.fetchHomework()) ?? friendHomework[f.id] ?? []
                CookieJar.write(c.cookies, to: CookieJar.friendURL(f.id))
            } catch ViggoError.notLoggedIn {
                await friendSessionExpired(f)
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

    /// Today's lessons/events plus the everyday items after school, as one list.
    func timeline(_ now: Date, from list: [ViggoEvent]? = nil) -> [ViggoEvent] {
        let all = list ?? events
        let school = all.filter { ($0.kind == .lesson || $0.kind == .event) && visibleOrFriend($0, list != nil)
            && DateUtil.cal.isDate($0.start, inSameDayAs: now) }
        let lastEnd = school.map(\.end).max() ?? DateUtil.startOfDay(now)
        let evening = all.filter { $0.kind == .routine && DateUtil.cal.isDate($0.start, inSameDayAs: now)
            && $0.start >= lastEnd && inMenubar($0.title) }
        return (school + evening).sorted { $0.start < $1.start }
    }

    private func visibleOrFriend(_ e: ViggoEvent, _ friend: Bool) -> Bool { friend || visible(e) }

    func tomorrowFirst(_ now: Date, from list: [ViggoEvent]? = nil) -> (ViggoEvent, Int)? {
        let t = items(on: DateUtil.add(.day, 1, now), from: list)
        return t.first.map { ($0, t.count) }
    }

    // MARK: homework, badge, free together, focus, login item

    func toggleHomework(_ h: Homework) {
        guard let i = homework.firstIndex(where: { $0.id == h.id }) else { return }
        let newValue = !homework[i].done
        homework[i].done = newValue
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
        let dayStart = DateUtil.cal.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let dayEnd = DateUtil.cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        let from = max(now, dayStart)
        guard from < dayEnd else { return [] }
        func busy(_ list: [ViggoEvent], mine: Bool) -> [(Date, Date)] {
            list.filter { ($0.kind == .lesson || $0.kind == .event) && (!mine || visible($0))
                && DateUtil.cal.isDate($0.start, inSameDayAs: now) && $0.end > from && $0.start < dayEnd }
                .map { (max($0.start, from), min($0.end, dayEnd)) }
        }
        let all = (busy(events, mine: true) + busy(friendEvents, mine: false)).sorted { $0.0 < $1.0 }
        var gaps: [(Date, Date)] = []
        var cursor = from
        for (s, e) in all {
            if s > cursor, s.timeIntervalSince(cursor) >= 15 * 60 { gaps.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if dayEnd.timeIntervalSince(cursor) >= 15 * 60 { gaps.append((cursor, dayEnd)) }
        return gaps
    }

    /// Runs your "focus on/off" Shortcuts when a lesson starts and ends.
    private func updateFocus() {
        guard prefs.focusEnabled else { focusActive = nil; return }
        let now = Date()
        let inLesson = events.contains { $0.kind == .lesson && $0.start <= now && $0.end > now }
        defer { focusActive = inLesson }
        guard let was = focusActive, was != inLesson else { return }
        runShortcut(inLesson ? prefs.focusOnShortcut : prefs.focusOffShortcut)
    }

    func runShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { status = "Start ved login: \(error.localizedDescription)" }
            objectWillChange.send()
        }
    }

    var menuTitle: String {
        let now = tick
        let today = items(on: now).filter { $0.kind == .lesson || $0.kind == .event }
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
        events.filter { $0.kind == .birthday && DateUtil.cal.isDateInToday($0.start) }.map(\.birthdayName)
    }

    private func checkBriefs() {
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
        lessonWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        lessonWindow?.makeKeyAndOrderFront(nil)
    }

    func openWeek() {
        if weekWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WeekView().environmentObject(self)))
            w.title = "Uge-overblik"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 1040, height: 760))
            w.center()
            weekWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        weekWindow?.makeKeyAndOrderFront(nil)
    }

    func setupHotKey() {
        HotKey.shared.action = { Task { @MainActor in HotKey.togglePanel() } }
        if prefs.hotkeyEnabled { HotKey.shared.register(choice: prefs.hotkeyChoice) } else { HotKey.shared.unregister() }
    }
}
