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

    private var fingerprint: String {
        if let f = UserDefaults.standard.string(forKey: "fingerprint") { return f }
        let f = UUID().uuidString.lowercased()
        UserDefaults.standard.set(f, forKey: "fingerprint")
        return f
    }

    private func get(_ path: String) async throws -> Data {
        let req = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        let (data, resp) = try await session.data(for: req)
        if let u = resp.url, u.path.lowercased().contains("/account/login") { throw ViggoError.notLoggedIn }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ViggoError.unexpected("HTTP \(code)") }
        return data
    }

    private func form(_ p: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return p.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)!
    }

    func login(username: String, password: String) async throws {
        let loginURL = URL(string: "/Basic/Account/Login", relativeTo: base)!.absoluteURL
        _ = try? await session.data(from: loginURL)
        var req = URLRequest(url: loginURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(["UserName": username, "Password": password, "returnUrl": "", "fingerprint": fingerprint])
        _ = try await session.data(for: req)
        do { _ = try await get("/") } catch ViggoError.notLoggedIn { throw ViggoError.badCredentials }
    }

    func fetchEvents(weeksBack: Int = Config.weeksBack, weeksAhead: Int = Config.weeksAhead) async throws -> [ViggoEvent] {
        let monday = DateUtil.mondayOf(Date())
        var all: [String: ViggoEvent] = [:]
        for w in -weeksBack...weeksAhead {
            let m = DateUtil.add(.weekOfYear, w, monday)
            let s = DateUtil.ymd(m), e = DateUtil.ymd(DateUtil.add(.day, 6, m))
            let data = try await get("/Shared/Events/GetEventItems?target=YourSchedule&date=\(s)&type=week&startDate=\(s)&endDate=\(e)")
            guard (try? JSONSerialization.jsonObject(with: data)) is [Any] else { throw ViggoError.notLoggedIn }
            for ev in try Parser.events(data) { all[ev.key] = ev }
        }
        return all.values.sorted { $0.start < $1.start }
    }

    func fetchHomework() async throws -> [Homework] {
        let monday = DateUtil.mondayOf(Date())
        var all: [Int: Homework] = [:]
        for offset in [0, 14] {
            let d = DateUtil.add(.day, offset, monday)
            let data = try await get("/Basic/HomeworkAndAssignment/?date=\(DateUtil.ymd(d))")
            let html = String(decoding: data, as: UTF8.self)
            guard html.contains("homework-data") else { throw ViggoError.notLoggedIn }
            if offset == 0, let p = Parser.profile(html) { profile = p }
            for h in Parser.homework(html, near: d) { all[h.id] = h }
        }
        return all.values.sorted { $0.due < $1.due }
    }

    func fetchMessages() async throws -> [ViggoMessage] {
        let data = try await get("/Basic/Message/Folder/13?ajax=1")
        return Parser.messages(String(decoding: data, as: UTF8.self))
    }
}
