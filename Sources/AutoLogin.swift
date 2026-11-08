import AppKit
import WebKit
import Security

/// Your SkoleIT login, saved in the macOS Keychain. Only used by AutoLogin.
enum SkoleITLogin {
    private static let service = Config.bundleID + ".skoleit"
    private static let userKey = "autoLoginUser"

    static var username: String? {
        let u = UserDefaults.standard.string(forKey: userKey) ?? ""
        return u.isEmpty ? nil : u
    }

    static var isSet: Bool { username != nil && password != nil }

    static var password: String? {
        guard let user = username else { return nil }
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: user,
                                kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// "otto1161" becomes "otto1161@cloud.skoleit.dk". A full address is kept as it is.
    static func normalize(_ user: String) -> String {
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty || u.contains("@") ? u : u + "@cloud.skoleit.dk"
    }

    static func save(username raw: String, password: String) {
        let username = normalize(raw)
        clear()
        SecItemAdd([kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: username,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                    kSecValueData as String: Data(password.utf8)] as CFDictionary, nil)
        UserDefaults.standard.set(username, forKey: userKey)
    }

    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}

/// A friend's SkoleIT login, saved in the Keychain under the friend's id. Only used by AutoLogin.
enum FriendLogin {
    private static let service = Config.bundleID + ".skoleit.friend"

    static func get(_ id: UUID) -> (user: String, pass: String)? {
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: id.uuidString,
                                kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), let nl = s.firstIndex(of: "\n") else { return nil }
        return (String(s[..<nl]), String(s[s.index(after: nl)...]))
    }

    static func has(_ id: UUID) -> Bool { get(id) != nil }

    static func save(_ id: UUID, username: String, password: String) {
        remove(id)
        SecItemAdd([kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: id.uuidString,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                    kSecValueData as String: Data((SkoleITLogin.normalize(username) + "\n" + password).utf8)] as CFDictionary, nil)
    }

    static func remove(_ id: UUID) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: id.uuidString] as CFDictionary)
    }
}

enum AutoLoginResult {
    case success([HTTPCookie])
    case failure(String)
}

