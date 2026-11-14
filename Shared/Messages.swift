import Combine
import Foundation

// MARK: - Models

/// A thread in the inbox list.
extension String {
    /// Viggo's "57 minutter siden", "I går 13:51" or "5. nov 2026 11:08" shortened like in Beskeder: "57 min", "I går", "5. nov".
    var shortWhen: String {
        let t = trimmingCharacters(in: .whitespaces)
        if let m = t.firstMatch("^(\\d+) minut") { return "\(m[1]) min" }
        if let m = t.firstMatch("^(\\d+) time") { return "\(m[1]) t" }
        if t.lowercased().hasPrefix("et øjeblik") || t.lowercased().hasPrefix("lige nu") { return "Nu" }
        if let m = t.firstMatch("^(i går|i dag)") { return m[1].prefix(1).uppercased() + m[1].dropFirst() }
        if let m = t.firstMatch("^(\\d{1,2}\\. \\w+)") { return m[1] }
        return t
    }
}

struct MessageThread: Identifiable, Hashable, Codable {
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
struct ThreadMessage: Identifiable, Hashable, Codable {
    let id: Int
    let authorID: Int
    let author: String
    let image: URL?
    let date: String
    let text: String
    let links: [URL]
    /// Who has read it and when, from Viggo's "Læst af".
    var readBy: [Reader] = []
    /// A personal answer inside a group thread: only you and this person can see it.
    var privateWith: String? = nil
    /// The start of the message it answers ("Hej Malou og Otto. Vær sød ...").
    var answers: String? = nil
    /// Pictures and files attached to it.
    var files: [MessageFile] = []
}

/// A picture or file attached to a message on Viggo. Both need your Viggo session to download.
struct MessageFile: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let mime: String
    /// The file itself.
    let url: URL
    /// A small version, for pictures.
    let preview: URL?
    var isImage: Bool { mime.hasPrefix("image/") || preview != nil && name.range(of: "\\.(jpe?g|png|gif|heic|webp)$", options: [.regularExpression, .caseInsensitive]) != nil }
    var isVideo: Bool { mime.hasPrefix("video/") || name.range(of: "\\.(mp4|mov|m4v)$", options: [.regularExpression, .caseInsensitive]) != nil }
}

/// A file picked to go with a message.
struct Attachment: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let mime: String
    let data: Data
    var size: String { ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file) }
    var isImage: Bool { mime.hasPrefix("image/") }
}

struct Reader: Hashable, Codable {
    let name: String
    let date: String
    let image: URL?
}

