#if os(macOS)
import AppKit
#else
import UIKit
#endif
import WebKit

/// Saved SkoleIT logins (yours and your friends'), in one file only your user can read.
/// Not in the Keychain: macOS asks for the Keychain password after every update of an
/// unsigned app, which would block logging in by itself in the background.
enum LoginStore {
    struct Login: Codable { var user: String; var pass: String }
    struct Data: Codable { var own: Login?; var friends: [String: Login] = [:] }

    private static var url: URL { CookieJar.dir.appendingPathComponent("logins.plist") }
    private static var cache: Data?

    static var data: Data {
        get {
            if let cache { return cache }
            let d = (try? Foundation.Data(contentsOf: url)).flatMap { try? PropertyListDecoder().decode(Data.self, from: $0) } ?? Data()
            cache = d
            return d
        }
        set {
            cache = newValue
            guard let bytes = try? PropertyListEncoder().encode(newValue) else { return }
            try? bytes.write(to: url, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

/// Your SkoleIT login. Only used by AutoLogin.
enum SkoleITLogin {
    private static var docs: Bool { CommandLine.arguments.contains("--render-docs") }   // screenshots never show your login

    static var username: String? { docs ? "navn1234@cloud.skoleit.dk" : LoginStore.data.own?.user }
    static var password: String? { docs ? "x" : LoginStore.data.own?.pass }
    static var isSet: Bool { username != nil && password != nil }

    /// "otto1161" becomes "otto1161@cloud.skoleit.dk". A full address is kept as it is.
    static func normalize(_ user: String) -> String {
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty || u.contains("@") ? u : u + "@cloud.skoleit.dk"
    }

    static func save(username: String, password: String) {
        LoginStore.data.own = .init(user: normalize(username), pass: password)
    }

    static func clear() { LoginStore.data.own = nil }
}

/// A friend's SkoleIT login, saved under the friend's id. Only used by AutoLogin.
enum FriendLogin {
    static func get(_ id: UUID) -> (user: String, pass: String)? {
        LoginStore.data.friends[id.uuidString].map { ($0.user, $0.pass) }
    }

    static func has(_ id: UUID) -> Bool { get(id) != nil }

    static func save(_ id: UUID, username: String, password: String) {
        LoginStore.data.friends[id.uuidString] = .init(user: SkoleITLogin.normalize(username), pass: password)
    }

    static func remove(_ id: UUID) { LoginStore.data.friends[id.uuidString] = nil }
}

/// Where a login is right now, for the sign-in card.
enum LoginStage: Equatable {
    case saving, viggo, unilogin, skoleit, verifying, success, failure(String)

    /// 0...4 for the step dots.
    var step: Int {
        switch self {
        case .saving: return 0
        case .viggo: return 1
        case .unilogin: return 2
        case .skoleit: return 3
        case .verifying, .success, .failure: return 4
        }
    }

    #if os(macOS)
    private static let device = "din Mac"
    #else
    private static let device = "din iPhone"
    #endif

    var text: String {
        switch self {
        case .saving: return "Gemmer sikkert på \(Self.device)"
        case .viggo: return "Forbinder til Viggo"
        case .unilogin: return "UNI-Login"
        case .skoleit: return "Logger ind hos SkoleIT"
        case .verifying: return "Bekræfter"
        case .success: return "Sessionen er gemt på \(Self.device)"
        case .failure(let why): return why
        }
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
    #if os(macOS)
    private var window: NSWindow?
    #endif
    private var done: ((AutoLoginResult) -> Void)?
    private var timeout: Task<Void, Never>?
    private var username = ""
    private var password = ""
    private var submitted = false
    private var steps = 0
    /// Dry run: walk the chain and stop at the filled-in SkoleIT form without pressing "Log på".
    private var dryRun = false
    var log: [String] = []
    /// Called as the login moves through Viggo, UNI-Login and SkoleIT.
    var onStage: ((LoginStage) -> Void)?

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
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 720), configuration: cfg)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        #if os(macOS)
        // A window far off screen keeps the page running at full speed without showing anything.
        let w = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 720),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        w.contentView = wv
        w.orderBack(nil)
        window = w
        #else
        // On the iPhone the web view sits invisibly in the app's window, so the page keeps running.
        wv.isUserInteractionEnabled = false
        wv.alpha = 0.01
        let host = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        host?.insertSubview(wv, at: 0)
        #endif
        webView = wv
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.finish(.failure("Login tog for lang tid"))
        }
        note("start")
        onStage?(.viggo)
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
        #if os(macOS)
        window?.orderOut(nil)
        window = nil
        #else
        webView?.removeFromSuperview()
        #endif
        webView = nil
        password = ""
        switch r {
        case .success: note("ok"); onStage?(.success)
        case .failure(let why): note("fejl: \(why)"); onStage?(.failure(why))
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
            onStage?(submitted ? .verifying : .unilogin)
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
            onStage?(submitted ? .verifying : .skoleit)
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

    /// Clicks when the button shows up. Viggo sometimes forwards the page by itself first
    /// (when the old session is still half alive), so give it a few seconds before giving up.
    private func click(_ wv: WKWebView, _ selector: String, or failure: String) async {
        let js = "const b = document.querySelector(sel); if (!b) return false; b.click(); return true;"
        let page = wv.url
        for _ in 0..<16 {
            guard done != nil, wv.url == page else { return }   // finished, or the page moved on by itself
            if (try? await wv.callAsyncJavaScript(js, arguments: ["sel": selector], contentWorld: .page) as? Bool) == true { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        if done != nil, wv.url == page { finish(.failure(failure)) }
    }
}