/// Logs in without you: Viggo › UNI-Login › Lokalt login › SkoleIT › username and password › back to Viggo.
/// Runs in a hidden web view that shares the login window's browser store, so UNI-Login
/// remembers SkoleIT as "Seneste login" and the SkoleIT session is reused when it is still valid.
@MainActor
final class AutoLogin: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var window: NSWindow?
    private var done: ((AutoLoginResult) -> Void)?
    private var timeout: Task<Void, Never>?
    private var username = ""
    private var password = ""
    private var submitted = false
    private var steps = 0
    /// Dry run: walk the chain and stop at the filled-in SkoleIT form without pressing "Log på".
    private var dryRun = false
    var log: [String] = []

    func run(username: String, password: String, dryRun: Bool = false,
             store: WKWebsiteDataStore? = nil) async -> AutoLoginResult {
        await withCheckedContinuation { cont in
            start(username: username, password: password, dryRun: dryRun, store: store ?? .default()) { cont.resume(returning: $0) }
        }
    }

    private func start(username: String, password: String, dryRun: Bool, store: WKWebsiteDataStore,
                       done: @escaping (AutoLoginResult) -> Void) {
        self.username = SkoleITLogin.normalize(username)
        self.password = password
        self.dryRun = dryRun
        self.done = done
        submitted = false
        steps = 0
        log = []
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: cfg)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        // A window far off screen keeps the page running at full speed without showing anything.
        let w = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 720),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        w.contentView = wv
        w.orderBack(nil)
        window = w
        webView = wv
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.finish(.failure("Login tog for lang tid"))
        }
        note("start")
        wv.load(URLRequest(url: URL(string: "/Basic/Account/Login", relativeTo: Config.baseURL)!.absoluteURL))
    }

    private func note(_ s: String) {
        log.append(s)
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--") && $0.contains("autologin") }) { print("[autologin] \(Date().formatted(date: .omitted, time: .standard)) \(s.prefix(120))") }
    }

    private func finish(_ r: AutoLoginResult) {
        guard let done else { return }
        self.done = nil
        timeout?.cancel()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
        webView = nil
        window = nil
        password = ""
        switch r {
        case .success: note("ok")
        case .failure(let why): note("fejl: \(why)")
        }
        done(r)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A redirect that replaces the page in flight is not an error.
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(.failure(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let u = webView.url { note("side: \(u.host ?? "")\(u.path)") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await step(webView) }
    }

    private func step(_ wv: WKWebView) async {
        guard done != nil, let url = wv.url, let host = url.host?.lowercased() else { return }
        steps += 1
        guard steps <= 15 else { return finish(.failure("Login kom ikke videre")) }
        let path = url.path.lowercased()

        // 4. Back inside Viggo: logged in.
        if host == Config.baseURL.host, !path.contains("/account/") {
            note("viggo")
            let cookies = await wv.configuration.websiteDataStore.httpCookieStore.allCookies()
            return finish(.success(cookies))
        }

        // 1. Viggo's front page: press "UNI Login".
        if host == Config.baseURL.host {
            note("viggo-login")
            return await click(wv, "button.unic", or: "UNI-Login-knappen findes ikke")
        }

        // 2. UNI-Login's chooser. Either "Seneste login: SkoleIT" is right there, or
        //    "Lokalt login" opens the list of schools, where we search for SkoleIT and pick it.
        if host.hasSuffix("unilogin.dk") {
            let js = """
            const sk = document.querySelector('button[name=selectedIdp][value=skoleit]');
            if (sk) {
              const s = document.getElementById('idp-search');
              if (s) { s.value = 'skoleit'; s.dispatchEvent(new Event('input', {bubbles: true})); }
              sk.click(); return 'skoleit';
            }
            const local = document.querySelector('button[name=showIdpList]');
            if (local) { local.click(); return 'lokalt'; }
            return 'ukendt:' + document.title + ' | ' + [...document.querySelectorAll('input,button,a')].map(e => `${e.tagName}:${e.name||e.id}=${(e.value||'').slice(0,30)}:${(e.innerText||'').trim().slice(0,30)}`).join(',') + ' | ' + document.body.innerText.trim().slice(0,300).replace(/\\s+/g,' ');
            """
            let r = (try? await wv.callAsyncJavaScript(js, contentWorld: .page) as? String) ?? "ukendt"
            note("unilogin: \(r)")
            if r.hasPrefix("ukendt"), !submitted { finish(.failure("UNI-Login viste en side Viggo+ ikke kender")) }
            return
        }

        // 3. SkoleIT: fill in username and password and press "Log på".
        if host.hasSuffix("skoleit.dk") {
            let js = """
            const err = (document.getElementById('errorText')?.innerText || '').trim();
            const u = document.getElementById('userNameInput'), p = document.getElementById('passwordInput');
            if (!u || !p) return submitted ? 'videre:' + document.title + ' | ' + [...document.querySelectorAll('input,button')].map(e => e.name || e.id).join(',') : 'ingen-felter';
            if (submitted && err) return 'fejl:' + err;
            if (submitted) return 'igen';
            const set = (el, v) => { el.focus(); el.value = v;
              el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); };
            set(u, user); set(p, pass);
            const k = document.getElementById('kmsiInput'); if (k) k.checked = true;
            if (dry) return 'udfyldt';
            if (window.Login && Login.submitLoginRequest) Login.submitLoginRequest();
            else document.getElementById('submitButton')?.click();
            return 'sendt';
            """
            let args: [String: Any] = ["user": username, "pass": password, "submitted": submitted, "dry": dryRun]
            let r = (try? await wv.callAsyncJavaScript(js, arguments: args, contentWorld: .page) as? String) ?? "ingen-felter"
            note("skoleit: \(r.hasPrefix("fejl:") ? "fejl" : r)")
            // After "Log på", SkoleIT shows a page that posts the answer back to UNI-Login by itself.
            if r.hasPrefix("videre:") { return }
            switch r {
            case "sendt": submitted = true
            case "udfyldt": finish(.failure("dry run: stoppede ved SkoleIT-formularen"))
            case "igen": finish(.failure("SkoleIT afviste login"))
            case "ingen-felter": finish(.failure("SkoleIT-siden har ændret sig"))
            default: finish(.failure("Forkert brugernavn eller adgangskode"))
            }
            return
        }

        // Anything in between (SAML hand-offs) posts itself on; only stop at a page that sits still.
        note("andet: \(host)")
    }

    private func click(_ wv: WKWebView, _ selector: String, or failure: String) async {
        let js = "const b = document.querySelector(sel); if (!b) return false; b.click(); return true;"
        let ok = (try? await wv.callAsyncJavaScript(js, arguments: ["sel": selector], contentWorld: .page) as? Bool) ?? false
        if !ok { finish(.failure(failure)) }
    }
}
