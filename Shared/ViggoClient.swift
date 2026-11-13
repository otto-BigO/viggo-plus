import Foundation

final class ViggoClient {
    let base = Config.baseURL
    let session: URLSession
    private(set) var profile: Profile?

    /// nil = your own account (shared cookies). Cookies = a friend's private session.
    init(cookies: [HTTPCookie]? = nil) {
        let c: URLSessionConfiguration = cookies == nil ? .default : .ephemeral
        if cookies == nil { c.httpCookieStorage = .shared }
        cookies?.forEach { c.httpCookieStorage?.setCookie($0) }
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 ViggoPlus/0.1"]
        session = URLSession(configuration: c)
    }

    var cookies: [HTTPCookie] { session.configuration.httpCookieStorage?.cookies ?? [] }

    /// Keeps the server session alive.
    func ping() async throws { _ = try await get("/Basic/Ping") }

    func fetchProfile() async throws -> Profile {
        let html = String(decoding: try await get("/Basic/HomeworkAndAssignment"), as: UTF8.self)
        guard let p = Parser.profile(html) else { throw ViggoError.notLoggedIn }
        profile = p
        return p
    }

    func getPublic(_ path: String) async throws -> Data { try await get(path) }

    /// A file behind the login, like a picture on a post.
    func data(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code), resp.url?.path.lowercased().contains("/account") != true else { throw ViggoError.notLoggedIn }
        return data
    }

    private func get(_ path: String) async throws -> Data {
        let req = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        let (data, resp) = try await session.data(for: req)
        if let u = resp.url, u.path.lowercased().contains("/account") { throw ViggoError.notLoggedIn }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ViggoError.unexpected("HTTP \(code)") }
        return data
    }

    /// Unread messages and questionnaires waiting for you.
    func fetchCounts() async throws -> (unread: Int, questionnaires: Int) {
        async let widget = get("/Basic/Message/HomeWidget?show=20&ajax=1")
        async let front = get("/")
        let w = String(decoding: try await widget, as: UTF8.self)
        let unread = Set(w.matches("Message/Details/(?:\\d+/)?(\\d+)").map { $0[1] }).count
        let home = String(decoding: try await front, as: UTF8.self)
        let q = home.firstMatch("Du har (\\d+) spørgeskema").flatMap { Int($0[1]) } ?? 0
        return (unread, q)
    }

    /// Same as ticking "Gennemført" on Viggo.
    func setHomework(_ id: Int, done: Bool) async throws {
        var req = URLRequest(url: URL(string: "/Basic/HomeworkAndAssignment/SaveStatusChange/\(id)?status=\(done ? 1 : 0)",
                                      relativeTo: base)!.absoluteURL)
        req.httpMethod = "PUT"
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (_, resp) = try await session.data(for: req)
        if let u = resp.url, u.path.lowercased().contains("/account") { throw ViggoError.notLoggedIn }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ViggoError.unexpected("HTTP \(code)") }
    }

    func fetchEvents(weeksBack: Int = Config.weeksBack, weeksAhead: Int = Config.nearWeeks) async throws -> [ViggoEvent] {
        try await fetchEvents(weeks: -weeksBack...weeksAhead)
    }

    /// Week offsets from this week's Monday.
    func fetchEvents(weeks: ClosedRange<Int>) async throws -> [ViggoEvent] {
        let monday = DateUtil.mondayOf(Date())
        // All weeks at once: one request per week, so fetching them in a row took most of the startup time.
        // Six at a time: the whole school year is 30+ weeks and Viggo shouldn't get them all at once.
        let paths = weeks.map { w -> String in
            let m = DateUtil.add(.weekOfYear, w, monday)
            let s = DateUtil.ymd(m), e = DateUtil.ymd(DateUtil.add(.day, 6, m))
            return "/Shared/Events/GetEventItems?target=YourSchedule&date=\(s)&type=week&startDate=\(s)&endDate=\(e)"
        }
        let weeks = try await withThrowingTaskGroup(of: [ViggoEvent].self) { group in
            var next = 0
            func add() {
                guard next < paths.count else { return }
                let path = paths[next]; next += 1
                group.addTask {
                    let data = try await self.get(path)
                    guard (try? JSONSerialization.jsonObject(with: data)) is [Any] else { throw ViggoError.notLoggedIn }
                    return try Parser.events(data)
                }
            }
            for _ in 0..<6 { add() }
            var all: [[ViggoEvent]] = []
            for try await list in group { all.append(list); add() }
            return all
        }
        var all: [String: ViggoEvent] = [:]
        for ev in weeks.joined() { all[ev.key] = ev }
        return all.values.sorted { $0.start < $1.start }
    }

    func fetchHomework() async throws -> [Homework] {
        let monday = DateUtil.mondayOf(Date())
        let d0 = monday, d1 = DateUtil.add(.day, 14, monday)
        async let a = get("/Basic/HomeworkAndAssignment/?date=\(DateUtil.ymd(d0))")
        async let b = get("/Basic/HomeworkAndAssignment/?date=\(DateUtil.ymd(d1))")
        let pages = [(String(decoding: try await a, as: UTF8.self), d0), (String(decoding: try await b, as: UTF8.self), d1)]
        var all: [Int: Homework] = [:]
        for (i, (html, d)) in pages.enumerated() {
            guard html.contains("homework-data") else { throw ViggoError.notLoggedIn }
            if i == 0, let p = Parser.profile(html) { profile = p }
            for h in Parser.homework(html, near: d) { all[h.id] = h }
        }
        return all.values.sorted { $0.due < $1.due }
    }

    func fetchMessages() async throws -> [ViggoMessage] {
        let data = try await get("/Basic/Message/Folder/13?ajax=1")
        return Parser.messages(String(decoding: data, as: UTF8.self))
    }
}
