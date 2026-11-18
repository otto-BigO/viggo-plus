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
            MainActor.assumeIsolated { p.orderOut(nil); p.alphaValue = 1 }
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
                s.openSearch()
                try? await Task.sleep(for: .seconds(6))
                if let w = NSApp.windows.first(where: { $0.title == "Søg" }) {
                    capture(w, "search")
                }
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
