import PDFKit
import AppKit
import Combine
import SwiftUI

/// Viggo+'s own menu bar item and panel. SwiftUI's MenuBarExtra can't be opened from code
/// (its button has no action, so the ⌥V hotkey did nothing); this one can.
@MainActor
final class PanelController: NSObject {
    static let shared = PanelController()

    private var item: NSStatusItem?
    private var panel: KeyPanel?
    private var host: PanelHost?
    private var monitors: [Any] = []
    private var bag: Set<AnyCancellable> = []
    /// Where the panel's top edge sits, so it grows downward when its content changes.
    private var top: CGFloat = 0

    var isShown: Bool { panel?.isVisible == true }
    /// How tall the panel window is: from just under the menu bar to the bottom of the screen
    /// the menu bar item is on.
    var room: CGFloat {
        if let test = testHeight { return test }
        return ((item?.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) - 4
    }
    /// A smaller screen, for --panel-test.
    var testHeight: CGFloat?

    /// The panel window's height, for the --panel-test hook.
    var windowHeight: CGFloat? { panel?.frame.height }

    /// Saves a picture of the panel window (for --panel-test with VIGGO_PANEL_SHOT=<dir>).
    func snapshot(to dir: String) {
        guard let v = panel?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("panel.png"))
    }
    /// Room around the card for its shadow.
    static let pad: CGFloat = 24
    /// The size of the visible card (the window around it is taller and see-through).
    var cardSize: CGSize = .zero
    /// Where the visible card sits on screen.
    var frame: NSRect? {
        guard isShown, let p = panel else { return nil }
        return NSRect(x: p.frame.minX + Self.pad, y: top - cardSize.height, width: cardSize.width, height: cardSize.height)
    }

    func setup() {
        guard item == nil else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.target = self
        it.button?.action = #selector(clicked)
        it.button?.imagePosition = .imageLeading
        item = it
        updateLabel()
        // The menu bar text follows the app state (time, lesson names, badge).
        AppState.shared.objectWillChange.merge(with: Prefs.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateLabel() } }
            .store(in: &bag)
    }

    private func updateLabel() {
        guard let b = item?.button else { return }
        let s = AppState.shared
        let img = NSImage(systemSymbolName: s.badgeCount > 0 ? "graduationcap.circle.fill" : "graduationcap.fill",
                          accessibilityDescription: "Viggo+")
        img?.isTemplate = true
        b.image = img
        let badge = s.badgeCount > 0 ? "  ✉︎ \(s.badgeCount)" : ""
        let text = s.menuTitle + badge
        let title = text.isEmpty ? "" : " " + text
        if b.title != title { b.title = title }
    }

    @objc private func clicked() { toggle() }

    func toggle() { isShown ? close() : show() }

    func show() {
        guard let button = item?.button, let bw = button.window else { return }
        let p = panel ?? makePanel()
        panel = p
        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame ?? .zero
        top = screen.maxY - 4
        let bottom = testHeight.map { top - $0 } ?? screen.minY
        // The window reaches from the menu bar to the bottom of the screen; the card inside grows
        // and shrinks with SwiftUI's own animation, so nothing jumps when a note folds out.
        let width = MenuView.width + 2 * Self.pad
        let x = min(max(screen.minX + 8, anchor.minX), screen.maxX - 8 - MenuView.width) - Self.pad
        p.setFrame(NSRect(x: x, y: bottom, width: width, height: top - bottom), display: true)
        NSApp.activate(ignoringOtherApps: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; p.animator().alphaValue = 1 }
        button.highlight(true)
        watch()
    }

    func close() {
        guard let p = panel, p.isVisible else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        item?.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; p.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                p.orderOut(nil); p.alphaValue = 1
                // Next time the panel opens it shows the day, not an old search.
                NotificationCenter.default.post(name: .panelClosed, object: nil)
            }
        }
    }

    private func makePanel() -> KeyPanel {
        let root = PanelCard()
        let h = PanelHost(rootView: AnyView(root))
        // The window is sized by show(), from the menu bar to the bottom of the screen. Left to
        // itself SwiftUI resized it to fit the card, and a card taller than the screen made AppKit
        // resize, re-measure and resize again until it gave up and the app crashed.
        h.sizingOptions = []
        host = h
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
                         styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.contentView = h
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false   // drawn by the card itself, so it follows the card while it animates
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return p
    }

    /// Closes on a click outside, on Escape, and when you switch to another app.
    private func watch() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            Task { @MainActor in PanelController.shared.close() }
        }) { monitors.append(m) }
        // A click on the see-through part of the panel's window (outside the card) closes it too.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in
            let c = PanelController.shared
            if let p = c.panel, e.window === p, let card = c.frame {
                let pt = p.convertPoint(toScreen: e.locationInWindow)
                if !card.contains(pt) { c.close(); return nil }
            }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { e in
            if e.keyCode == 53, PanelController.shared.panel?.isKeyWindow == true { PanelController.shared.close(); return nil }
            return e
        }) { monitors.append(m) }
    }
}

