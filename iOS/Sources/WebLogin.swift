import UIKit
import WebKit

/// Viggo's own login page in a sheet: UNI-Login, SkoleIT or password all work.
/// Nothing typed here is read or stored by Viggo+. When the page lands inside Viggo,
/// the session cookies are handed to the app.
@MainActor
final class WebLogin: NSObject, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private var nav: UINavigationController?
    private var onDone: (([HTTPCookie]) -> Void)?
    /// Called when the sheet is closed without logging in.
    var onClose: (() -> Void)?

    func show(store: WKWebsiteDataStore? = nil, title: String = "Log ind på Viggo",
              onDone: @escaping ([HTTPCookie]) -> Void) {
        self.onDone = onDone
        guard nav == nil, let top = Self.topController() else { return }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store ?? .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        let vc = UIViewController()
        vc.view = wv
        vc.title = title
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(closed: true)
        })
        let n = UINavigationController(rootViewController: vc)
        n.presentationController?.delegate = self
        nav = n
        wv.load(URLRequest(url: URL(string: "/Basic/Account/Login", relativeTo: Config.baseURL)!.absoluteURL))
        top.present(n, animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host == Config.baseURL.host,
              !url.path.lowercased().contains("/account/") else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            Task { @MainActor in
                self.dismiss(closed: false)
                self.onDone?(cookies)
            }
        }
    }

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated { nav = nil; onClose?() }
    }

    private func dismiss(closed: Bool) {
        nav?.dismiss(animated: true)
        nav = nil
        if closed { onClose?() }
    }

    func clearCookies() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}
