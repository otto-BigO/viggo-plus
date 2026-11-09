import Combine
import Foundation

// MARK: - Models

/// A thread in the inbox list.
struct MessageThread: Identifiable, Hashable {
    let id: Int
    let sender: String
    let when: String
    let subject: String
    let preview: String
    let image: URL?
    /// How many others got it too ("+13" in Viggo).
    let others: Int
    var unread: Bool
}

/// One message in a thread.
struct ThreadMessage: Identifiable, Hashable {
    let id: Int
    let authorID: Int
    let author: String
    let image: URL?
    let date: String
    let text: String
    let links: [URL]
}

struct ThreadDetail: Hashable {
    let id: Int
    let subject: String
    let from: [String]
    let to: [String]
    let messages: [ThreadMessage]
    let canReplyAll: Bool
}

/// Someone you can write to.
struct Person: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let image: URL?
    let info: String

    enum CodingKeys: String, CodingKey { case Id, Name, Image, ProfileValue, Grade }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .Id)
        name = (try? c.decode(String.self, forKey: .Name)) ?? ""
        image = (try? c.decodeIfPresent(String.self, forKey: .Image)).flatMap { $0 }.flatMap(URL.init(string:))
        // "Hus: Drengegangen;*; Værelse: D17" → "Drengegangen, D17"
        let raw = (try? c.decodeIfPresent(String.self, forKey: .ProfileValue)) ?? nil
        info = raw.map { $0.components(separatedBy: ";*;").map { $0.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "" }
            .filter { !$0.isEmpty }.joined(separator: ", ") } ?? ""
    }
    init(id: Int, name: String, image: URL?, info: String) { self.id = id; self.name = name; self.image = image; self.info = info }
    var firstName: String { name.components(separatedBy: " ").first ?? name }
}

/// A group you can write to (a class, a team, a house).
struct PersonGroup: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let members: [Int]
    enum CodingKeys: String, CodingKey { case Id, Name, UsersIds }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .Id)
        name = (try? c.decode(String.self, forKey: .Name)) ?? ""
        members = (try? c.decode([Int].self, forKey: .UsersIds)) ?? []
    }
}

enum ReplyKind: String { case all = "AnswerThreadToAll", sender = "AnswerThisMessageTo" }

// MARK: - Parsing

extension Parser {
    static func threads(_ html: String, unread: Set<Int>) -> [MessageThread] {
        html.components(separatedBy: "<li id=\"tree-item-message-id-").dropFirst().compactMap { c in
            guard let idS = c.firstMatch("^(\\d+)")?[1], let id = Int(idS) else { return nil }
            let who = c.firstMatch("<div><div>(.*?)</div><small>(.*?)</small></div>")
            let subject = c.firstMatch("<div class=\"h\"[^>]*>(.*?)</div>")?[1].strippedHTML ?? ""
            // Viggo glues the paragraphs together in the preview ("15.15Sunday"), so put a space back.
            let preview = (c.firstMatch("<div class=\"h\"[^>]*>.*?</div>\\s*<div>(.*?)</div>")?[1].strippedHTML ?? "")
                .replacingOccurrences(of: "([0-9.!?:)]|[a-zæøå]{2})([A-ZÆØÅ])", with: "$1 $2", options: .regularExpression)
            let img = c.firstMatch("<div class=\"imgs[^\"]*\">\\s*<div><img src=\"([^\"]+)\"")?[1].htmlDecoded
            let others = c.firstMatch("<label>\\+(\\d+)</label>").flatMap { Int($0[1]) } ?? 0
            let cls = c.firstMatch("class=\"([^\"]*)\"")?[1] ?? ""
            return MessageThread(id: id, sender: who?[1].strippedHTML ?? "", when: who?[2].strippedHTML ?? "",
                                 subject: subject, preview: preview, image: img.flatMap(URL.init(string:)), others: others,
                                 unread: unread.contains(id) || cls.contains("unread"))
        }
    }