struct ThreadDetail: Hashable, Codable {
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
            var preview = (c.firstMatch("<div class=\"h\"[^>]*>.*?</div>\\s*<div>(.*?)</div>")?[1].strippedHTML.htmlDecoded ?? "")
                .replacingOccurrences(of: "([0-9.!?:)]|[a-zæøå]{2})([A-ZÆØÅ])", with: "$1 $2", options: .regularExpression)
            // A message with only a picture: "Dig:" with nothing after it.
            let trimmed = preview.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasSuffix(":") { preview = trimmed + (trimmed.isEmpty ? "" : " ") + "📎 Vedhæftet fil" }
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
            for stop in ["<label onclick", "<ul class=\"button-group"] {
                if let r = body.range(of: stop) { body = String(body[..<r.lowerBound]) }
            }
            // Attachments: <ul class="files-attached"> with a preview link and a thumbnail per file.
            // Taken out of the text, or they read as "• Billede 1.jpg".
            var files: [MessageFile] = []
            if let r = body.range(of: "<ul class=\"files-attached\">") {
                let block = String(body[r.upperBound...]).components(separatedBy: "</ul>").first ?? ""
                for li in block.components(separatedBy: "<li").dropFirst() {
                    guard let m = li.firstMatch("href=\"/Shared/Files/Preview/(\\d+)\\?viggoFunction=(\\w+)&(?:amp;)?rowId=(\\d+)"),
                          let fid = Int(m[1]) else { continue }
                    let name = li.firstMatch("<span>(.*?)</span>")?[1].strippedHTML.htmlDecoded
                        ?? li.firstMatch("alt=\"([^\"]*)\"")?[1].htmlDecoded ?? "Fil"
                    let mime = li.firstMatch(" type=\"([^\"]+)\"")?[1] ?? ""
                    let thumb = li.firstMatch("<img src=\"([^\"]*DownloadFile[^\"]*)\"")?[1].htmlDecoded
                    guard let full = URL(string: "/Shared/Files/DownloadFile?viggoFunction=\(m[2])&id=\(fid)&rowId=\(m[3])&download=False", relativeTo: Config.baseURL)?.absoluteURL
                    else { continue }
                    files.append(MessageFile(id: fid, name: name, mime: mime, url: full,
                                             preview: thumb.flatMap { URL(string: $0, relativeTo: Config.baseURL)?.absoluteURL }))
                }
                body = String(body[..<r.lowerBound]).replacingOccurrences(of: "<hr\\s*/?>\\s*$", with: "", options: .regularExpression)
            }
            if let r = body.range(of: "</li>") { body = String(body[..<r.lowerBound]) }
            let links = body.matches("<a[^>]+href=\"(https?://[^\"]+)\"").compactMap { URL(string: $0[1].htmlDecoded) }
            let text = body.replacingOccurrences(of: "</div>\\s*$", with: "", options: .regularExpression).messageText
            // "Læst af 3": a hidden list of who read it, "Name (9. nov 2026 19:14)" with a picture.
            let list = c.components(separatedBy: "<ul class=\"list-icons small\"").dropFirst().first?
                .components(separatedBy: "</ul>").first ?? ""
            let readers: [Reader] = list.matches("<img src=\"([^\"]+)\"[^>]*>\\s*<p[^>]*>(.*?)</p>").map { r in
                let full = r[2].strippedHTML.htmlDecoded
                let m = full.firstMatch("^(.*) \\((.*)\\)$")
                return Reader(name: m?[1] ?? full, date: m?[2] ?? "", image: URL(string: r[1].htmlDecoded))
            }
            // <li class="me personal answered-to"> … "Personlig besked mellem dig og Heidi Gerneu".
            let personal = c.firstMatch("Personlig besked mellem dig og ([^<]+)<")?[1].htmlDecoded.trimmingCharacters(in: .whitespaces)
            let answers = c.firstMatch("<div class=\"answered-to-message\">.*?<a href=\"#mid_\\d+\">(.*?)</a>")?[1].strippedHTML.htmlDecoded
                // Viggo drops the line breaks in this snippet ("Otto.Vær", "HeidiEmilie"), so put a space back.
                .replacingOccurrences(of: "([.!?]|\\p{Ll})(\\p{Lu})", with: "$1 $2", options: .regularExpression)
            return ThreadMessage(id: mid, authorID: author.flatMap { Int($0[1]) } ?? 0, author: author?[2].strippedHTML ?? "",
                                 image: img.flatMap(URL.init(string:)), date: author?[3].strippedHTML ?? "", text: text, links: links,
                                 readBy: readers, privateWith: personal, answers: answers, files: files)
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

    func reply(to id: Int, kind: ReplyKind, text: String, files: [Attachment] = []) async throws {
        let ids = try await upload(files)
        try await send(form: "/Basic/Message/AddEdit/\(id)/?type=\(kind.rawValue)&ajax=1", set: ["Contents": text.messageHTML], files: ids)
    }

    func newMessage(to users: [Int], subject: String, text: String, files: [Attachment] = []) async throws {
        let ids = try await upload(files)
        try await send(form: "/Basic/Message/AddEdit/?ajax=1",
                       set: ["users": users.map(String.init).joined(separator: ","), "headline": subject, "Contents": text.messageHTML],
                       files: ids)
    }

    /// Viggo takes up to 10 MB per file.
    static let maxFileSize = 10 * 1024 * 1024

    func upload(_ files: [Attachment]) async throws -> [String] {
        var ids: [String] = []
        for f in files { ids.append(try await uploadFile(f)) }
        return ids
    }