final class PanelHost: NSHostingView<AnyView> {}

/// The panel as you see it: the frosted card with a shadow, at the top of a see-through window.
/// Clicks on the see-through part fall through to whatever is behind it.
struct PanelCard: View {
    var body: some View {
        VStack(spacing: 0) {
            MenuView().environmentObject(AppState.shared)
                .layoutPriority(1)
                .background(VisualEffect())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { PanelController.shared.cardSize = $0 }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelController.pad)
        .padding(.bottom, PanelController.pad)
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        // Clicking one of Viggo+'s own windows (or the app losing focus) closes the panel, like a menu.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if NSApp.keyWindow !== self { PanelController.shared.close() }
            }
        }
    }
}

/// The frosted background the system uses for menus and popovers.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            PanelController.shared.setup()
            PhoneInstaller.shared.startRenewal()
        }
        // --focus-test: makes the Focus shortcuts if they are missing (click Tilføj genvej), then turns the
        // Focus on and off and checks with macOS that it really changed.
        if CommandLine.arguments.contains("--focus-test") {
            Task { @MainActor in
                let fs = FocusShortcuts.shared
                let m = fs.mode(Prefs.shared.focusMode)
                fflush(stdout); print("[fokus] tilstande: \(fs.modes.map(\.name)) valgt: \(m.name) klar: \(fs.ready(m))")
                if !fs.ready(m) { await fs.install(m); fflush(stdout); print("[fokus] \(fs.message)") }
                let n = FocusShortcuts.names(for: m)
                fflush(stdout); print("[fokus] til: \(await fs.run(n.on) ?? "ok")")
                try? await Task.sleep(for: .seconds(2))
                fflush(stdout); print("[fokus] aktiv nu: \(fs.activeModes() ?? [])")
                fflush(stdout); print("[fokus] fra: \(await fs.run(n.off) ?? "ok")")
                try? await Task.sleep(for: .seconds(2))
                fflush(stdout); print("[fokus] aktiv bagefter: \(fs.activeModes() ?? [])")
                exit(0)
            }
            return
        }
        // For testing the login transfer in the simulator: write the transfer file and quit.
        // For looking at Viggo's HTML from Terminal while building a parser: --peek /Basic/... prints the page.
        if let i = CommandLine.arguments.firstIndex(of: "--peek"), i + 1 < CommandLine.arguments.count {
            Task { @MainActor in
                CookieJar.restore()
                await AppState.shared.sync()
                if AppState.shared.needsLogin { _ = await AppState.shared.tryAutoLogin(force: true) }
                do {
                    let html = String(decoding: try await ViggoClient().getPublic(CommandLine.arguments[i + 1]), as: UTF8.self)
                    if CommandLine.arguments.contains("--parsed") {
                        let d = Parser.thread(html, id: 0)
                        print("[peek] til \(d.to) fra \(d.from)")
                        for m in d.messages { print("[peek] \(m.id) \(m.author)\(m.privateWith.map { " [privat med \($0)]" } ?? ""): læst af \(m.readBy.map { "\($0.name) (\($0.date))" })") }
                        if let r = Receipts.receipt(d) { print("[peek] set af \(r.readers.count) af \(r.total)") }
                    } else { print(html) }
                }
                catch { print("[peek] \(error.localizedDescription)") }
                exit(0)
            }
            return
        }
        // --upload-test: puts a tiny file in Viggo's temporary upload store, prints its id and deletes it again.
        // Sends no message.
        if CommandLine.arguments.contains("--upload-test") {
            Task { @MainActor in
                CookieJar.restore()
                await AppState.shared.sync()
                let c = ViggoClient()
                let f = Attachment(name: "viggoplus-test.txt", mime: "text/plain", data: Data("Viggo+ upload-test\n".utf8))
                do {
                    let id = try await c.uploadFile(f)
                    print("[upload] id \(id)")
                    await c.deleteTemporaryFile(id, name: f.name)
                    print("[upload] slettet igen")
                } catch { print("[upload] fejl: \(error.localizedDescription)") }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--write-transfer"), i + 1 < CommandLine.arguments.count {
            let t = LoginTransfer.make()
            try? PropertyListEncoder().encode(t).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            print("[transfer] own=\(t.own != nil) session=\(t.session != nil) friends=\(t.friends.count)")
            exit(0)
        }
        // For testing the iPhone installer from Terminal.
        if CommandLine.arguments.contains("--phone-status") || CommandLine.arguments.contains("--phone-install")
            || CommandLine.arguments.contains("--phone-send-login") || CommandLine.arguments.contains("--phone-renew") {
            Task { @MainActor in
                let p = PhoneInstaller.shared
                await p.refresh()
                if let i = CommandLine.arguments.firstIndex(of: "--device"), i + 1 < CommandLine.arguments.count {
                    p.pick(CommandLine.arguments[i + 1])
                }
                print("[phone] xcode=\(p.xcodeApp?.path ?? "-") firstLaunch=\(p.firstLaunchDone) ios=\(p.iosPlatform)")
                print("[phone] team=\(p.team.map { "\($0.id) \($0.name) free=\($0.free)" } ?? "-") signer=\(p.signer ?? "-")")
                for d in p.devices { print("[phone] device \(d.name) \(d.model) iOS \(d.os) wired=\(d.wired) reachable=\(d.reachable) paired=\(d.paired) devmode=\(d.developerMode.map(String.init) ?? "-")") }
                print("[phone] selected \(p.device.map { "\($0.id) \($0.name)" } ?? "-")")
                for (k, r) in p.records { print("[phone] record \(k) \(r.name) \(r.version) expires=\(r.expires) trusted=\(r.trusted.map(String.init) ?? "-")") }
                if CommandLine.arguments.contains("--phone-renew") {
                    // The same path the timer takes. VIGGO_RENEW_DUE=1 makes it renew now.
                    let before = p.records.mapValues(\.expires)
                    await p.renewIfNeeded()
                    for (k, r) in p.records { print("[phone] renew \(k) \(before[k] == r.expires ? "unchanged" : "renewed") expires=\(r.expires) error=\(p.error ?? "-")") }
                }
                if CommandLine.arguments.contains("--phone-send-login"), let d = p.device {
                    await p.sendLogin(to: d)
                    print("[phone] sent=\(p.loginSent ?? "-") error=\(p.error ?? "-")")
                }
                if CommandLine.arguments.contains("--phone-install"), let d = p.device {
                    let watch = Task { @MainActor in
                        var last = ""
                        while !Task.isCancelled {
                            if let j = p.job, "\(j.detail) \(Int(j.progress * 100))" != last {
                                last = "\(j.detail) \(Int(j.progress * 100))"
                                print("[phone] \(j.detail) \(Int(j.progress * 100))% \(Int(-j.started.timeIntervalSinceNow))s")
                            }
                            try? await Task.sleep(for: .milliseconds(300))
                        }
                    }
                    let ok = await p.install(d, quiet: CommandLine.arguments.contains("--quiet"))
                    watch.cancel()
                    print("[phone] ok=\(ok) error=\(p.error ?? "-") login=\(p.loginSent ?? "-")")
                    for (k, r) in p.records { print("[phone] record \(k) \(r.version) expires=\(r.expires) trusted=\(r.trusted.map(String.init) ?? "-")") }
                }
                exit(0)
            }
        }
        // --panel-test: opens the panel and switches between you and every friend a few times, the
        // way the account switcher does, and prints whether the card stays inside the screen. The
        // card used to grow past the screen and crash the app.
        if CommandLine.arguments.contains("--panel-test") {
            Task { @MainActor in
                let s = AppState.shared, c = PanelController.shared
                try? await Task.sleep(for: .seconds(8))
                // VIGGO_PANEL_HEIGHT=600 makes the window that tall, like a small screen.
                c.testHeight = ProcessInfo.processInfo.environment["VIGGO_PANEL_HEIGHT"].flatMap(Double.init).map { CGFloat($0) }
                c.show()
                let ids: [UUID?] = [nil] + s.friends.map { Optional($0.id) }
                for round in 0..<3 {
                    for id in ids {
                        withAnimation(.viggo) { s.selectedFriend = id }
                        try? await Task.sleep(for: .milliseconds(round == 0 ? 1500 : 400))
                        let name = id.flatMap { i in s.friends.first { $0.id == i }?.firstName } ?? "Mig"
                        let room = (c.windowHeight ?? 0) - PanelController.pad
                        print("[panel] \(name): kort \(Int(c.cardSize.height)) af \(Int(room)) pt \(c.cardSize.height <= room + 0.5 ? "ok" : "FOR HØJT")")
                        fflush(stdout)
                    }
                }
                s.selectedFriend = nil
                if let dir = ProcessInfo.processInfo.environment["VIGGO_PANEL_SHOT"] { c.snapshot(to: dir) }
                print("[panel] færdig uden nedbrud"); fflush(stdout)
                exit(0)
            }
        }
        // --panel-search-test: the panel's own search with VIGGO_SEARCH (default "musik"): the
        // results, a person's card and back to the day, saved as pictures in VIGGO_PANEL_SHOT.
        if CommandLine.arguments.contains("--panel-search-test") {
            Task { @MainActor in
                let c = PanelController.shared
                let dir = ProcessInfo.processInfo.environment["VIGGO_PANEL_SHOT"] ?? NSTemporaryDirectory()
                let q = ProcessInfo.processInfo.environment["VIGGO_SEARCH"] ?? "musik"
                try? await Task.sleep(for: .seconds(8))
                c.show()
                try? await Task.sleep(for: .seconds(2))
                func step(_ what: String, _ wait: Double = 1.5) async {
                    NotificationCenter.default.post(name: .panelSearchTest, object: what)
                    try? await Task.sleep(for: .seconds(wait))
                }
                let h0 = c.cardSize.height
                await step("open")
                c.snapshot(to: dir); try? FileManager.default.moveItem(atPath: dir + "/panel.png", toPath: dir + "/ps-empty.png")
                await step("query:" + q)
                c.snapshot(to: dir); try? FileManager.default.moveItem(atPath: dir + "/panel.png", toPath: dir + "/ps-results.png")
                await step("person")
                c.snapshot(to: dir); try? FileManager.default.moveItem(atPath: dir + "/panel.png", toPath: dir + "/ps-person.png")
                await step("close")
                c.snapshot(to: dir); try? FileManager.default.moveItem(atPath: dir + "/panel.png", toPath: dir + "/ps-day.png")
                print("[panelsøg] kortets højde før \(Int(h0)), efter \(Int(c.cardSize.height))")
                await step("open"); c.close()
                try? await Task.sleep(for: .seconds(1)); c.show()
                try? await Task.sleep(for: .seconds(1))
                NotificationCenter.default.post(name: .panelSearchTest, object: "state")
                try? await Task.sleep(for: .seconds(0.5))
                print("[panelsøg] færdig"); fflush(stdout)
                exit(0)
            }
        }
        // --roster-test [pdf ...]: day spans in made-up messages, your name in the given PDFs, and then the
        // real path on cached threads with PDFs (download with your login, read, the card's slots).
        if let i = CommandLine.arguments.firstIndex(of: "--roster-test") {
            Task { @MainActor in
                let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEE d/M HH:mm"
                let posted = DateUtil.cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 15, minute: 22))!
                for c in ["Mødetid er kl. 6.30 mandag til fredag, og det starter fra uge 48.", "Vi er der mandag til fredag kl. 8-9",
                          "I morgen kl. 13.00 er der fællesmøde.", "Turen er fredag til søndag"] {
                    let sp = Deadlines.spots(in: c, posted: posted).map { sp in
                        "\"\((c as NSString).substring(with: sp.range))\" -> \(sp.start.map { f.string(from: $0) } ?? sp.day.map { "dag " + f.string(from: $0) } ?? "-") x\(sp.days)"
                    }
                    print("[vagt] \(c)  =>  \(sp.joined(separator: ", "))")
                    if let s0 = Deadlines.spots(in: c, posted: posted).first, let u = PlanDraft.link(for: s0, title: "T", subject: "T"), let d = PlanDraft(url: u) {
                        print("[vagt]   boks: \(d.slots.map { f.string(from: $0.0) }.joined(separator: ", "))")
                    }
                }
                print("[vagt] uge 1 i nov -> \(f.string(from: Roster.monday(ofWeek: 1, near: posted)!)), uge 49 -> \(f.string(from: Roster.monday(ofWeek: 49, near: posted)!))")
                let name = ProcessInfo.processInfo.environment["VIGGO_ROSTER_NAME"] ?? AppState.shared.profile?.name ?? ""
                let message = "Mødetid er kl. 6.30 mandag til fredag"
                for path in CommandLine.arguments[(i + 1)...] where path.hasSuffix(".pdf") {
                    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { print("[vagt] kan ikke læse \(path)"); continue }
                    let lines = Roster.lines(doc)
                    let hit = Roster.find(name: name, lines: lines, message: message, subject: "Køkkenhold fra november til marts", posted: posted,
                                          file: 0, thread: 0, fileName: "x.pdf", from: "")
                    print("[vagt] \((path as NSString).lastPathComponent): \(lines.count) linjer, \(hit.map { "\($0.title): \($0.summary), \($0.slots.count) gange: " + $0.slots.map { f.string(from: $0.start) + "-" + DateUtil.hm($0.end) }.joined(separator: ", ") } ?? "ikke på listen")")
                }
                // Rooms: VIGGO_ROSTER_ROOM="Buen/B8" reads the cached PDFs as if that were your room.
                if let r = ProcessInfo.processInfo.environment["VIGGO_ROSTER_ROOM"]?.split(separator: "/").map(String.init), r.count == 2 {
                    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ViggoPlus/Filer")
                    for file in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where file.hasSuffix(".pdf") {
                        guard let doc = PDFDocument(url: dir.appendingPathComponent(file)) else { continue }
                        if let h = Roster.findRoom(house: r[0], room: r[1], lines: Roster.lines(doc), message: "", subject: "Nye rengøringsområder", posted: posted,
                                                   file: 0, thread: 0, fileName: file) {
                            print("[vagt] værelse \(r[1]) i \(file): \(h.title): \(h.summary), \(h.slots.count) gange: " + h.slots.prefix(6).map { f.string(from: $0.start) }.joined(separator: ", "))
                        }
                    }
                }
                CookieJar.restore()
                for d in Inbox.shared.details.values where d.messages.contains(where: { $0.files.contains { $0.name.lowercased().hasSuffix(".pdf") } }) {
                    await RosterStore.shared.check(d)
                    let hits = RosterStore.shared.hits[d.id] ?? []
                    print("[vagt] tråd \(d.id) \"\(d.subject)\": \(hits.isEmpty ? "ikke på listen" : hits.map { "\($0.title): \($0.summary), \($0.slots.count) gange, \($0.upcoming().count) kommende" }.joined(separator: "; "))")
                }
                for q in [ProcessInfo.processInfo.environment["VIGGO_TEXT_QUERY"] ?? "støvsuge", "13.00"] {
                    let r = RosterStore.shared.search(q)
                    print("[vagt] søg \"\(q)\": \(r.count) fund: " + r.prefix(4).map { "\($0.file ?? "besked") i \"\($0.subject)\": \($0.snippet.prefix(70))" }.joined(separator: " | "))
                }
                // The card with a made-up hit, before and after "Sæt i skema" (only made-up names and days).
                if let dir = ProcessInfo.processInfo.environment["VIGGO_PANEL_SHOT"] {
                    let start = DateUtil.cal.date(bySettingHour: 6, minute: 30, second: 0, of: DateUtil.add(.day, 7, Date()))!
                    let hit = RosterHit(file: -1, thread: -1, title: "Køkkenhold", summary: "uge 49 og 52, man til fre kl. 6.30",
                                        slots: (0..<5).map { .init(start: DateUtil.add(.day, $0, start), end: DateUtil.add(.day, $0, start).addingTimeInterval(3600)) }, from: "Test")
                    RosterStore.shared.hits[-1] = [hit]
                    let d = ThreadDetail(id: -1, subject: "Test", from: [], to: [], messages: [], canReplyAll: false)
                    let span = Deadlines.spots(in: "Mødetid er kl. 6.30 mandag til fredag fra uge 48", posted: posted).first!
                    let draft = PlanDraft(url: PlanDraft.link(for: span, title: "Køkkenhold", subject: "Køkkenhold")!)!
                    for name in ["roster-card", "roster-card-added", "roster-box"] {
                        let view = name == "roster-box" ? AnyView(PlanSheet(draft: draft) {}) : AnyView(RosterCard(detail: d).padding(20).frame(width: 560))
                        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
                        host.frame = NSRect(x: 0, y: 0, width: name == "roster-box" ? 330 : 560, height: name == "roster-box" ? 250 : 100)
                        let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: 80, y: 80), size: host.frame.size), styleMask: [.titled], backing: .buffered, defer: false)
                        w.contentView = host; w.isReleasedWhenClosed = false; w.orderFrontRegardless()
                        try? await Task.sleep(for: .seconds(1))
                        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                            host.cacheDisplay(in: host.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
                        }
                        w.orderOut(nil)
                        if name == "roster-card" { for s in hit.slots { Prefs.shared.planned.append(PlannedItem(title: hit.title, start: s.start, end: s.end, from: "Test")) } }
                    }
                    let inDay = AppState.shared.customEvents(on: start).contains { $0.title == "Køkkenhold" }
                    Prefs.shared.planned.removeAll { $0.from == "Test" }
                    print("[vagt] kort tegnet, i skemaet den dag: \(inDay), fjernet igen: \(!Prefs.shared.planned.contains { $0.from == "Test" })")
                }
                fflush(stdout)
                exit(0)
            }
        }
        // --plan-test: times in a made-up message, the box filled from one, adding it to the
        // schedule and taking it out again, plus pictures of the bubble and the box (VIGGO_PANEL_SHOT).
        if CommandLine.arguments.contains("--plan-test") {
            Task { @MainActor in
                let dir = ProcessInfo.processInfo.environment["VIGGO_PANEL_SHOT"] ?? NSTemporaryDirectory()
                let posted = DateUtil.cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
                let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEE d/M HH:mm"
                let cases = ["Vi mødes fredag d. 20/11 kl. 10-12 i hallen.", "I morgen kl. 13.00 er der fællesmøde.",
                             "Husk fredag. Vi starter kl. 9 i kantinen.", "Turen er d. 3. dec og vi tager afsted 8.15-9.45",
                             "Lav opgave 3.15 og 12.50 kr", "Mødet er 13:15 til 14:00", "den 20.11 er sidste frist"]
                for c in cases {
                    let sp = Deadlines.spots(in: c, posted: posted).map { sp in
                        "\"\((c as NSString).substring(with: sp.range))\" -> \(sp.start.map { f.string(from: $0) } ?? sp.day.map { "dag " + f.string(from: $0) } ?? "-")\(sp.end.map { "-" + DateUtil.hm($0) } ?? "")"
                    }
                    print("[plan] \(c)  =>  \(sp.isEmpty ? "intet" : sp.joined(separator: ", "))")
                }
                let text = "Hej alle. Vi mødes fredag d. 20/11 kl. 10-12 i hallen, så tag praktisk tøj med."
                let s0 = Deadlines.spots(in: text, posted: Date()).first!
                let title = Deadlines.title(subject: "Idrætsdag", sentence: text)
                guard let url = PlanDraft.link(for: s0, title: title, subject: "Idrætsdag"), let d = PlanDraft(url: url) else { print("[plan] intet link"); exit(1) }
                print("[plan] boks: \(d.title), \(f.string(from: d.start))-\(DateUtil.hm(d.end)), tid fra beskeden: \(d.timed)")
                let p = Prefs.shared, before = p.planned.count
                p.planned.append(PlannedItem(title: d.title, start: d.start, end: d.end, from: d.from))
                let inDay = AppState.shared.customEvents(on: d.start).contains { $0.title == d.title && $0.start == d.start }
                let inWeek = AppState.shared.weekItems(d.start, person: nil).contains { $0.title == d.title && $0.start == d.start }
                print("[plan] i skemaet den dag: \(inDay), i Uge-overblikket: \(inWeek)")
                // The bubble and the box, drawn off screen.
                @MainActor func draw<V: View>(_ v: V, _ size: NSSize, _ name: String) async {
                    let host = NSHostingView(rootView: v.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor)).environmentObject(AppState.shared))
                    host.frame = NSRect(origin: .zero, size: size)
                    let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: size.width, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
                    w.contentView = host; w.isReleasedWhenClosed = false
                    w.orderFrontRegardless()
                    try? await Task.sleep(for: .seconds(1.2))
                    defer { w.orderOut(nil) }
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
                    }
                }
                let msg = ThreadMessage(id: 1, authorID: -5, author: "Lærer Test", image: nil, date: "18. nov 2026 09:00", text: text, links: [])
                let mine = ThreadMessage(id: 2, authorID: -6, author: "Mig", image: nil, date: "18. nov 2026 09:05", text: "Super, ses i morgen kl. 8.15", links: [])
                await draw(VStack(spacing: 14) { MacBubble(m: msg, mine: false, subject: "Idrætsdag"); MacBubble(m: mine, mine: true, subject: "Idrætsdag") }.padding(20),
                     NSSize(width: 560, height: 220), "plan-bubble")
                await draw(PlanSheet(draft: d) {}, NSSize(width: 330, height: 220), "plan-box-added")
                // A real click on the time in the bubble, sent into the app's own window: does the box open?
                do {
                    let host = NSHostingView(rootView: MacBubble(m: msg, mine: false, subject: "Idrætsdag").padding(20)
                        .frame(width: 560, height: 160).background(Color(nsColor: .windowBackgroundColor)).environmentObject(AppState.shared))
                    host.frame = NSRect(x: 0, y: 0, width: 560, height: 160)
                    let w = NSWindow(contentRect: NSRect(x: 120, y: 200, width: 560, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
                    w.contentView = host; w.isReleasedWhenClosed = false
                    NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .seconds(1.2))
                    let before = NSApp.windows.count
                    func textView(in v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(textView).first }
                    var pops: [NSWindow] = []
                    if let tv = textView(in: host), let lm = tv.layoutManager, let tc = tv.textContainer,
                       let r = Deadlines.planLinks(text: text, posted: Deadlines.postedDate(msg.date), subject: "Idrætsdag").first?.range {
                        let glyphs = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                        let rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
                        let pt = tv.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
                        print("[plan] tiden står ved \(Int(pt.x)),\(Int(pt.y)) i vinduet")
                        func ev(_ t: NSEvent.EventType) -> NSEvent? {
                            NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                        }
                        // The text view tracks the mouse until it goes up, so the up waits in the queue first.
                        if let up = ev(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
                        let hit = w.contentView?.hitTest(w.contentView!.convert(pt, from: nil))
                        print("[plan] træffer: \(hit.map { String(describing: type(of: $0)) } ?? "intet"), nøglevindue \(w.isKeyWindow), aktiv \(NSApp.isActive)")
                        if let down = ev(.leftMouseDown) { w.sendEvent(down) }
                        try? await Task.sleep(for: .seconds(1.2))
                        pops = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
                        print("[plan] vinduer: \(NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) })")
                    } else { print("[plan] fandt ikke teksten") }
                    print("[plan] klik på tiden åbner boksen: \(!pops.isEmpty) (vinduer \(before) -> \(NSApp.windows.count))")
                    if let pw = pops.first, let v = pw.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("plan-popover.png"))
                    }
                    pops.forEach { $0.orderOut(nil) }; w.orderOut(nil)
                }
                let undated = PlanDraft(url: PlanDraft.link(for: Deadlines.spots(in: "Husk fredag", posted: Date()).first!, title: "Husk", subject: "")!)!
                await draw(PlanSheet(draft: undated) {}, NSSize(width: 330, height: 240), "plan-box-new")
                p.planned.removeAll { $0.title == d.title && $0.start == d.start }
                print("[plan] fjernet igen: \(p.planned.count == before), ikke i skemaet: \(!AppState.shared.customEvents(on: d.start).contains { $0.title == d.title })")
                print("[plan] færdig"); fflush(stdout)
                exit(0)
            }
        }
        // --feature-test: opens Søg (VIGGO_SEARCH) and the next lesson with a test note and photo,
        // saves pictures of the panel and both windows in VIGGO_PANEL_SHOT, then removes the note.
        if CommandLine.arguments.contains("--feature-test") {
            Task { @MainActor in
                let s = AppState.shared, c = PanelController.shared
                let dir = ProcessInfo.processInfo.environment["VIGGO_PANEL_SHOT"] ?? NSTemporaryDirectory()
                func shot(_ w: NSWindow?, _ name: String) {
                    guard let v = w?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("[feature] ingen \(name)"); return }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
                }
                // A real screen picture of a window (lists don't draw into cacheDisplay).
                func capture(_ w: NSWindow, _ name: String) {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", dir + "/" + name + ".png"]
                    try? p.run(); p.waitUntilExit()
                }
                try? await Task.sleep(for: .seconds(8))
                c.show()
                try? await Task.sleep(for: .seconds(2))
                var pack = MacPackSection.day(now: Date())
                var added: [PackItem] = []
                if pack == nil {
                    // Nothing to pack: add one test thing for the day the panel would show, and remove it after.
                    let d = DateUtil.cal.component(.hour, from: Date()) < 12 ? DateUtil.startOfDay(Date()) : DateUtil.add(.day, 1, DateUtil.startOfDay(Date()))
                    PackStore.shared.add("Testting fra --feature-test", on: d)
                    added = PackStore.shared.items(on: d).filter { $0.text == "Testting fra --feature-test" }
                    pack = MacPackSection.day(now: Date())
                    try? await Task.sleep(for: .seconds(1))
                }
                print("[feature] pakkeliste: \(pack.map { "\($0.1), \(PackStore.shared.items(on: $0.0).count) ting" } ?? "ingen dag")")
                c.snapshot(to: dir)
                for i in added { PackStore.shared.remove(i) }
                print("[feature] pakkeliste ryddet: \(added.count) testting fjernet")
                let notes = LessonNotes.shared
                if let e = s.events.filter({ $0.kind == .lesson && $0.end > Date() && !notes.hasNote($0) }).min(by: { $0.start < $1.start }) {
                    notes.setText("Testnote fra --feature-test", for: e)
                    let img = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { r in
                        NSColor.systemTeal.setFill(); r.fill(); return true
                    }
                    notes.add(img, for: e)
                    let n = notes.note(for: e)
                    print("[feature] note på \(e.title): \(n?.text ?? "-"), \(n?.photos.count ?? 0) billede(r), fil findes: \(n?.photos.first.map { FileManager.default.fileExists(atPath: notes.url(of: $0).path) } ?? false)")
                    s.openLesson(e)
                    try? await Task.sleep(for: .seconds(2))
                    shot(NSApp.windows.first { $0.title == e.title }, "lesson")
                    if let w = NSApp.windows.first(where: { $0.title == e.title }) { capture(w, "lesson-screen") }
                    for p in n?.photos ?? [] { notes.remove(photo: p, from: e) }
                    notes.setText("", for: e)
                    print("[feature] note fjernet igen: \(!notes.hasNote(e))")
                }
                let bad = BrowseHistory.selfTest()
                print("[nav] historik-test: \(bad.isEmpty ? "ok" : "fejl i " + bad.joined(separator: ", "))")
                s.openSearch()
                try? await Task.sleep(for: .seconds(6))
                let search = NSApp.windows.first(where: { $0.title == "Søg" })
                if let w = search { capture(w, "search") }
                // Walk the real window: a person, a link on their page, back, back, forward.
                let dirx = Directory.shared
                if let w = search, let me = s.profile?.id, let m = dirx.member(me) ?? dirx.members.first,
                   let g = dirx.groups(of: m.id).first {
                    @MainActor func send(_ what: String, _ f: Found? = nil) async {
                        NotificationCenter.default.post(name: .searchTest, object: what, userInfo: f.map { ["found": $0] })
                        try? await Task.sleep(for: .seconds(1.5))
                        print("[nav] \(what): vinduet viser \"\(w.title == m.name ? "personen" : w.title == g.name ? "gruppen" : w.title)\"")
                    }
                    await send("select", .person(m.id))
                    await send("link", .group(g.id))
                    await send("back")
                    await send("forward")
                    if let other = dirx.members.first(where: { $0.id != m.id && $0.kind == .student }) {
                        await send("select", .person(other.id))
                        print("[nav] efter klik i listen: \(w.title == other.name ? "den anden person" : w.title)")
                        await send("back")
                    }
                    await send("back")
                    // The big picture: load it the way the viewer does.
                    if m.imageBig ?? m.image != nil {
                        let host = NSHostingView(rootView: MacPhotoViewer(url: m.imageBig ?? m.image, fallback: m.image, name: m.name) {})
                        host.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
                        let pw = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                        pw.contentView = host
                        try? await Task.sleep(for: .seconds(4))
                        shot(pw, "photo")
                        pw.close()
                    } else { print("[photo] personen har intet billede") }
                } else { print("[nav] ingen person med en gruppe at gå til") }
                print("[feature] færdig"); fflush(stdout)
                exit(0)
            }
        }
        // --open-search opens Søg at start (VIGGO_SEARCH fills in the search).
        if CommandLine.arguments.contains("--open-search") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { AppState.shared.openSearch() } }
        }
        // For checking from Terminal: --open-messages opens the messages window at start.
        if CommandLine.arguments.contains("--open-messages") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { AppState.shared.openMessages(thread: ProcessInfo.processInfo.environment["VIGGO_THREAD"].flatMap(Int.init)) } }
        }
    }
}
