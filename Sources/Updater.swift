import AppKit
import SwiftUI

/// Checks GitHub for a newer release and installs it in place: downloads the zipped app,
/// swaps it in after Viggo+ quits, and opens the new version. No DMG needed.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "otto-BigO/viggo-plus"

    struct Release {
        let version: String
        let highlights: [String]
        let page: URL
        let zip: URL
    }

    enum Phase: Equatable { case idle, downloading, installing, failed(String) }

    @Published var available: Release?
    @Published var phase: Phase = .idle
    @Published var lastResult = ""
    private var lastCheck = Date.distantPast
    private var window: NSWindow?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The first few "- " lines of the release notes, each cut to its first sentence.
    static func highlights(_ body: String) -> [String] {
        body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .prefix(3)
            .map { line in
                var t = String(line.dropFirst(2)).replacingOccurrences(of: "**", with: "")
                if let r = t.range(of: ". ") { t = String(t[..<r.lowerBound]) }
                if let r = t.range(of: ": ") { t = String(t[..<r.lowerBound]) }
                if let r = t.range(of: ", ") { t = String(t[..<r.lowerBound]) }
                return t.count > 60 ? String(t.prefix(58)) + "…" : t.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
    }

    /// Automatic checks run at most every 6 hours and skip a version you said "Senere" to.
    func checkIfDue() {
        guard Prefs.shared.autoUpdate, Date().timeIntervalSince(lastCheck) > 6 * 3600 else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        lastCheck = Date()
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = o["tag_name"] as? String,
                  let page = (o["html_url"] as? String).flatMap(URL.init(string:)),
                  let zip = (o["assets"] as? [[String: Any]])?
                    .first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })?["browser_download_url"] as? String,
                  let zipURL = URL(string: zip) else {
                if manual { lastResult = "Kunne ikke læse den nyeste version" }
                return
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Updater.isNewer(version, than: current) else {
                available = nil
                if manual { lastResult = "Du har den nyeste version (\(current))" }
                return
            }
            let r = Release(version: version, highlights: Updater.highlights(o["body"] as? String ?? ""), page: page, zip: zipURL)
            available = r
            lastResult = "Version \(version) er klar"
            if manual || Prefs.shared.dismissedVersion != version { show() }
        } catch {
            if manual { lastResult = "Kunne ikke tjekke: \(error.localizedDescription)" }
        }
    }

    func show() {
        guard available != nil else { return }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: UpdateView(updater: self)))
            w.title = "Opdatering"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func later() {
        if let v = available?.version { Prefs.shared.dismissedVersion = v }
        window?.close()
    }

    func install() {
        guard let r = available else { return }
        phase = .downloading
        Task {
            do {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("ViggoPlusUpdate-\(UUID().uuidString)")
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let (tmp, resp) = try await URLSession.shared.download(from: r.zip)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ViggoError.unexpected("Download fejlede") }
                let zip = work.appendingPathComponent("update.zip")
                try fm.moveItem(at: tmp, to: zip)
                phase = .installing
                try Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
                guard let app = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }),
                      let info = Bundle(url: app)?.infoDictionary,
                      info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                      let v = info["CFBundleShortVersionString"] as? String, v == r.version else {
                    throw ViggoError.unexpected("Den hentede app ser forkert ud")
                }
                try Updater.run("/usr/bin/codesign", ["--verify", "--deep", app.path])
                try? Updater.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])

                // Swap the app once this process has quit, then open the new one.
                let dest = Bundle.main.bundleURL.path
                let script = work.appendingPathComponent("swap.sh")
                try """
                #!/bin/sh
                while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
                rm -rf "\(dest).old"
                mv "\(dest)" "\(dest).old" && mv "\(app.path)" "\(dest)" && rm -rf "\(dest).old" || mv "\(dest).old" "\(dest)"
                open "\(dest)"
                rm -rf "\(work.path)"
                """.write(to: script, atomically: true, encoding: .utf8)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", "nohup /bin/sh '\(script.path)' >/dev/null 2>&1 &"]
                try p.run()
                p.waitUntilExit()
                NSApp.terminate(nil)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ViggoError.unexpected("\((tool as NSString).lastPathComponent) fejlede") }
    }
}

struct UpdateView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
                      ?? NSApp.applicationIconImage)
                    .resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Viggo+ \(updater.available?.version ?? "") er klar").font(.system(size: 16, weight: .bold))
                    Text("Du har version \(updater.current)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if let r = updater.available, !r.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(r.highlights, id: \.self) { h in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                            Text(h).font(.system(size: 13))
                        }
                    }
                }
            }
            if let r = updater.available {
                Link("Læs mere på GitHub", destination: r.page).font(.system(size: 12))
            }
            if case .failed(let msg) = updater.phase {
                Text("Opdateringen fejlede: \(msg)").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                switch updater.phase {
                case .downloading, .installing:
                    ProgressView().controlSize(.small)
                    Text(updater.phase == .downloading ? "Henter…" : "Installerer…").font(.system(size: 12))
                default:
                    Button("Senere") { updater.later() }
                    Button("Opdater") { updater.install() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 18)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