    /// Puts a file in Viggo's temporary store the way the message form does and returns its id.
    /// It only becomes part of a message when the form is sent with `temporaryFile=<id>`.
    func uploadFile(_ f: Attachment) async throws -> String {
        guard f.data.count <= Self.maxFileSize else { throw ViggoError.unexpected("\(f.name) er over 10 MB") }
        let boundary = "ViggoPlus-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let safe = f.name.replacingOccurrences(of: "\"", with: "")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safe)\"\r\nContent-Type: \(f.mime)\r\n\r\n".utf8))
        body.append(f.data)
        body.append(Data("\r\n".utf8))
        field("id", "0")
        field("function", "1")
        body.append(Data("--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: URL(string: "/Basic/Message/UploadFile", relativeTo: base)!.absoluteURL)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("ViggoAjax", forHTTPHeaderField: "X-Request-By")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        if let u = resp.url, u.path.lowercased().contains("/account") { throw ViggoError.notLoggedIn }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ViggoError.unexpected("Viggo afviste \(f.name) (\(code))") }
        // A number or an id string, maybe in quotes or as {"fileId": …}.
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
        if text.range(of: "^[0-9a-zA-Z_-]+$", options: .regularExpression) != nil { return text }
        if let m = text.firstMatch("\"(?:fileId|id)\"\\s*:\\s*\"?([0-9a-zA-Z_-]+)") { return m[1] }
        throw ViggoError.unexpected("Viggo gav intet fil-id for \(f.name)")
    }

    /// Removes a temporary upload again (used by the upload self-test).
    func deleteTemporaryFile(_ id: String, name: String) async {
        let n = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        _ = try? await getPublic("/Shared/Files/DeleteTemporaryFiles/?id=\(id)&name=\(n)")
    }

    /// Loads Viggo's own form (so the hidden fields and token are right), fills it in and posts it.
    private func send(form path: String, set values: [String: String], files: [String] = []) async throws {
        let html = String(decoding: try await getPublic(path), as: UTF8.self)
        guard html.contains("/Basic/Message/SaveMessage") else { throw ViggoError.unexpected("Kunne ikke åbne svar-formularen") }
        var fields = Parser.formFields(html).filter { values[$0.0] == nil }
        for (k, v) in values { fields.append((k, v)) }
        for id in files { fields.append(("temporaryFile", id)) }
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
    /// Pinned threads, kept at the top like in Beskeder on the iPhone.
    @Published var pinned: [Int] = UserDefaults.standard.array(forKey: "pinnedThreads") as? [Int] ?? [] {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinnedThreads") }
    }

    func isPinned(_ id: Int) -> Bool { pinned.contains(id) }
    func togglePin(_ id: Int) {
        if let i = pinned.firstIndex(of: id) { pinned.remove(at: i) } else { pinned.insert(id, at: 0) }
    }
    var pinnedThreads: [MessageThread] { pinned.compactMap { id in threads.first { $0.id == id } } }
    var otherThreads: [MessageThread] { threads.filter { !pinned.contains($0.id) } }

    /// Threads opened or fetched ahead, so they open at once and the list can show "Set".
    @Published private(set) var details: [Int: ThreadDetail] = [:]

    // The inbox and the threads you have opened are kept on disk, so Beskeder works offline.
    private struct Stored: Codable { var threads: [MessageThread]; var details: [Int: ThreadDetail] }
    private var storeURL: URL { CookieJar.dir.appendingPathComponent("inbox.json") }

    init() {
        if let data = try? Data(contentsOf: storeURL), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            threads = s.threads; details = s.details
        }
    }

    private var saveTask: Task<Void, Never>?
    /// Written a moment later, so fetching twelve threads ahead writes the file once.
    private func save() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            // The newest 60 threads are plenty offline.
            let keep = Set(threads.prefix(60).map(\.id))
            let s = Stored(threads: threads, details: details.filter { keep.contains($0.key) })
            if let data = try? JSONEncoder().encode(s) { try? data.write(to: storeURL, options: .atomic) }
        }
    }

    /// When the thread list was last fetched from Viggo (not read from disk).
    private var loadedAt: Date?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            threads = try await client.fetchThreads()
            loadedAt = Date()
            save()
            error = nil
            AppState.shared.unreadCount = threads.filter(\.unread).count
            Deadlines.shared.scanAll()
            Task { await prefetch() }
        } catch ViggoError.notLoggedIn {
            error = "Du er logget ud af Viggo."
        } catch where AppState.isOffline(error) {
            // The saved inbox stays; the offline banner explains why it is not new.
            AppState.shared.offline = true
            self.error = threads.isEmpty ? "Du er offline, og der er ingen gemte beskeder endnu." : nil
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
        keep(d)
        return d
    }

    /// Marks a thread read without showing it: Viggo marks it when the thread is fetched.
    /// The dot goes at once and comes back if the fetch fails.
    func markRead(_ id: Int) {
        guard let i = threads.firstIndex(where: { $0.id == id }), threads[i].unread else { return }
        threads[i].unread = false
        AppState.shared.unreadCount = max(0, AppState.shared.unreadCount - 1)
        Task {
            do { keep(try await client.fetchThread(id)) }
            catch {
                if let j = threads.firstIndex(where: { $0.id == id }) { threads[j].unread = true }
                AppState.shared.unreadCount += 1
            }
        }
    }

    private func keep(_ d: ThreadDetail) {
        details[d.id] = d
        Receipts.track(d, notify: false)
        Deadlines.shared.scan(d)
        save()
    }

    /// Fetches the newest threads ahead of time. Only ones you have read already: opening an
    /// unread thread on Viggo marks it read, and that must only happen when you open it yourself.
    private var prefetching = false
    func prefetch() async {
        guard !prefetching else { return }
        prefetching = true
        defer { prefetching = false }
        for t in threads.prefix(12) where !t.unread && details[t.id] == nil {
            guard let d = try? await client.fetchThread(t.id) else { return }
            keep(d)
        }
    }

    struct Receipt: Equatable { let readers: [Reader]; let total: Int }

    /// Who has seen the newest message in a thread, when that message is yours.
    func receipt(_ id: Int) -> Receipt? { details[id].flatMap(Receipts.receipt) }

    /// Fetches the threads where your last message is not seen by everyone yet, and says who
    /// has seen it since last time ("Emilie har set din besked"). Run with every sync.
    ///
    /// Opening a thread marks it read on Viggo, so this only runs right after the list was fetched:
    /// with an old list a new reply would look read here and be opened behind your back.
    func checkReceipts() async {
        guard let t = loadedAt, Date().timeIntervalSince(t) < 120 else { return }
        for id in Receipts.watched() {
            if let t = threads.first(where: { $0.id == id }), t.unread { Receipts.stop(id); continue }
            guard let d = try? await client.fetchThread(id) else { continue }
            details[d.id] = d
            Receipts.track(d, notify: true)
        }
    }

    /// The inbox first, then the read receipts, in that order (see `checkReceipts`).
    func refresh() async {
        await load()
        await checkReceipts()
    }

    /// Forgets everything about the account that was logged in.
    func clear() {
        saveTask?.cancel()
        threads = []; details = [:]; people = []; groups = []; selected = nil; pinned = []
        loadedAt = nil; error = nil
        try? FileManager.default.removeItem(at: storeURL)
        Receipts.clear()
    }

    func reply(_ id: Int, kind: ReplyKind, text: String, files: [Attachment] = []) async throws {
        do { try await client.reply(to: id, kind: kind, text: text, files: files) }
        catch where AppState.isOffline(error) { throw ViggoError.offline }
        await load()
    }

    func send(to: [Int], subject: String, text: String, files: [Attachment] = []) async throws {
        do { try await client.newMessage(to: to, subject: subject, text: text, files: files) }
        catch where AppState.isOffline(error) { throw ViggoError.offline }
        await load()
    }

    func loadDirectory() async {
        guard people.isEmpty, let d = try? await client.fetchDirectory() else { return }
        people = d.people
        groups = d.groups
    }
}


