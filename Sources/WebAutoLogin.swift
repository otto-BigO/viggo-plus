import AppKit
import WebKit

/// Logs in exactly like a browser: loads Viggo's login page in a private, invisible web view,
/// fills in username + password and presses log ind. Never touches the main account's session.
@MainActor
final class WebAutoLogin: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var window: NSWindow?
    private var cont: CheckedContinuation<[HTTPCookie], Error>?
    private var submitted = false
    private var username = ""
    private var password = ""
    private var timeout: Task<Void, Never>?

    static func login(username: String, password: String) async throws -> [HTTPCookie] {
        let w = WebAutoLogin()
        return try await w.run(username: username, password: password)
    }

    private func run(username: String, password: String) async throws -> [HTTPCookie] {
        self.username = username
        self.password = password
        return try await withCheckedThrowingContinuation { c in
            cont = c
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
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
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finish(.failure(ViggoError.unexpected("Viggo svarede ikke")))
            }
        }
    }

    private func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s], options: [])
        let a = String(data: d, encoding: .utf8)!
        return String(a.dropFirst().dropLast())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let onLogin = url.path.lowercased().contains("/account/")
        if !onLogin {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                Task { @MainActor in self.finish(.success(cookies.filter { $0.domain.contains("viggo.dk") })) }
            }
            return
        }
        if submitted {
            webView.evaluateJavaScript("(document.body.innerHTML.match(/notice\\('warning',\\s*\"([^\"]+)\"/)||[])[1]||''") { r, _ in
                let msg = (r as? String ?? "").trimmingCharacters(in: .whitespaces)
                Task { @MainActor in
                    self.finish(.failure(msg.isEmpty ? ViggoError.badCredentials : ViggoError.unexpected(msg)))
                }
            }
            return
        }
        submitted = true
        let script = """
        (function(){
          var f = document.querySelector('form.unknown-user') || document.querySelector('form');
          if (!f) return 'noform';
          var u = f.querySelector('input[name="UserName"]'); var p = f.querySelector('input[name="Password"]');
          u.value = \(js(username)); p.value = \(js(password));
          f.submit(); return 'ok';
        })()
        """
        webView.evaluateJavaScript(script) { r, _ in
            if (r as? String) == "noform" {
                Task { @MainActor in self.finish(.failure(ViggoError.unexpected("Fandt ikke login-formularen"))) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ r: Result<[HTTPCookie], Error>) {
        guard let c = cont else { return }
        cont = nil
        timeout?.cancel()
        password = ""
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        let w = window, v = webView
        webView = nil
        window = nil
        c.resume(with: r)
        DispatchQueue.main.async { w?.orderOut(nil); w?.contentView = nil; _ = v }
    }
}
