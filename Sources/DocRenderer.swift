import AppKit
import SwiftUI

/// `ViggoPlus --render-docs <dir>` draws the panel and the settings pages with made-up demo data
/// into PNGs for the README. No real account, names or schedule are used.
@MainActor
enum DocRenderer {
    static var outDir: String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--render-docs"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func run(_ state: AppState, dir: String) async {
        DemoData.load(state)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        snap(MenuView().environmentObject(state), name: "panel", dir: dir, panel: true)

        StatusPill.shared.done("Lektie klaret") {}
        snap(MenuView().environmentObject(state), name: "panel-pill", dir: dir, panel: true)
        StatusPill.shared.working("Markerer...")
        snap(MenuView().environmentObject(state), name: "panel-pill-working", dir: dir, panel: true)
        StatusPill.shared.dismiss()

        state.selectedFriend = state.friends.first?.id
        snap(MenuView().environmentObject(state), name: "panel-friend", dir: dir, panel: true)
        state.selectedFriend = nil

        snap(WeekView().environmentObject(state), name: "week", dir: dir, size: NSSize(width: 1040, height: 720))
        snap(Form { FocusSection() }.formStyle(.grouped).environmentObject(state), name: "settings-fokus", dir: dir, size: NSSize(width: 560, height: 300))
        state.quietLogins = [QuietLogin(id: UUID(), name: "Ida", image: nil, stage: .skoleit),
                             QuietLogin(id: UUID(), name: "Noah", image: nil, stage: .failure("Forkert kodeord"))]
        snap(MenuView().environmentObject(state), name: "panel-login", dir: dir, panel: true)
        state.quietLogins = []
        let tomorrow = DateUtil.add(.day, 1, DateUtil.startOfDay(Date()))
        Deadlines.shared.showDemo([
            Deadline(id: "a", title: "Tilmelding til weekenden", due: tomorrow.addingTimeInterval(13 * 3600), hasTime: true, source: "tråd:1",
                     sourceTitle: "Weekendtilmelding", from: "Jan Lærer", snippet: "Husk deadline i morgen kl. 13.00", found: Date()),
            Deadline(id: "b", title: "Jobopslag til OSO", due: DateUtil.add(.day, 4, tomorrow), hasTime: false, source: "tråd:2",
                     sourceTitle: "OSO", from: "Heidi Lærer", snippet: "Deadline for jobopslaget er på tirsdag", found: Date()),
        ])
        snap(MenuView().environmentObject(state), name: "panel-deadlines", dir: dir, panel: true)
        state.offline = true
        snap(MenuView().environmentObject(state), name: "panel-offline", dir: dir, panel: true)
        state.offline = false
        Deadlines.shared.showDemo([])
        if let fysik = state.events.first(where: { $0.id == 4 }) {
            snap(LessonDetailView(e: fysik), name: "lesson", dir: dir)
        }

        let cur = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0").split(separator: ".").compactMap { Int($0) }
        Updater.shared.available = Updater.Release(
            version: cur.count >= 2 ? "\(cur[0]).\(cur[1] + 1).0" : "2.0.0", highlights: ["Uge-overblik med alle dine timer", "Fødselsdage i panelet", "Genvejstast til panelet"],
            page: URL(string: "https://github.com/otto-BigO/viggo-plus/releases")!, zip: URL(string: "https://example.com")!)
        snap(UpdateView(updater: Updater.shared), name: "update", dir: dir)
        Updater.shared.available = nil

        // The iPhone page with made-up state: halfway through the guide, then installed.
        PhoneInstaller.shared.loadDemo(done: false)
        snap(SettingsView(initial: .iphone).environmentObject(state), name: "settings-iphone-guide", dir: dir,
             size: NSSize(width: 680, height: 500))
        if ProcessInfo.processInfo.environment["VIGGO_PHONE_TALL"] != nil {
            // Only for checking the whole guide; not part of the README pictures.
            snap(PhoneTab().frame(width: 470, height: 1250).background(Color(nsColor: .windowBackgroundColor)),
                 name: "iphone-guide-tall", dir: dir, size: NSSize(width: 470, height: 1250))
        }
        if ProcessInfo.processInfo.environment["VIGGO_PHONE_TALL"] != nil {
            PhoneInstaller.shared.loadDemo(done: true, second: true)
            snap(PhoneTab().frame(width: 470, height: 1250).background(Color(nsColor: .windowBackgroundColor)),
                 name: "iphone-two", dir: dir, size: NSSize(width: 470, height: 1250))
        }
        PhoneInstaller.shared.loadDemo(done: true)
        for page in SettingsPage.allCases {
            snap(SettingsView(initial: page).environmentObject(state), name: "settings-\(page.slug)", dir: dir,
                 size: NSSize(width: 680, height: 500))
        }
        if ProcessInfo.processInfo.environment["VIGGO_CARD_SNAPS"] != nil {
            // Only for checking the sign-in card; not part of the README pictures.
            for (name, st) in [("card-skoleit", LoginStage.skoleit), ("card-ok", .success), ("card-fail", .failure("Forkert brugernavn eller adgangskode"))] {
                state.loginStageName = nil
                state.loginStage = st
                snap(SettingsView(initial: .konto).environmentObject(state), name: name, dir: dir, size: NSSize(width: 680, height: 500))
            }
            state.loginStage = nil
        }
        exit(0)
    }

    private static func snap<V: View>(_ view: V, name: String, dir: String, size: NSSize? = nil, panel: Bool = false) {
        let content: AnyView = panel
            ? AnyView(view.environment(\.controlActiveState, .key).background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Fomo.bg)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
            : AnyView(view.environment(\.controlActiveState, .key))
        let host = NSHostingView(rootView: content)
        var sz = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: sz)
        host.appearance = NSAppearance(named: .darkAqua)
        let win = KeyWindow(contentRect: NSRect(x: -30000, y: -30000, width: sz.width, height: sz.height),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = panel ? .clear : .windowBackgroundColor
        win.isOpaque = !panel
        win.contentView = host
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        for _ in 0..<15 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
        // The panel sizes itself once it has measured the day, which happens after the first layout.
        if size == nil {
            let settled = host.fittingSize
            if abs(settled.height - sz.height) > 0.5 {
                sz = settled
                host.frame = NSRect(origin: .zero, size: sz)
                win.setContentSize(sz)
                for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
            }
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sz.width * 2), pixelsHigh: Int(sz.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = sz
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        win.orderOut(nil)
    }
}

/// Lets an off-screen window count as the active one, so switches and selections draw in color.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