/// Remembers who has seen your last message in a thread, so a new reader gives one notification.
@MainActor
enum Receipts {
    private struct Watch: Codable { var message: Int; var seen: [String]; var total: Int; var since: Date }
    private static let key = "readReceipts"
    private static var all: [String: Watch] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Watch].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func receipt(_ d: ThreadDetail) -> Inbox.Receipt? {
        guard let me = AppState.shared.profile, let last = d.messages.last, last.authorID == me.id else { return nil }
        // A personal answer can only be seen by the one it went to.
        let total = last.privateWith != nil ? 1 : Set(d.to + d.from).subtracting([me.name]).count
        return Inbox.Receipt(readers: last.readBy.filter { $0.name != me.name }, total: total)
    }

    /// Threads still worth checking: your last message, not seen by everyone, less than a week old.
    static func watched() -> [Int] {
        all.filter { $0.value.total > 0 && $0.value.seen.count < $0.value.total && -$0.value.since.timeIntervalSinceNow < 7 * 86400 }
            .sorted { $0.value.since > $1.value.since }.prefix(8).compactMap { Int($0.key) }
    }

    static func stop(_ id: Int) { all[String(id)] = nil }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// For testing: forget who has seen each message, so the next check tells about them again.
    static func forgetReaders() {
        var list = all
        for k in list.keys { list[k]?.seen = []; list[k]?.since = Date() }
        all = list
    }

    static func track(_ d: ThreadDetail, notify: Bool) {
        let k = String(d.id)
        guard let r = receipt(d), let last = d.messages.last else { all[k] = nil; return }
        let names = r.readers.map(\.name)
        var list = all
        if let w = list[k], w.message == last.id {
            let new = names.filter { !w.seen.contains($0) }
            if notify, !new.isEmpty, AppState.shared.prefs.notifySeen {
                let first = new.map { $0.components(separatedBy: " ").first ?? $0 }
                let who = first.count == 1 ? first[0] : first.dropLast().joined(separator: ", ") + " og " + first.last!
                print("[set] \(who) har set din besked: \(d.subject)")
                Notifier.shared.post("\(who) har set din besked", d.subject,
                                     url: URL(string: "viggoplus://thread/\(d.id)"))
            }
            list[k]?.seen = Array(Set(w.seen + names))
            list[k]?.total = r.total
        } else {
            list[k] = Watch(message: last.id, seen: names, total: r.total, since: Date())
        }
        // Keep the list short.
        if list.count > 40 { for (key, _) in list.sorted(by: { $0.value.since < $1.value.since }).prefix(list.count - 40) { list[key] = nil } }
        all = list
    }
}
