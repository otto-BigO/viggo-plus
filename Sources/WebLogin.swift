import AppKit
import WebKit

/// Viggo's own login page in a window: UNI-Login, password or SkoleIT all work.
/// When the page lands inside Viggo, the session cookies are copied to the app.
@MainActor
final class WebLogin: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    struct Credentials { let username: String; let password: String }

    private var window: NSWindow?
    private var webView: WKWebView?
    private var onDone: (([HTTPCookie], Credentials?) -> Void)?
    private var captured: Credentials?

    /// Picks up what is typed into Viggo's own password form (only on the Viggo login page).
    private static let captureJS = """
    document.addEventListener('submit', function (e) {
      var f = e.target; if (!f || !f.querySelector) return;
      var u = f.querySelector('input[name="UserName"]'), p = f.querySelector('input[name="Password"]');
      if (u && p && u.value && p.value) {
        window.webkit.messageHandlers.viggoCreds.postMessage({ u: u.value, p: p.value });
      }
    }, true);
    """

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.request.url?.host == Config.baseURL.host,
              let d = message.body as? [String: String], let u = d["u"], let p = d["p"] else { return }
        captured = Credentials(username: u, password: p)
    }

    func show(store: WKWebsiteDataStore = .default(), title: String = "Log ind på Viggo",
              onDone: @escaping ([HTTPCookie], Credentials?) -> Void) {
        self.onDone = onDone
        captured = nil
        if let window { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        cfg.userContentController.add(WeakHandler(self), name: "viggoCreds")
        cfg.userContentController.addUserScript(WKUserScript(source: WebLogin.captureJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: cfg)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        let w = NSWindow(contentRect: wv.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.contentView = wv
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        webView = wv
        wv.load(URLRequest(url: URL(string: "/Basic/Account/Login", relativeTo: Config.baseURL)!.absoluteURL))
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host == Config.baseURL.host,
              !url.path.lowercased().contains("/account/") else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            Task { @MainActor in
                let viggo = cookies.filter { $0.domain.contains("viggo.dk") }
                let creds = self.captured
                self.captured = nil
                self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "viggoCreds")
                self.window?.orderOut(nil)
                self.window = nil
                self.webView = nil
                self.onDone?(viggo, creds)
            }
        }
    }

    func clearCookies() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let viggo = records.filter { $0.displayName.contains("viggo") }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: viggo) {}
        }
    }
}

/// Avoids a retain cycle between WKUserContentController and WebLogin.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(uc, didReceive: message)
    }
}