    static func thread(_ html: String, id: Int) -> ThreadDetail {
        let subject = html.firstMatch("<div class=\"head\">\\s*<h3>(?:<i[^>]*></i>)?(.*?)</h3>")?[1].strippedHTML ?? ""
        let info = html.firstMatch("<li class=\"message-info\">(.*?)</li>\\s*<li class=\"[^\"]*\" id=\"mid_")?[1] ?? ""
        let names: (String) -> [String] = { block in block.matches("<a href=\"/Basic/Users/Details/\\d+\"[^>]*>(.*?)</a>").map { $0[1].strippedHTML } }
        let fromBlock = info.components(separatedBy: "o-flaticon-users").first ?? ""
        let toBlock = info.components(separatedBy: "o-flaticon-users").dropFirst().joined()
        let parts = html.components(separatedBy: "\" id=\"mid_").dropFirst()
        let messages: [ThreadMessage] = parts.compactMap { c in
            guard let mid = c.firstMatch("^(\\d+)").flatMap({ Int($0[1]) }) else { return nil }
            let author = c.firstMatch("<a href=\"/Basic/Users/Details/(\\d+)\" class=\"hinted\">\\s*(.*?)<small>(.*?)</small>")
            let img = c.firstMatch("^\\d+\">\\s*<img src=\"([^\"]+)\"")?[1].htmlDecoded
            // The body sits in <div class="p">, before "Læst af" or the reply buttons.
            var body = c.components(separatedBy: "<div class=\"p\">").dropFirst().first ?? ""
            for stop in ["<label onclick", "<ul class=\"button-group", "</li>"] {
                if let r = body.range(of: stop) { body = String(body[..<r.lowerBound]) }
            }
            let links = body.matches("<a[^>]+href=\"(https?://[^\"]+)\"").compactMap { URL(string: $0[1].htmlDecoded) }
            let text = body.replacingOccurrences(of: "</div>\\s*$", with: "", options: .regularExpression).messageText
            return ThreadMessage(id: mid, authorID: author.flatMap { Int($0[1]) } ?? 0, author: author?[2].strippedHTML ?? "",
                                 image: img.flatMap(URL.init(string:)), date: author?[3].strippedHTML ?? "", text: text, links: links)
        }
        return ThreadDetail(id: id, subject: subject, from: names(fromBlock), to: names(toBlock), messages: messages,
                            canReplyAll: html.contains("type=AnswerThreadToAll"))
    }

    /// Every input of a form, as Viggo would post it.
    static func formFields(_ html: String) -> [(String, String)] {
        html.matches("<input([^>]*)>").compactMap { m in
            let a = m[1]
            guard let name = a.firstMatch("name=\"([^\"]+)\"")?[1], !a.contains("type=\"file\""), !a.contains("type=\"checkbox\"") else { return nil }
            return (name, a.firstMatch("value=\"([^\"]*)\"")?[1].htmlDecoded ?? "")
        }
    }
}

