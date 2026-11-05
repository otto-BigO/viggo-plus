import AppKit
import WebKit

/// Logs in like a browser in a private, invisible web view that never touches other sessions.
/// 1. Restores the saved cookies (incl. the SkoleIT / UNI-Login single sign-on session).
/// 2. On Viggo's login page it picks UNI-Login (SkoleIT runs through it).
/// 3. If SkoleIT still remembers the user, it bounces straight back logged in (no password).
///    Otherwise, if a saved password exists, it fills SkoleIT's form and submits.
@MainActor
final class WebAutoLogin: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var window: NSWindow?
    private var cont: CheckedContinuation<[HTTPCookie], Error>?
    private var username: String?
    private var password: String?
    private var clickedUni = false
    private var filledHosts: Set<String> = []
    private var timeout: Task<Void, Never>?
    private var trace: [String] = []

    static func login(cookies: [HTTPCookie] = [], username: String? = nil, password: String? = nil) async throws -> [HTTPCookie] {
        try await WebAutoLogin().run(cookies: cookies, username: username, password: password)
    }

    private func run(cookies: [HTTPCookie], username: String?, password: String?) async throws -> [HTTPCookie] {
        self.username = username
        self.password = password
        let store = WKWebsiteDataStore.nonPersistent()
        for c in cookies { await store.httpCookieStore.setCookie(c) }
        return try await withCheckedThrowingContinuation { c in
            cont = c
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = store
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: cfg)
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            wv.navigationDelegate = self
            let win = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 720),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.isReleasedWhenClosed = false
            win.contentView = wv
            win.orderBack(nil)
            window = win
            webView = wv
            wv.load(URLRequest(url: URL(string: "/Basic/Account/Login", relativeTo: Config.baseURL)!.absoluteURL))
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 35_000_000_000)
                self?.finish(.failure(ViggoError.notLoggedIn))
            }
        }
    }

    private func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s], options: [])
        let a = String(data: d, encoding: .utf8)!
        return String(a.dropFirst().dropLast())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, let host = url.host else { return }
        trace.append("\(host)\(url.path)")
        let isViggo = host == Config.baseURL.host
        if isViggo && !url.path.lowercased().contains("/account") {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                Task { @MainActor in self.finish(.success(cookies)) }
            }
            return
        }
        if isViggo {
            guard !clickedUni else { return }
            clickedUni = true
            // Same as pressing "Brug UNI Log ind" on the page.
            webView.evaluateJavaScript("""
            (function(){ var b = document.querySelector('button.unic'); if (b) { b.click(); return 'ok'; } return 'nobutton'; })()
            """) { r, _ in
                if (r as? String) == "nobutton" {
                    Task { @MainActor in self.finish(.failure(ViggoError.unexpected("Fandt ikke UNI-Login-knappen"))) }
                }
            }
            return
        }
        // On UNI-Login / SkoleIT pages.
        guard !filledHosts.contains(host + url.path) else { return }
        filledHosts.insert(host + url.path)
        attempt(webView, key: host + url.path, tries: 0)
    }

    private func attempt(_ webView: WKWebView, key: String, tries: Int) {
        guard cont != nil, webView.url.map({ ($0.host ?? "") + $0.path }) == key else { return }
        let user = username.map { js($0) } ?? "null"
        let pass = password.map { js($0) } ?? "null"
        webView.evaluateJavaScript("""
        (function(){
          var user = \(user), pass = \(pass);
          var pw = document.querySelector('input[type="password"]');
          if (pw) {
            if (!pass) return 'needpassword';
            var f = pw.form || document;
            var u = f.querySelector('input[type="email"], input[name*="user" i], input[name*="login" i], input[id*="user" i], input[type="text"]');
            if (u && user) { u.value = user; u.dispatchEvent(new Event('input', {bubbles:true})); }
            pw.value = pass; pw.dispatchEvent(new Event('input', {bubbles:true}));
            var b = document.getElementById('submitButton') || (pw.form && pw.form.querySelector('button[type="submit"], input[type="submit"], button:not([type])'));
            if (b) b.click(); else if (pw.form) pw.form.submit();
            return 'filled';
          }
          // Pick SkoleIT if UNI-Login asks which login to use.
          var links = Array.from(document.querySelectorAll('a, button'));
          var s = links.find(function(e){ return /skoleit/i.test(e.textContent + ' ' + (e.href||'') + ' ' + (e.id||'')); });
          if (s) { s.click(); return 'skoleit'; }
          var u2 = document.querySelector('input[type="email"], input[name*="user" i], input[type="text"]');
          if (u2 && user) {
            u2.value = user; u2.dispatchEvent(new Event('input', {bubbles:true}));
            var b2 = (u2.form && u2.form.querySelector('button[type="submit"], input[type="submit"], button:not([type])'));
            if (b2) { b2.click(); return 'username'; }
          }
          return 'wait';
        })()
        """) { r, _ in
            let res = r as? String ?? "?"
            Task { @MainActor in
                if res != "wait" || tries == 0 { self.trace.append("→\(res)") }
                if res == "needpassword" { self.finish(.failure(ViggoError.notLoggedIn)) }
                if res == "wait" && tries < 20 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self.attempt(webView, key: key, tries: tries + 1)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        trace.append("fail \(error.localizedDescription)")
    }

    private func finish(_ r: Result<[HTTPCookie], Error>) {
        guard let c = cont else { return }
        cont = nil
        timeout?.cancel()
        password = nil
        let line = "\(Date()) autologin \(username ?? "-") \((try? r.get()) != nil ? "OK" : "FAIL") \(trace.joined(separator: " "))\n"
        if let h = try? FileHandle(forWritingTo: ViggoClient.logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        let w = window, v = webView
        webView = nil
        window = nil
        c.resume(with: r)
        DispatchQueue.main.async { w?.orderOut(nil); w?.contentView = nil; _ = v }
    }
}