extension String {
    /// Message HTML as plain text that keeps its paragraphs.
    var messageText: String {
        var s = replacingOccurrences(of: "<script.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<br ?/?>|</p>|</li>|</div>|</h\\d>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.htmlDecoded
        s = s.replacingOccurrences(of: "[ \\t\\r]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain text as the HTML Viggo's editor makes, one <p> per line.
    var messageHTML: String {
        components(separatedBy: "\n").map { line in
            let esc = line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            return "<p>\(esc.isEmpty ? "<br>" : esc)</p>"
        }.joined()
    }
}

// MARK: - Client

extension ViggoClient {
    static let inboxFolder = 13

    func fetchThreads() async throws -> [MessageThread] {
        let html = String(decoding: try await getPublic("/Basic/Message/Folder/\(Self.inboxFolder)?ajax=1"), as: UTF8.self)
        guard html.contains("Indbakke") else { throw ViggoError.notLoggedIn }
        let w = String(decoding: (try? await getPublic("/Basic/Message/HomeWidget?show=50&ajax=1")) ?? Data(), as: UTF8.self)
        let unread = Set(w.matches("Message/Details/(?:\\d+/)?(\\d+)").compactMap { Int($0[1]) })
        return Parser.threads(html, unread: unread)
    }

    /// Opening a thread marks it read on Viggo, like on the website.
    func fetchThread(_ id: Int) async throws -> ThreadDetail {
        let html = String(decoding: try await getPublic("/Basic/Message/Details/\(Self.inboxFolder)/\(id)/?ajax=1"), as: UTF8.self)
        guard html.contains("list-conversation") else { throw ViggoError.unexpected("Kunne ikke åbne beskeden") }
        return Parser.thread(html, id: id)
    }

    func fetchDirectory() async throws -> (people: [Person], groups: [PersonGroup]) {
        struct Dir: Decodable { let Users: [Person]; let Groups: [PersonGroup] }
        let d = try JSONDecoder().decode(Dir.self, from: try await getPublic("/Shared/Search/GetautocompleteData"))
        return (d.Users.sorted { $0.name < $1.name }, d.Groups.filter { !$0.members.isEmpty }.sorted { $0.name < $1.name })
    }

    func reply(to id: Int, kind: ReplyKind, text: String) async throws {
        try await send(form: "/Basic/Message/AddEdit/\(id)/?type=\(kind.rawValue)&ajax=1", set: ["Contents": text.messageHTML])
    }

    func newMessage(to users: [Int], subject: String, text: String) async throws {
        try await send(form: "/Basic/Message/AddEdit/?ajax=1",
                       set: ["users": users.map(String.init).joined(separator: ","), "headline": subject, "Contents": text.messageHTML])
    }

    /// Loads Viggo's own form (so the hidden fields and token are right), fills it in and posts it.
    private func send(form path: String, set values: [String: String]) async throws {
        let html = String(decoding: try await getPublic(path), as: UTF8.self)
        guard html.contains("/Basic/Message/SaveMessage") else { throw ViggoError.unexpected("Kunne ikke åbne svar-formularen") }
        var fields = Parser.formFields(html).filter { values[$0.0] == nil }
        for (k, v) in values { fields.append((k, v)) }
        if !fields.contains(where: { $0.0 == "Contents" }) { fields.append(("Contents", "")) }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._*")
        let body = fields.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        var req = URLRequest(url: URL(string: "/Basic/Message/SaveMessage", relativeTo: base)!.absoluteURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = Data(body.utf8)
        let (data, resp) = try await session.data(for: req)
        if let u = resp.url, u.path.lowercased().contains("/account") { throw ViggoError.notLoggedIn }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ViggoError.unexpected("Viggo svarede \(code)") }
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("field-validation-error") || text.contains("validation-summary-errors") {
            throw ViggoError.unexpected("Viggo afviste beskeden")
        }
    }
}

// MARK: - Inbox state

/// Viggo's inbox inside the app: read threads, answer and write new messages.
@MainActor
final class Inbox: ObservableObject {
    static let shared = Inbox()
    private let client = ViggoClient()

    @Published var threads: [MessageThread] = []
    @Published var loading = false
    @Published var error: String?
    @Published var people: [Person] = []
    @Published var groups: [PersonGroup] = []
    /// The thread shown in the Mac window.
    @Published var selected: Int?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            threads = try await client.fetchThreads()
            error = nil
            AppState.shared.unreadCount = threads.filter(\.unread).count
        } catch ViggoError.notLoggedIn {
            error = "Du er logget ud af Viggo."
        } catch {
            self.error = "Kunne ikke hente beskeder."
        }
    }

    func open(_ id: Int) async throws -> ThreadDetail {
        let d = try await client.fetchThread(id)
        if let i = threads.firstIndex(where: { $0.id == id }), threads[i].unread {
            threads[i].unread = false
            AppState.shared.unreadCount = max(0, AppState.shared.unreadCount - 1)
        }
        return d
    }

    func reply(_ id: Int, kind: ReplyKind, text: String) async throws {
        try await client.reply(to: id, kind: kind, text: text)
        await load()
    }

    func send(to: [Int], subject: String, text: String) async throws {
        try await client.newMessage(to: to, subject: subject, text: text)
        await load()
    }

    func loadDirectory() async {
        guard people.isEmpty, let d = try? await client.fetchDirectory() else { return }
        people = d.people
        groups = d.groups
    }
}

